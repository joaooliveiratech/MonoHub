import Foundation
import Observation

enum HubFeature: String, CaseIterable, Identifiable, Sendable {
    case systemMonitor
    case dynamicNotch
    case windowSwitcher
    case windowTiling
    case screenshot
    case aiQuota
    case cleanupTools
    case mediaConverter
    case productivity
    case audioControl
    case displayControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemMonitor: return localized("System Monitor")
        case .dynamicNotch: return localized("Dynamic Notch")
        case .windowSwitcher: return localized("Window Switcher")
        case .windowTiling: return localized("Window Tiling")
        case .screenshot: return localized("Screenshots")
        case .aiQuota: return localized("AI Quotas")
        case .cleanupTools: return localized("Clean and Uninstall")
        case .mediaConverter: return localized("Media Converter")
        case .productivity: return localized("Productivity & Clipboard")
        case .audioControl: return localized("Sound & Audio Control")
        case .displayControl: return localized("External Displays")
        }
    }

    var summary: String {
        switch self {
        case .systemMonitor:
            return localized("CPU, memory, network, battery, and sensor metrics in the menu bar.")
        case .dynamicNotch:
            return localized("Dynamic Island in the notch with media, calendar, timer, clipboard, and HUDs.")
        case .windowSwitcher:
            return localized("Window switcher with live thumbnails via ⌥ Tab.")
        case .windowTiling:
            return localized("Magnetic snapping and global shortcuts to organize windows.")
        case .screenshot:
            return localized("Area, window, and full screen capture with annotation editor, OCR, and pixel loupe.")
        case .aiQuota:
            return localized("Usage and limits of Claude, Codex, Antigravity, and other AI providers in the menu bar.")
        case .cleanupTools:
            return localized("Uninstaller, cleanup, project purge, and disk analyzer.")
        case .mediaConverter:
            return localized("Hardware-accelerated conversion and size reduction for videos and images.")
        case .productivity:
            return localized("URL router, UTM stripper, text snippets expansion, and fast 1-touch Bluetooth connection.")
        case .audioControl:
            return localized("Per-application volume mixer, persistent default microphone lock (anti-AirPods hijack), input gain, and default headphones.")
        case .displayControl:
            return localized("DDC/CI hardware brightness and volume, HiDPI scaling, PiP streaming, and external display management.")
        }
    }

    var resourceNote: String {
        switch self {
        case .systemMonitor:
            return localized("Periodic kernel sampling while widgets or panels are visible.")
        case .dynamicNotch:
            return localized("Always visible window; each internal feature only runs when enabled.")
        case .windowSwitcher:
            return localized("Keyboard event tap and thumbnail cache.")
        case .windowTiling:
            return localized("Global shortcuts and mouse drag monitor.")
        case .screenshot:
            return localized("Global shortcuts registered; capture, editor, and OCR only run on demand.")
        case .aiQuota:
            return localized("Queries active providers on configurable intervals without consuming tokens; pauses during sleep.")
        case .cleanupTools:
            return localized("Zero background cost; only runs when you open the tool.")
        case .mediaConverter:
            return localized("Zero background cost; processes on demand via Apple Silicon Media Engine and ImageIO.")
        case .productivity:
            return localized("Zero network; lightweight local event tap for snippets and AppleEvent router for links.")
        case .audioControl:
            return localized("Event-driven CoreAudio HAL observer; zero CPU when apps are at 100% volume.")
        case .displayControl:
            return localized("Lightweight event and display notification observer; zero background CPU when idle.")
        }
    }

    var systemImage: String {
        switch self {
        case .systemMonitor: return "waveform.path.ecg"
        case .dynamicNotch: return "rectangle.topthird.inset.filled"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .windowTiling: return "rectangle.split.2x2"
        case .screenshot: return ScreenshotStyle.symbol
        case .aiQuota: return AIQuotaStyle.symbol
        case .cleanupTools: return "sparkles"
        case .mediaConverter: return "arrow.triangle.2.circlepath"
        case .productivity: return "command.square.fill"
        case .audioControl: return "slider.horizontal.below.square.and.square.filled"
        case .displayControl: return "display"
        }
    }

    var sidebarItems: [SidebarItem] {
        switch self {
        case .systemMonitor: return [.monitor, .ports, .battery, .menuBar]
        case .dynamicNotch: return [.notch]
        case .windowSwitcher: return [.windowSwitcher]
        case .windowTiling: return [.windowTiling]
        case .screenshot: return [.screenshot]
        case .aiQuota: return [.aiQuota]
        case .cleanupTools: return [.uninstaller, .orphans, .cleaner, .purge, .env, .dupes, .startup, .disk, .maintenance, .history]
        case .mediaConverter: return [.mediaConverter]
        case .productivity: return [.urlRouter, .snippets, .bluetoothQuickConnect]
        case .audioControl: return [.audioControl]
        case .displayControl: return [.displayControl]
        }
    }

    var isEnabledByDefault: Bool {
        self != .displayControl
    }

    var runsInBackground: Bool {
        self != .cleanupTools && self != .mediaConverter
    }
}

