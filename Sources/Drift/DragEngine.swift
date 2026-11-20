import AppKit
import ApplicationServices

/// Global mouse hook: hold the modifier and left-drag to move a window,
/// right-drag to resize it from the nearest corner, double-click to fill the screen.
final class DragEngine {
    static let shared = DragEngine()

    var onDragStateChange: ((Bool) -> Void)?
    var onDragFinished: (() -> Void)?

    private enum Mode { case move, resize }

    private struct Session {
        let window: AXUIElement
        let app: AXUIElement
        let mode: Mode
        let startMouse: CGPoint
        let startOrigin: CGPoint
        let startSize: CGSize
        let fromLeft: Bool
        let fromTop: Bool
        let restoreEnhancedUI: Bool
    }

    private struct Frame { var origin: CGPoint; var size: CGSize? }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var session: Session?
    private var swallowUntilUp = false
    private var savedFrames: [(window: AXUIElement, frame: CGRect)] = []
    private let systemWide = AXUIElementCreateSystemWide()
    private let minSize = CGSize(width: 160, height: 100)

    // AX writes happen off the event tap thread, latest-frame-wins, so the
    // cursor never waits on a slow app.
    private let writer = DispatchQueue(label: "dev.xevrion.drift.writer", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (AXUIElement, Frame)?
    private var writing = false

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .rightMouseDown, .rightMouseDragged, .rightMouseUp,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let engine = Unmanaged<DragEngine>.fromOpaque(refcon!).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .leftMouseDown, .rightMouseDown:
            let mode: Mode = type == .leftMouseDown ? .move : .resize
            guard Settings.enabled,
                  event.flags.intersection(Settings.relevantFlags) == Settings.modifier.flags
            else { return pass }

            if mode == .move, Settings.fillEnabled,
               event.getIntegerValueField(.mouseEventClickState) == 2,
               toggleFill(at: event.location) {
                swallowUntilUp = true
                return nil
            }

            guard mode == .move || Settings.resizeEnabled,
                  begin(mode: mode, at: event.location)
            else { return pass }
            return nil

        case .leftMouseDragged, .rightMouseDragged:
            guard let session else { return pass }
            update(session, mouse: event.location)
            return nil

        case .leftMouseUp, .rightMouseUp:
            if swallowUntilUp {
                swallowUntilUp = false
                return nil
            }
            guard session != nil else { return pass }
            end()
            return nil

        default:
            return pass
        }
    }

    private func begin(mode: Mode, at point: CGPoint) -> Bool {
        guard let window = window(at: point),
              let origin: CGPoint = window.value(kAXPositionAttribute),
              let size: CGSize = window.value(kAXSizeAttribute)
        else { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != getpid() else { return false }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(window, 0.25)

        // Apps with "enhanced UI" on (Chrome, Electron, anything a screen reader
        // touched) animate every AX frame change. Turn it off while dragging.
        let enhanced = app.bool("AXEnhancedUserInterface") ?? false
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()

        session = Session(
            window: window,
            app: app,
            mode: mode,
            startMouse: point,
            startOrigin: origin,
            startSize: size,
            fromLeft: point.x < origin.x + size.width / 2,
            fromTop: point.y < origin.y + size.height / 2,
            restoreEnhancedUI: enhanced
        )
        onDragStateChange?(true)
        return true
    }

    private func update(_ s: Session, mouse: CGPoint) {
        let dx = mouse.x - s.startMouse.x
        let dy = mouse.y - s.startMouse.y

        switch s.mode {
        case .move:
            enqueue(s.window, Frame(origin: CGPoint(x: s.startOrigin.x + dx, y: s.startOrigin.y + dy)))

        case .resize:
            var origin = s.startOrigin
            var size = s.startSize
            if s.fromLeft {
                size.width = max(minSize.width, s.startSize.width - dx)
                origin.x = s.startOrigin.x + s.startSize.width - size.width
            } else {
                size.width = max(minSize.width, s.startSize.width + dx)
            }
            if s.fromTop {
                size.height = max(minSize.height, s.startSize.height - dy)
                origin.y = s.startOrigin.y + s.startSize.height - size.height
            } else {
                size.height = max(minSize.height, s.startSize.height + dy)
            }
            enqueue(s.window, Frame(origin: origin, size: size))
        }
    }

    private func end() {
        guard let s = session else { return }
        session = nil
        writer.async {
            if s.restoreEnhancedUI { s.app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        }
        onDragStateChange?(false)
        onDragFinished?()
    }

    // MARK: - Fill screen

    /// Fills the visible area of the window's screen, or restores the frame it
    /// had before if it's already filling it.
    private func toggleFill(at point: CGPoint) -> Bool {
        guard let window = window(at: point),
              let origin: CGPoint = window.value(kAXPositionAttribute),
              let size: CGSize = window.value(kAXSizeAttribute),
              let screen = visibleFrame(containing: CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2))
        else { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != getpid() else { return false }

        let current = CGRect(origin: origin, size: size)
        let saved = savedFrames.firstIndex { CFEqual($0.window, window) }
        let target: CGRect
        if let saved, current.isClose(to: screen) {
            target = savedFrames.remove(at: saved).frame
        } else {
            if let saved { savedFrames.remove(at: saved) }
            savedFrames.append((window, current))
            if savedFrames.count > 64 { savedFrames.removeFirst() }
            target = screen
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
        writer.async {
            let enhanced = app.bool("AXEnhancedUserInterface") ?? false
            if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
            // Size, move, size again: the first resize can be clamped by the
            // screen edge before the window has moved.
            window.set(kAXSizeAttribute, target.size)
            window.set(kAXPositionAttribute, target.origin)
            window.set(kAXSizeAttribute, target.size)
            if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        }
        onDragFinished?()
        return true
    }

    /// The visible frame (minus menu bar and Dock) of the screen holding
    /// `point`, in AX coordinates: top-left origin of the primary screen.
    private func visibleFrame(containing point: CGPoint) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let flip = { (r: CGRect) in
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        let screen = NSScreen.screens.first { flip($0.frame).contains(point) } ?? NSScreen.main
        return screen.map { flip($0.visibleFrame) }
    }

    // MARK: - Coalesced AX writes

    private func enqueue(_ window: AXUIElement, _ frame: Frame) {
        lock.lock()
        pending = (window, frame)
        let shouldSchedule = !writing
        writing = true
        lock.unlock()
        if shouldSchedule { writer.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (window, frame) = pending else {
                writing = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            if let size = frame.size { window.set(kAXSizeAttribute, size) }
            window.set(kAXPositionAttribute, frame.origin)
        }
    }

    // MARK: - Window lookup

    private func window(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit
        else { return nil }

        if let window: AXUIElement = element.value(kAXWindowAttribute) { return window }

        for _ in 0..<32 {
            if element.string(kAXRoleAttribute) == kAXWindowRole as String { return element }
            guard let parent: AXUIElement = element.value(kAXParentAttribute) else { return nil }
            element = parent
        }
        return nil
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

// MARK: - AX helpers

private extension AXUIElement {
    func raw(_ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attr as CFString, &value) == .success else { return nil }
        return value
    }

    func value(_ attr: String) -> AXUIElement? {
        guard let v = raw(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func value(_ attr: String) -> CGPoint? {
        guard let v = raw(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    func value(_ attr: String) -> CGSize? {
        guard let v = raw(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    func string(_ attr: String) -> String? { raw(attr) as? String }
    func bool(_ attr: String) -> Bool? { (raw(attr) as? NSNumber)?.boolValue }

    func set(_ attr: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(self, attr as CFString, v) }
    }

    func set(_ attr: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(self, attr as CFString, v) }
    }

    func set(_ attr: String, _ value: CFBoolean) {
        AXUIElementSetAttributeValue(self, attr as CFString, value)
    }
}
