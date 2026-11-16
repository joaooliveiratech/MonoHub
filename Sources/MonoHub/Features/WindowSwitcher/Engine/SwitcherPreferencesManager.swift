import CoreGraphics
import Foundation
import Observation
import ServiceManagement

nonisolated protocol SwitcherPreferenceOption: RawRepresentable, CaseIterable, Identifiable, Sendable where RawValue == String {
    var displayName: String { get }
}

extension SwitcherPreferenceOption {
    nonisolated var id: String { rawValue }
}

nonisolated enum ShortcutPreference: String, SwitcherPreferenceOption {
    case optionTab
    case commandTab
    case both

    var displayName: String {
        switch self {
        case .optionTab: "⌥ Option + Tab"
        case .commandTab: "⌘ Command + Tab"
        case .both: localized("⌥ Tab and ⌘ Tab")
        }
    }

    var shortName: String {
        switch self {
        case .optionTab: "⌥ Tab"
        case .commandTab: "⌘ Tab"
        case .both: "⌥ Tab / ⌘ Tab"
        }
    }

    var hint: String {
        switch self {
        case .optionTab: localized("Option + Tab does not interfere with the native macOS switcher.")
        case .commandTab: localized("Command + Tab replaces the native macOS switcher.")
        case .both: localized("Option + Tab and Command + Tab open the switcher; Command + Tab replaces macOS native.")
        }
    }
}

nonisolated enum DisplayModePreference: String, SwitcherPreferenceOption {
    case compact
    case fullscreen

    var displayName: String {
        switch self {
        case .compact: localized("Floating panel")
        case .fullscreen: localized("Full screen")
        }
    }
}

nonisolated enum ThumbnailSizePreference: String, SwitcherPreferenceOption {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: localized("Small")
        case .medium: localized("Medium")
        case .large: localized("Large")
        }
    }

    func maximum(isFullscreen: Bool) -> CGSize {
        let base = switch self {
        case .small: CGSize(width: 224, height: 140)
        case .medium: CGSize(width: 288, height: 180)
        case .large: CGSize(width: 352, height: 220)
        }
        let scale: CGFloat = isFullscreen ? 1.25 : 1
        return CGSize(width: base.width * scale, height: base.height * scale)
    }
}

nonisolated enum ScreenTargetPreference: String, SwitcherPreferenceOption {
    case mouseLocation
    case activeWindow

    var displayName: String {
        switch self {
        case .mouseLocation: localized("Under cursor")
        case .activeWindow: localized("With active window")
        }
    }
}

@MainActor
protocol SwitcherPreferencesProviding: AnyObject {
    var shortcut: ShortcutPreference { get set }
    var displayMode: DisplayModePreference { get set }
    var thumbnailSize: ThumbnailSizePreference { get set }
    var screenTarget: ScreenTargetPreference { get set }
    var accent: AccentPreference { get set }
    var showQuickShortcuts: Bool { get set }
    var showMinimizedWindows: Bool { get set }
    var groupBrowserTabs: Bool { get set }
    var currentSpaceOnly: Bool { get set }
    var useRecentOrdering: Bool { get set }
    var confirmDestructiveActions: Bool { get set }
    var showMenuBarIcon: Bool { get set }
    var launchAtLogin: Bool { get set }
    var showAppTabs: Bool { get }
    var isFullscreen: Bool { get }
    func toggleDisplayMode()
    func restoreDefaults()
}

@Observable
final class SwitcherPreferencesManager: SwitcherPreferencesProviding {
    static let shared = SwitcherPreferencesManager()

    private enum Key {
        static let shortcut = "monotab_shortcut_preference"
        static let displayMode = "monotab_display_mode"
        static let thumbnailSize = "monotab_thumbnail_size"
        static let showMinimized = "monotab_show_minimized"
        static let groupBrowserTabs = "monotab_group_browser_tabs"
        static let currentSpaceOnly = "monotab_current_space_only"
        static let showMenuBarIcon = "monotab_show_menu_bar_icon"
        static let screenTarget = "monotab_screen_target"
        static let showQuickShortcuts = "monotab_show_quick_shortcuts"
        static let accent = "monotab_accent"
        static let recentOrdering = "monotab_recent_ordering"
        static let confirmDestructive = "monotab_confirm_destructive"
    }

