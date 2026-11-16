import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return localized("System")
        case .light: return localized("Light", context: "theme")
        case .dark: return localized("Dark", context: "theme")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@Observable
@MainActor
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appTheme = "MonoHub_appTheme"
        static let keepRunningInBackgroundOnQuit = "MonoHub_keepRunningInBackgroundOnQuit"
        static let soundOnCompletion = "MonoHub_soundOnCompletion"
        static let language = "MonoHub_language"
    }

    var systemIsDark: Bool {
        if let style = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String {
            return style.caseInsensitiveCompare("Dark") == .orderedSame
        }
        guard let app = NSApp else { return false }
        return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var resolvedColorScheme: ColorScheme {
        switch appTheme {
        case .system:
            return systemIsDark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var appTheme: AppTheme {
        didSet {
            defaults.set(appTheme.rawValue, forKey: Keys.appTheme)
            applyTheme()
        }
    }

    func applyTheme() {
        guard let app = NSApp else { return }
        app.appearance = appTheme.nsAppearance
        let targetAppearance = appTheme.nsAppearance
        for window in app.windows {
            window.appearance = targetAppearance
            window.invalidateShadow()
            window.contentView?.needsDisplay = true
        }
    }

    var keepRunningInBackgroundOnQuit: Bool {
        didSet { defaults.set(keepRunningInBackgroundOnQuit, forKey: Keys.keepRunningInBackgroundOnQuit) }
    }

    var soundOnCompletion: Bool {
        didSet { defaults.set(soundOnCompletion, forKey: Keys.soundOnCompletion) }
    }

    var language: AppLanguage {
        didSet {
            Localization.language = language
            defaults.set(language.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: language)
        }
    }

    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("MonoHub: launch at login update failed: \(error.localizedDescription)")
            }
        }
    }

    private init() {
        let storedTheme = defaults.string(forKey: Keys.appTheme).flatMap(AppTheme.init(rawValue:)) ?? .system
        self.appTheme = storedTheme

        self.keepRunningInBackgroundOnQuit = defaults.object(forKey: Keys.keepRunningInBackgroundOnQuit) == nil ? true : defaults.bool(forKey: Keys.keepRunningInBackgroundOnQuit)
        self.soundOnCompletion = defaults.object(forKey: Keys.soundOnCompletion) == nil ? true : defaults.bool(forKey: Keys.soundOnCompletion)

        let storedLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .portuguese
        self.language = storedLanguage
        Localization.language = storedLanguage

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.appTheme == .system {
                    self.applyTheme()
                }
            }
        }

        applyTheme()
    }

    func playCompletionSound() {
        guard soundOnCompletion else { return }
        NSSound(named: "Glass")?.play()
    }

    func openFolderPicker(title: String = "Escolher Pasta") -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }
}
