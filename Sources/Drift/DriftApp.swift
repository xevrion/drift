import SwiftUI
import ServiceManagement

@main
struct DriftApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.isDragging ? "hand.raised.fill" : "macwindow.on.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var isDragging = false
    @Published var dragCount = UserDefaults.standard.integer(forKey: Settings.Keys.drags)
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var poll: Timer?

    init() {
        let engine = DragEngine.shared
        engine.onDragStateChange = { [weak self] dragging in
            Task { @MainActor in self?.isDragging = dragging }
        }
        engine.onDragFinished = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.dragCount += 1
                UserDefaults.standard.set(self.dragCount, forKey: Settings.Keys.drags)
            }
        }

        if !trusted {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        startEngineWhenTrusted()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Drift: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func startEngineWhenTrusted() {
        if AXIsProcessTrusted(), DragEngine.shared.start() {
            trusted = true
            return
        }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, AXIsProcessTrusted(), DragEngine.shared.start() else { return }
                self.trusted = true
                timer.invalidate()
            }
        }
    }
}
