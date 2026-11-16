import Foundation
import Synchronization

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case portuguese = "pt-BR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .portuguese: return "Português (Brasil)"
        }
    }

    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .portuguese: return Locale(identifier: "pt_BR")
        }
    }
}

nonisolated enum Localization {
    private static let current = Mutex(AppLanguage.english)

    static var language: AppLanguage {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    static var locale: Locale {
        language.locale
    }

    static func string(_ english: String, in language: AppLanguage) -> String {
        switch language {
        case .english: return english
        case .portuguese: return portuguese[english] ?? english
        }
    }

    static let portuguese: [String: String] = PortugueseStrings.table
}

nonisolated func localized(_ english: String) -> String {
    Localization.string(english, in: Localization.language)
}

nonisolated func localized(_ english: String, context: String) -> String {
    guard Localization.language != .english else { return english }
    let translated = localized("\(context):\(english)")
    return translated.hasPrefix("\(context):") ? localized(english) : translated
}

nonisolated func localized(_ format: String, _ arguments: any CVarArg...) -> String {
    String(format: localized(format), locale: Localization.locale, arguments: arguments)
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("MonoHubAppLanguageDidChange")
}
