import Foundation
import Observation

nonisolated struct DisplayDeviceConfig: Codable, Sendable, Equatable {
    var dimmingMode: DisplayDimmingMode = .combined
    var minHardwareBrightness: Float = 0.0
    var maxHardwareBrightness: Float = 1.0
    var minHardwareVolume: Float = 0.0
    var maxHardwareVolume: Float = 1.0
    var brightnessCurve: BrightnessCurve = .perceptual
    var isBrightnessEnabled: Bool = true
    var isAudioEnabled: Bool = true
    var allowSubZeroOverlayDimming: Bool = true
    var colorAdjustment: DisplayColorAdjustment = DisplayColorAdjustment()
    var xdrConfig: XDRUpscalingConfig = XDRUpscalingConfig()
    var favoriteResolutionModeIDs: [Int32] = []
    var customScaledResolutions: [CustomScaledResolutionSpec] = CustomScaledResolutionSpec.standardPresets

    enum CodingKeys: String, CodingKey {
        case dimmingMode
        case minHardwareBrightness
        case maxHardwareBrightness
        case minHardwareVolume
        case maxHardwareVolume
        case brightnessCurve
        case isBrightnessEnabled
        case isAudioEnabled
        case allowSubZeroOverlayDimming
        case colorAdjustment
        case xdrConfig
        case favoriteResolutionModeIDs
        case customScaledResolutions
    }

    init(
        dimmingMode: DisplayDimmingMode = .combined,
        minHardwareBrightness: Float = 0.0,
        maxHardwareBrightness: Float = 1.0,
        minHardwareVolume: Float = 0.0,
        maxHardwareVolume: Float = 1.0,
        brightnessCurve: BrightnessCurve = .perceptual,
        isBrightnessEnabled: Bool = true,
        isAudioEnabled: Bool = true,
        allowSubZeroOverlayDimming: Bool = true,
        colorAdjustment: DisplayColorAdjustment = DisplayColorAdjustment(),
        xdrConfig: XDRUpscalingConfig = XDRUpscalingConfig(),
        favoriteResolutionModeIDs: [Int32] = [],
        customScaledResolutions: [CustomScaledResolutionSpec] = CustomScaledResolutionSpec.standardPresets
    ) {
        self.dimmingMode = dimmingMode
        self.minHardwareBrightness = max(0.0, min(0.5, minHardwareBrightness))
        self.maxHardwareBrightness = max(0.5, min(1.0, maxHardwareBrightness))
        self.minHardwareVolume = max(0.0, min(0.5, minHardwareVolume))
        self.maxHardwareVolume = max(0.5, min(1.0, maxHardwareVolume))
        self.brightnessCurve = brightnessCurve
        self.isBrightnessEnabled = isBrightnessEnabled
        self.isAudioEnabled = isAudioEnabled
        self.allowSubZeroOverlayDimming = allowSubZeroOverlayDimming
        self.colorAdjustment = colorAdjustment
        self.xdrConfig = xdrConfig
        self.favoriteResolutionModeIDs = favoriteResolutionModeIDs
        self.customScaledResolutions = customScaledResolutions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dimmingMode = try container.decodeIfPresent(DisplayDimmingMode.self, forKey: .dimmingMode) ?? .combined
        let minB = try container.decodeIfPresent(Float.self, forKey: .minHardwareBrightness) ?? 0.0
        let maxB = try container.decodeIfPresent(Float.self, forKey: .maxHardwareBrightness) ?? 1.0
        let minV = try container.decodeIfPresent(Float.self, forKey: .minHardwareVolume) ?? 0.0
        let maxV = try container.decodeIfPresent(Float.self, forKey: .maxHardwareVolume) ?? 1.0
        self.minHardwareBrightness = max(0.0, min(0.5, minB))
        self.maxHardwareBrightness = max(0.5, min(1.0, maxB))
        self.minHardwareVolume = max(0.0, min(0.5, minV))
        self.maxHardwareVolume = max(0.5, min(1.0, maxV))
        self.brightnessCurve = try container.decodeIfPresent(BrightnessCurve.self, forKey: .brightnessCurve) ?? .perceptual
        self.isBrightnessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBrightnessEnabled) ?? true
        self.isAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAudioEnabled) ?? true
        self.allowSubZeroOverlayDimming = try container.decodeIfPresent(Bool.self, forKey: .allowSubZeroOverlayDimming) ?? true
        self.colorAdjustment = try container.decodeIfPresent(DisplayColorAdjustment.self, forKey: .colorAdjustment) ?? DisplayColorAdjustment()
        self.xdrConfig = try container.decodeIfPresent(XDRUpscalingConfig.self, forKey: .xdrConfig) ?? XDRUpscalingConfig()
        self.favoriteResolutionModeIDs = try container.decodeIfPresent([Int32].self, forKey: .favoriteResolutionModeIDs) ?? []
        self.customScaledResolutions = try container.decodeIfPresent([CustomScaledResolutionSpec].self, forKey: .customScaledResolutions) ?? CustomScaledResolutionSpec.standardPresets
    }
}