    private let defaults = UserDefaults.standard

    var shortcut: ShortcutPreference {
        didSet {
            guard shortcut != oldValue else { return }
            defaults.set(shortcut.rawValue, forKey: Key.shortcut)
            SwitcherHotkeyManager.shared.setShortcutPreference(shortcut)
        }
    }

    var displayMode: DisplayModePreference {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    var thumbnailSize: ThumbnailSizePreference {
        didSet { defaults.set(thumbnailSize.rawValue, forKey: Key.thumbnailSize) }
    }

    var screenTarget: ScreenTargetPreference {
        didSet { defaults.set(screenTarget.rawValue, forKey: Key.screenTarget) }
    }

    var accent: AccentPreference {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    var showQuickShortcuts: Bool {
        didSet { defaults.set(showQuickShortcuts, forKey: Key.showQuickShortcuts) }
    }

    var showMinimizedWindows: Bool {
        didSet { defaults.set(showMinimizedWindows, forKey: Key.showMinimized) }
    }

    var groupBrowserTabs: Bool {
        didSet { defaults.set(groupBrowserTabs, forKey: Key.groupBrowserTabs) }
    }

    var currentSpaceOnly: Bool {
        didSet { defaults.set(currentSpaceOnly, forKey: Key.currentSpaceOnly) }
    }

    var useRecentOrdering: Bool {
        didSet { defaults.set(useRecentOrdering, forKey: Key.recentOrdering) }
    }

    var confirmDestructiveActions: Bool {
        didSet { defaults.set(confirmDestructiveActions, forKey: Key.confirmDestructive) }
    }

    var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                isRevertingLaunchAtLogin = true
                launchAtLogin = oldValue
                isRevertingLaunchAtLogin = false
            }
        }
    }

    @ObservationIgnored private var isRevertingLaunchAtLogin = false

    var showAppTabs: Bool { !groupBrowserTabs }

    var isFullscreen: Bool { displayMode == .fullscreen }

    var maxThumbnail: CGSize { thumbnailSize.maximum(isFullscreen: isFullscreen) }

    private init() {
        let defaults = UserDefaults.standard
        shortcut = defaults.option(Key.shortcut, default: .both)
        displayMode = defaults.option(Key.displayMode, default: .compact)
        thumbnailSize = defaults.option(Key.thumbnailSize, default: .medium)
        screenTarget = defaults.option(Key.screenTarget, default: .mouseLocation)
        accent = defaults.option(Key.accent, default: .system)
        showQuickShortcuts = defaults.flag(Key.showQuickShortcuts, default: true)
        showMinimizedWindows = defaults.flag(Key.showMinimized, default: false)
        currentSpaceOnly = defaults.flag(Key.currentSpaceOnly, default: true)
        showMenuBarIcon = defaults.flag(Key.showMenuBarIcon, default: true)
        useRecentOrdering = defaults.flag(Key.recentOrdering, default: true)
        confirmDestructiveActions = defaults.flag(Key.confirmDestructive, default: true)
        groupBrowserTabs = defaults.flag(Key.groupBrowserTabs, default: true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .compact ? .fullscreen : .compact
    }

    func restoreDefaults() {
        shortcut = .both
        displayMode = .compact
        thumbnailSize = .medium
        screenTarget = .mouseLocation
        accent = .system
        showQuickShortcuts = true
        showMinimizedWindows = false
        groupBrowserTabs = true
        currentSpaceOnly = true
        useRecentOrdering = true
        confirmDestructiveActions = true
        showMenuBarIcon = true
    }
}

private extension UserDefaults {
    func flag(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }

    func option<Option: SwitcherPreferenceOption>(_ key: String, default fallback: Option) -> Option {
        string(forKey: key).flatMap(Option.init(rawValue:)) ?? fallback
    }
}
