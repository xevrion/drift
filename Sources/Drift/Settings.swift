import AppKit

enum Modifier: String, CaseIterable, Identifiable {
    case command, option, control, controlOption

    var id: String { rawValue }

    var flags: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        case .controlOption: [.maskControl, .maskAlternate]
        }
    }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .controlOption: "⌃⌥"
        }
    }
}

/// Read straight from UserDefaults so the event tap always sees the latest values.
enum Settings {
    static let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    static var enabled: Bool { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
    static var resizeEnabled: Bool { UserDefaults.standard.object(forKey: Keys.resize) as? Bool ?? true }
    static var modifier: Modifier {
        UserDefaults.standard.string(forKey: Keys.modifier).flatMap(Modifier.init) ?? .command
    }

    enum Keys {
        static let enabled = "enabled"
        static let resize = "resizeEnabled"
        static let modifier = "modifier"
        static let drags = "dragCount"
    }
}
