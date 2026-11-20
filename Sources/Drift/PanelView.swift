import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(Settings.Keys.enabled) private var enabled = true
    @AppStorage(Settings.Keys.resize) private var resize = true
    @AppStorage(Settings.Keys.fill) private var fill = true
    @AppStorage(Settings.Keys.modifier) private var modifier: Modifier = .command
    @Namespace private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !state.trusted {
                permissionCard
                    .transition(.blurReplace)
            }

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    row("Drag windows", "hand.point.up.left", isOn: $enabled)
                    row("Right-drag to resize", "arrow.up.left.and.arrow.down.right", isOn: $resize)
                        .disabled(!enabled)
                    row("Double-click to fill screen", "arrow.up.backward.and.arrow.down.forward.rectangle", isOn: $fill)
                        .disabled(!enabled)
                    row("Launch at login", "power", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.setLaunchAtLogin($0) }
                    ))
                }
            }

            modifierPicker

            footer
        }
        .padding(18)
        .frame(width: 300)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: state.trusted)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: modifier)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isDragging ? "hand.raised.fill" : "macwindow.on.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.accentColor.opacity(enabled ? 0.45 : 0)).interactive(), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Drift")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(enabled ? "Hold \(modifier.symbol) and drag any window" : "Paused")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs Accessibility access", systemImage: "lock.shield")
                .font(.system(size: 13, weight: .semibold))
            Text("Drift moves windows through the Accessibility API. Turn it on, and Drift starts by itself.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { state.openAccessibilitySettings() }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 16))
    }

    private func row(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private var modifierPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modifier")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Modifier.allCases) { option in
                        let selected = option == modifier
                        Button {
                            modifier = option
                        } label: {
                            Text(option.symbol)
                                .font(.system(size: 15, weight: selected ? .semibold : .regular, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            selected ? .regular.tint(.accentColor.opacity(0.55)).interactive() : .regular.interactive(),
                            in: .capsule
                        )
                        .glassEffectID(option.id, in: glass)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(state.dragCount) windows drifted")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(state.dragCount)))
                .animation(.snappy, value: state.dragCount)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .keyboardShortcut("q")
        }
    }
}