@Observable
@MainActor
final class DisplayControlPreferences {
    static let shared = DisplayControlPreferences()

    @ObservationIgnored private let defaults: UserDefaults

    var isDDCEnabled: Bool {
        didSet { defaults.set(isDDCEnabled, forKey: "MonoHub_Display_isDDCEnabled") }
    }

    var targetMode: DDCTargetMode {
        didSet { defaults.set(targetMode.rawValue, forKey: "MonoHub_Display_targetMode") }
    }

    var enableVolumeKeys: Bool {
        didSet { defaults.set(enableVolumeKeys, forKey: "MonoHub_Display_enableVolumeKeys") }
    }

    var syncBrightnessWithBuiltIn: Bool {
        didSet { defaults.set(syncBrightnessWithBuiltIn, forKey: "MonoHub_Display_syncBrightnessWithBuiltIn") }
    }

    var globalDimmingMode: DisplayDimmingMode {
        didSet { defaults.set(globalDimmingMode.rawValue, forKey: "MonoHub_Display_globalDimmingMode") }
    }

    var ddcWriteSleepMs: Int {
        didSet { defaults.set(ddcWriteSleepMs, forKey: "MonoHub_Display_ddcWriteSleepMs") }
    }

    var ddcReadSleepMs: Int {
        didSet { defaults.set(ddcReadSleepMs, forKey: "MonoHub_Display_ddcReadSleepMs") }
    }

    var ddcRetryAttempts: Int {
        didSet { defaults.set(ddcRetryAttempts, forKey: "MonoHub_Display_ddcRetryAttempts") }
    }

    var readOnStartup: Bool {
        didSet { defaults.set(readOnStartup, forKey: "MonoHub_Display_readOnStartup") }
    }

    var showDisplayTitleInHUD: Bool {
        didSet { defaults.set(showDisplayTitleInHUD, forKey: "MonoHub_Display_showDisplayTitleInHUD") }
    }

    var primaryDisplayUUID: String {
        didSet { defaults.set(primaryDisplayUUID, forKey: "MonoHub_Display_primaryDisplayUUID") }
    }

    var isLayoutProtectionEnabled: Bool {
        didSet { defaults.set(isLayoutProtectionEnabled, forKey: "MonoHub_Display_isLayoutProtectionEnabled") }
    }

    var autoBlackoutBuiltInOnExternal: Bool {
        didSet { defaults.set(autoBlackoutBuiltInOnExternal, forKey: "MonoHub_Display_autoBlackoutBuiltInOnExternal") }
    }

    var showLowResolutionDuplicateModes: Bool {
        didSet { defaults.set(showLowResolutionDuplicateModes, forKey: "MonoHub_Display_showLowResolutionDuplicateModes") }
    }

    var virtualScreens: [VirtualScreenConfig] = [] {
        didSet { saveVirtualScreens() }
    }

    var savedLayoutAnchors: [DisplayLayoutAnchor] = [] {
        didSet { saveLayoutAnchors() }
    }

    var displayConfigs: [String: DisplayDeviceConfig] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.isDDCEnabled = defaults.object(forKey: "MonoHub_Display_isDDCEnabled") as? Bool ?? true
        if let rawTarget = defaults.string(forKey: "MonoHub_Display_targetMode"),
           let mode = DDCTargetMode(rawValue: rawTarget) {
            self.targetMode = mode
        } else {
            self.targetMode = .cursor
        }

