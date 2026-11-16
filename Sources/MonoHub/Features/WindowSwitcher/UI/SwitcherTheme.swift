import SwiftUI

nonisolated enum AccentPreference: String, SwitcherPreferenceOption {
    case system
    case blue
    case purple
    case teal
    case amber
    case pink
    case graphite

    var displayName: String {
        switch self {
        case .system: localized("System default")
        case .blue: localized("Blue")
        case .purple: localized("Purple")
        case .teal: localized("Teal")
        case .amber: localized("Amber")
        case .pink: localized("Pink")
        case .graphite: localized("Graphite")
        }
    }

    var color: Color {
        switch self {
        case .system: .accentColor
        case .blue: Color(red: 0.20, green: 0.55, blue: 0.98)
        case .purple: Color(red: 0.68, green: 0.38, blue: 0.96)
        case .teal: Color(red: 0.24, green: 0.74, blue: 0.72)
        case .amber: Color(red: 0.96, green: 0.68, blue: 0.22)
        case .pink: Color(red: 0.95, green: 0.35, blue: 0.62)
        case .graphite: Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }
}

private struct MonoAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

private struct MonoReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var monoAccent: Color {
        get { self[MonoAccentKey.self] }
        set { self[MonoAccentKey.self] = newValue }
    }

    var monoReduceMotion: Bool {
        get { self[MonoReduceMotionKey.self] }
        set { self[MonoReduceMotionKey.self] = newValue }
    }
}

extension View {
    func monoAnimation<Value: Equatable>(_ animation: Animation, value: Value, enabled: Bool) -> some View {
        self.animation(enabled ? animation : nil, value: value)
    }
}