@Observable
@MainActor
final class FeatureManager {
    static let shared = FeatureManager()

    static func defaultsKey(for feature: HubFeature) -> String {
        "MonoHub_feature_\(feature.rawValue)"
    }

    private let defaults: UserDefaults
    private(set) var enabledFeatures: Set<HubFeature>
    @ObservationIgnored private var appliedFeatures: Set<HubFeature> = []
    @ObservationIgnored private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var enabled = Set<HubFeature>()
        for feature in HubFeature.allCases {
            let key = Self.defaultsKey(for: feature)
            let stored = defaults.object(forKey: key) as? Bool
            if stored ?? feature.isEnabledByDefault {
                enabled.insert(feature)
            }
        }
        self.enabledFeatures = enabled
    }

    func isEnabled(_ feature: HubFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    func setEnabled(_ feature: HubFeature, _ enabled: Bool) {
        guard isEnabled(feature) != enabled else { return }
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
        defaults.set(enabled, forKey: Self.defaultsKey(for: feature))
        if hasStarted {
            apply(feature)
            MainWindowController.shared.updateActivationPolicy()
        }
    }

    func isRunning(_ feature: HubFeature) -> Bool {
        appliedFeatures.contains(feature)
    }

    func isSidebarItemAvailable(_ item: SidebarItem) -> Bool {
        guard let owner = HubFeature.allCases.first(where: { $0.sidebarItems.contains(item) }) else { return true }
        return isEnabled(owner)
    }

    func startEnabledFeatures() {
        guard !hasStarted else { return }
        hasStarted = true
        for feature in HubFeature.allCases {
            apply(feature)
        }
    }

    func stopAll() {
        for feature in HubFeature.allCases where appliedFeatures.contains(feature) {
            FeatureLifecycle.deactivate(feature)
        }
        appliedFeatures.removeAll()
        hasStarted = false
    }

    private func apply(_ feature: HubFeature) {
        let shouldRun = isEnabled(feature)
        let isRunning = appliedFeatures.contains(feature)
        guard shouldRun != isRunning else { return }
        if shouldRun {
            appliedFeatures.insert(feature)
            FeatureLifecycle.activate(feature)
        } else {
            appliedFeatures.remove(feature)
            FeatureLifecycle.deactivate(feature)
        }
    }
}

@MainActor
protocol FeatureModule {
    static func activate()
    static func deactivate()
}

@MainActor
enum FeatureLifecycle {
    private static func module(for feature: HubFeature) -> (any FeatureModule.Type)? {
        switch feature {
        case .systemMonitor: SystemMonitorFeature.self
        case .dynamicNotch: NotchFeature.self
        case .windowSwitcher: SwitcherFeature.self
        case .windowTiling: TilingFeature.self
        case .screenshot: ScreenshotFeature.self
        case .aiQuota: AIQuotaFeature.self
        case .productivity: ProductivityFeature.self
        case .audioControl: AudioControlFeature.self
        case .displayControl: DisplayControlFeature.self
        case .cleanupTools: CleanupFeature.self
        case .mediaConverter: MediaConverterFeature.self
        }
    }

    static func activate(_ feature: HubFeature) {
        module(for: feature)?.activate()
    }

    static func deactivate(_ feature: HubFeature) {
        module(for: feature)?.deactivate()
    }
}