        self.enableVolumeKeys = defaults.object(forKey: "MonoHub_Display_enableVolumeKeys") as? Bool ?? true
        self.syncBrightnessWithBuiltIn = defaults.bool(forKey: "MonoHub_Display_syncBrightnessWithBuiltIn")

        if let rawDimming = defaults.string(forKey: "MonoHub_Display_globalDimmingMode"),
           let mode = DisplayDimmingMode(rawValue: rawDimming) {
            self.globalDimmingMode = mode
        } else {
            self.globalDimmingMode = .combined
        }

        let writeSleep = defaults.integer(forKey: "MonoHub_Display_ddcWriteSleepMs")
        self.ddcWriteSleepMs = writeSleep > 0 ? max(5, min(100, writeSleep)) : 25

        let readSleep = defaults.integer(forKey: "MonoHub_Display_ddcReadSleepMs")
        self.ddcReadSleepMs = readSleep > 0 ? max(10, min(150, readSleep)) : 35

        let retries = defaults.integer(forKey: "MonoHub_Display_ddcRetryAttempts")
        self.ddcRetryAttempts = retries > 0 ? max(1, min(5, retries)) : 3

        self.readOnStartup = defaults.object(forKey: "MonoHub_Display_readOnStartup") as? Bool ?? true
        self.showDisplayTitleInHUD = defaults.object(forKey: "MonoHub_Display_showDisplayTitleInHUD") as? Bool ?? true
        self.primaryDisplayUUID = defaults.string(forKey: "MonoHub_Display_primaryDisplayUUID") ?? ""
        self.isLayoutProtectionEnabled = defaults.object(forKey: "MonoHub_Display_isLayoutProtectionEnabled") as? Bool ?? false
        self.autoBlackoutBuiltInOnExternal = defaults.object(forKey: "MonoHub_Display_autoBlackoutBuiltInOnExternal") as? Bool ?? false
        self.showLowResolutionDuplicateModes = defaults.object(forKey: "MonoHub_Display_showLowResolutionDuplicateModes") as? Bool ?? true

        loadConfigs()
        loadVirtualScreens()
        loadLayoutAnchors()
    }

    func config(for uuid: String) -> DisplayDeviceConfig {
        if let cfg = displayConfigs[uuid] {
            return cfg
        }
        return DisplayDeviceConfig(dimmingMode: globalDimmingMode)
    }

    func updateConfig(for uuid: String, _ modify: (inout DisplayDeviceConfig) -> Void) {
        var cfg = config(for: uuid)
        modify(&cfg)
        displayConfigs[uuid] = cfg
        saveConfigs()
    }

    private func loadConfigs() {
        guard let data = defaults.data(forKey: "MonoHub_Display_configsData"),
              let decoded = try? JSONDecoder().decode([String: DisplayDeviceConfig].self, from: data) else {
            return
        }
        self.displayConfigs = decoded
    }

    private func saveConfigs() {
        guard let data = try? JSONEncoder().encode(displayConfigs) else { return }
        defaults.set(data, forKey: "MonoHub_Display_configsData")
    }

    private func loadVirtualScreens() {
        guard let data = defaults.data(forKey: "MonoHub_Display_virtualScreensData"),
              let decoded = try? JSONDecoder().decode([VirtualScreenConfig].self, from: data) else {
            return
        }
        self.virtualScreens = decoded
    }

    private func saveVirtualScreens() {
        guard let data = try? JSONEncoder().encode(virtualScreens) else { return }
        defaults.set(data, forKey: "MonoHub_Display_virtualScreensData")
    }

    private func loadLayoutAnchors() {
        guard let data = defaults.data(forKey: "MonoHub_Display_layoutAnchorsData"),
              let decoded = try? JSONDecoder().decode([DisplayLayoutAnchor].self, from: data) else {
            return
        }
        self.savedLayoutAnchors = decoded
    }

    private func saveLayoutAnchors() {
        guard let data = try? JSONEncoder().encode(savedLayoutAnchors) else { return }
        defaults.set(data, forKey: "MonoHub_Display_layoutAnchorsData")
    }
}
