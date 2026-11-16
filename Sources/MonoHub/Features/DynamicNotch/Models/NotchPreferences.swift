import Foundation
import Combine
import Observation

nonisolated struct NotchEngineDemand: Equatable, Sendable {
    var media = false
    var calendar = false
    var reminders = false
    var battery = false
    var bluetooth = false
    var timer = false
    var mirror = false
    var systemHUD = false
    var statusItem = false
    var scrollMonitor = false
    var clipboard = false
    var teleprompter = false
    var aiQuota = false
    var systemStats = false

    static let none = NotchEngineDemand()
}

@Observable
@MainActor
final class NotchPreferences {
    static let shared = NotchPreferences()

    @ObservationIgnored private let defaults: UserDefaults

    var displayTargetMode: DisplayTargetMode {
        didSet { defaults.set(displayTargetMode.rawValue, forKey: "displayTargetMode") }
    }

    var customEnabledDisplayIDs: [String] {
        didSet { defaults.set(customEnabledDisplayIDs, forKey: "customEnabledDisplayIDs") }
    }

    var targetDisplayUUID: String {
        didSet { defaults.set(targetDisplayUUID, forKey: "targetDisplayUUID") }
    }

    var enableVirtualNotch: Bool {
        didSet { defaults.set(enableVirtualNotch, forKey: "enableVirtualNotch") }
    }

    var closedNotchWidth: CGFloat {
        didSet { defaults.set(closedNotchWidth, forKey: "closedNotchWidth") }
    }

    var closedNotchHeight: CGFloat {
        didSet { defaults.set(closedNotchHeight, forKey: "closedNotchHeight") }
    }

    var closedTopCornerRadius: CGFloat {
        didSet { defaults.set(closedTopCornerRadius, forKey: "closedTopCornerRadius") }
    }

    var closedBottomCornerRadius: CGFloat {
        didSet { defaults.set(closedBottomCornerRadius, forKey: "closedBottomCornerRadius") }
    }

    var openNotchWidth: CGFloat {
        didSet { defaults.set(openNotchWidth, forKey: "openNotchWidth") }
    }

    var openNotchHeight: CGFloat {
        didSet { defaults.set(openNotchHeight, forKey: "openNotchHeight") }
    }

    var autoAdjustHeight: Bool {
        didSet { defaults.set(autoAdjustHeight, forKey: "autoAdjustHeight") }
    }

    var openCornerRadius: CGFloat {
        didSet { defaults.set(openCornerRadius, forKey: "openCornerRadius") }
    }

    var enableHomeModule: Bool {
        didSet { defaults.set(enableHomeModule, forKey: "enableHomeModule") }
    }

    var showHomeMusicCard: Bool {
        didSet { defaults.set(showHomeMusicCard, forKey: "showHomeMusicCard") }
    }

    var showHomeCalendarCard: Bool {
        didSet { defaults.set(showHomeCalendarCard, forKey: "showHomeCalendarCard") }
    }

    var showHomeTimerCard: Bool {
        didSet { defaults.set(showHomeTimerCard, forKey: "showHomeTimerCard") }
    }

    var showHomeBatteryCard: Bool {
        didSet { defaults.set(showHomeBatteryCard, forKey: "showHomeBatteryCard") }
    }

    var showHomeBluetoothCard: Bool {
        didSet { defaults.set(showHomeBluetoothCard, forKey: "showHomeBluetoothCard") }
    }

    var showHomeClipboardCard: Bool {
        didSet { defaults.set(showHomeClipboardCard, forKey: "showHomeClipboardCard") }
    }

    var showHomeTeleprompterCard: Bool {
        didSet { defaults.set(showHomeTeleprompterCard, forKey: "showHomeTeleprompterCard") }
    }

    var showHomeAIQuotaCard: Bool {
        didSet { defaults.set(showHomeAIQuotaCard, forKey: "showHomeAIQuotaCard") }
    }

    var showHomeHeavyProcessCard: Bool {
        didSet { defaults.set(showHomeHeavyProcessCard, forKey: "showHomeHeavyProcessCard") }
    }

    var enableMusicModule: Bool {
        didSet { defaults.set(enableMusicModule, forKey: "enableMusicModule") }
    }

    var enableAudioModule: Bool {
        didSet { defaults.set(enableAudioModule, forKey: "enableAudioModule") }
    }

    var enableTimerModule: Bool {
        didSet { defaults.set(enableTimerModule, forKey: "enableTimerModule") }
    }

    var enableCalendarModule: Bool {
        didSet { defaults.set(enableCalendarModule, forKey: "enableCalendarModule") }
    }

    var enableRemindersModule: Bool {
        didSet { defaults.set(enableRemindersModule, forKey: "enableRemindersModule") }
    }

    var enableMirrorModule: Bool {
        didSet { defaults.set(enableMirrorModule, forKey: "enableMirrorModule") }
    }

    var enableBatteryModule: Bool {
        didSet { defaults.set(enableBatteryModule, forKey: "enableBatteryModule") }
    }

    var enableBluetoothModule: Bool {
        didSet { defaults.set(enableBluetoothModule, forKey: "enableBluetoothModule") }
    }

    var enableShelfModule: Bool {
        didSet { defaults.set(enableShelfModule, forKey: "enableShelfModule") }
    }

    var enableClipboardModule: Bool {
        didSet { defaults.set(enableClipboardModule, forKey: "enableClipboardModule") }
    }

    var clipboardHistoryLimit: Int {
        didSet { defaults.set(clipboardHistoryLimit, forKey: "clipboardHistoryLimit") }
    }

    var clipboardAutoPaste: Bool {
        didSet { defaults.set(clipboardAutoPaste, forKey: "clipboardAutoPaste") }
    }

    var clipboardClickAction: ClipboardClickAction {
        didSet { defaults.set(clipboardClickAction.rawValue, forKey: "clipboardClickAction") }
    }

    var enableTeleprompterModule: Bool {
        didSet { defaults.set(enableTeleprompterModule, forKey: "enableTeleprompterModule") }
    }

    var teleprompterSpeed: Double {
        didSet {
            defaults.set(teleprompterSpeed, forKey: "teleprompterSpeed")
        }
    }

    var teleprompterFontSize: Double {
        didSet {
            defaults.set(teleprompterFontSize, forKey: "teleprompterFontSize")
        }
    }

    var teleprompterShowFocusGuide: Bool {
        didSet {
            defaults.set(teleprompterShowFocusGuide, forKey: "teleprompterShowFocusGuide")
        }
    }

    var teleprompterKeepOpenWhilePlaying: Bool {
        didSet { defaults.set(teleprompterKeepOpenWhilePlaying, forKey: "teleprompterKeepOpenWhilePlaying") }
    }

    var teleprompterIsMirrored: Bool {
        didSet {
            defaults.set(teleprompterIsMirrored, forKey: "teleprompterIsMirrored")
        }
    }

    var teleprompterMirrorHorizontal: Bool {
        get { teleprompterIsMirrored }
        set { teleprompterIsMirrored = newValue }
    }

    var enableSystemHUD: Bool {
        didSet { defaults.set(enableSystemHUD, forKey: "enableSystemHUD") }
    }

    var showMusicLiveActivity: Bool {
        didSet { defaults.set(showMusicLiveActivity, forKey: "showMusicLiveActivity") }
    }

    var showTimerLiveActivity: Bool {
        didSet { defaults.set(showTimerLiveActivity, forKey: "showTimerLiveActivity") }
    }

    var showCalendarLiveActivity: Bool {
        didSet { defaults.set(showCalendarLiveActivity, forKey: "showCalendarLiveActivity") }
    }

    var showBatteryLiveActivity: Bool {
        didSet { defaults.set(showBatteryLiveActivity, forKey: "showBatteryLiveActivity") }
    }

    var showAIQuotaLiveActivity: Bool {
        didSet { defaults.set(showAIQuotaLiveActivity, forKey: "showAIQuotaLiveActivity") }
    }

    var showHeavyProcessLiveActivity: Bool {
        didSet { defaults.set(showHeavyProcessLiveActivity, forKey: "showHeavyProcessLiveActivity") }
    }

    var showQuotaResetPeek: Bool {
        didSet { defaults.set(showQuotaResetPeek, forKey: "showQuotaResetPeek") }
    }

    var showSystemAlertPeek: Bool {
        didSet { defaults.set(showSystemAlertPeek, forKey: "showSystemAlertPeek") }
    }

    var heavyProcessThreshold: Double {
        didSet { defaults.set(heavyProcessThreshold, forKey: "heavyProcessThreshold") }
    }

    var thermalAlertThreshold: Double {
        didSet { defaults.set(thermalAlertThreshold, forKey: "thermalAlertThreshold") }
    }

    var showClockWhenIdle: Bool {
        didSet { defaults.set(showClockWhenIdle, forKey: "showClockWhenIdle") }
    }

    var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: "hoverToExpand") }
    }

    var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: "hoverDelay") }
    }

    var autoCollapseDelay: Double {
        didSet { defaults.set(autoCollapseDelay, forKey: "autoCollapseDelay") }
    }

    var scrollAction: ScrollAction {
        didSet { defaults.set(scrollAction.rawValue, forKey: "scrollAction") }
    }

    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") }
    }

    var excludedAppBundleIDs: [String] {
        didSet { defaults.set(excludedAppBundleIDs, forKey: "excludedAppBundleIDs") }
    }

    var hideInFullScreenApps: Bool {
        didSet { defaults.set(hideInFullScreenApps, forKey: "hideInFullScreenApps") }
    }

    var activeTab: NotchTab {
        didSet { defaults.set(activeTab.rawValue, forKey: "activeTab") }
    }

    var homeCardOrder: [HomeCard] {
        didSet { defaults.set(homeCardOrder.map(\.rawValue), forKey: "homeCardOrder") }
    }

    var homePrioritizeActive: Bool {
        didSet { defaults.set(homePrioritizeActive, forKey: "homePrioritizeActive") }
    }

    var homeShowHeader: Bool {
        didSet { defaults.set(homeShowHeader, forKey: "homeShowHeader") }
    }

    var homeShowHeaderDate: Bool {
        didSet { defaults.set(homeShowHeaderDate, forKey: "homeShowHeaderDate") }
    }

    var homeShowHeaderBattery: Bool {
        didSet { defaults.set(homeShowHeaderBattery, forKey: "homeShowHeaderBattery") }
    }

    var homeShowHeaderClock: Bool {
        didSet { defaults.set(homeShowHeaderClock, forKey: "homeShowHeaderClock") }
    }

    var homeGridSingleColumn: Bool {
        didSet { defaults.set(homeGridSingleColumn, forKey: "homeGridSingleColumn") }
    }

    var bluetoothShowMacBattery: Bool {
        didSet { defaults.set(bluetoothShowMacBattery, forKey: "bluetoothShowMacBattery") }
    }

    var showBatteryWhenIdle: Bool {
        didSet { defaults.set(showBatteryWhenIdle, forKey: "showBatteryWhenIdle") }
    }

    var liveActivityPriority: [LiveActivityKind] {
        didSet { defaults.set(liveActivityPriority.map(\.rawValue), forKey: "liveActivityPriority") }
    }

    var liveActivityLayout: LiveActivityLayout {
        didSet { defaults.set(liveActivityLayout.rawValue, forKey: "liveActivityLayout") }
    }

    var showPausedTimerActivity: Bool {
        didSet { defaults.set(showPausedTimerActivity, forKey: "showPausedTimerActivity") }
    }

    var showTrackChangePeek: Bool {
        didSet { defaults.set(showTrackChangePeek, forKey: "showTrackChangePeek") }
    }

    var showTimerCompletionPeek: Bool {
        didSet { defaults.set(showTimerCompletionPeek, forKey: "showTimerCompletionPeek") }
    }

    var dynamicIslandHoverBounce: Bool {
        didSet { defaults.set(dynamicIslandHoverBounce, forKey: "dynamicIslandHoverBounce") }
    }

    var calendarLiveActivityLeadMinutes: Int {
        didSet { defaults.set(calendarLiveActivityLeadMinutes, forKey: "calendarLiveActivityLeadMinutes") }
    }

    var tabOrder: [NotchTab] {
        didSet { defaults.set(tabOrder.map(\.rawValue), forKey: "tabOrder") }
    }

    var tabLabelStyle: TabLabelStyle {
        didSet { defaults.set(tabLabelStyle.rawValue, forKey: "tabLabelStyle") }
    }

    var showNotchBorder: Bool {
        didSet { defaults.set(showNotchBorder, forKey: "showNotchBorder") }
    }

    var showNotchShadow: Bool {
        didSet { defaults.set(showNotchShadow, forKey: "showNotchShadow") }
    }

    var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") }
    }

    var cameraCenterStageEnabled: Bool {
        didSet { defaults.set(cameraCenterStageEnabled, forKey: "cameraCenterStageEnabled") }
    }

    var cameraStudioLightEnabled: Bool {
        didSet { defaults.set(cameraStudioLightEnabled, forKey: "cameraStudioLightEnabled") }
    }

    var cameraPortraitEnabled: Bool {
        didSet { defaults.set(cameraPortraitEnabled, forKey: "cameraPortraitEnabled") }
    }

    var cameraRingLightEnabled: Bool {
        didSet { defaults.set(cameraRingLightEnabled, forKey: "cameraRingLightEnabled") }
    }

    var cameraShowGrid: Bool {
        didSet { defaults.set(cameraShowGrid, forKey: "cameraShowGrid") }
    }

    var cameraZoomFactor: Double {
        didSet { defaults.set(cameraZoomFactor, forKey: "cameraZoomFactor") }
    }

    var cameraExposureBias: Double {
        didSet { defaults.set(cameraExposureBias, forKey: "cameraExposureBias") }
    }

    var cameraIsMirrored: Bool {
        didSet { defaults.set(cameraIsMirrored, forKey: "cameraIsMirrored") }
    }

    var idleAnimationStyle: NotchIdleAnimation {
        didSet { defaults.set(idleAnimationStyle.rawValue, forKey: "idleAnimationStyle") }
    }

    var idleAnimation: NotchIdleAnimation {
        get { idleAnimationStyle }
        set { idleAnimationStyle = newValue }
    }

    var idleInteractionMode: NotchIdleInteractionMode {
        didSet { defaults.set(idleInteractionMode.rawValue, forKey: "idleInteractionMode") }
    }

    var idleWithActivityMode: NotchIdleWithActivityMode {
        didSet { defaults.set(idleWithActivityMode.rawValue, forKey: "idleWithActivityMode") }
    }

    var idleAnimationSpeed: Double {
        didSet { defaults.set(idleAnimationSpeed, forKey: "idleAnimationSpeed") }
    }

    var showIdleOnHardwareNotch: Bool {
        didSet { defaults.set(showIdleOnHardwareNotch, forKey: "showIdleOnHardwareNotch") }
    }

    var idleWingWidth: CGFloat {
        didSet { defaults.set(idleWingWidth, forKey: "idleWingWidth") }
    }

    var hardwareNotchTabBarStyle: HardwareNotchTabBarStyle {
        didSet { defaults.set(hardwareNotchTabBarStyle.rawValue, forKey: "hardwareNotchTabBarStyle") }
    }

    var musicShowVisualizer: Bool {
        didSet { defaults.set(musicShowVisualizer, forKey: "musicShowVisualizer") }
    }

    var musicShowElapsedTimes: Bool {
        didSet { defaults.set(musicShowElapsedTimes, forKey: "musicShowElapsedTimes") }
    }

    var musicShowArtworkGlow: Bool {
        didSet { defaults.set(musicShowArtworkGlow, forKey: "musicShowArtworkGlow") }
    }

    var musicShowVolumeSlider: Bool {
        didSet { defaults.set(musicShowVolumeSlider, forKey: "musicShowVolumeSlider") }
    }

    var musicShowAlbumTitle: Bool {
        didSet { defaults.set(musicShowAlbumTitle, forKey: "musicShowAlbumTitle") }
    }

    var musicShowAudioRouteSelector: Bool {
        didSet { defaults.set(musicShowAudioRouteSelector, forKey: "musicShowAudioRouteSelector") }
    }

    var musicEnableMicLevelMeter: Bool {
        didSet { defaults.set(musicEnableMicLevelMeter, forKey: "musicEnableMicLevelMeter") }
    }

    var timerDefaultMinutes: Int {
        didSet { defaults.set(timerDefaultMinutes, forKey: "timerDefaultMinutes") }
    }

    var timerPlayCompletionSound: Bool {
        didSet { defaults.set(timerPlayCompletionSound, forKey: "timerPlayCompletionSound") }
    }

    var focusModeEnabled: Bool {
        didSet { defaults.set(focusModeEnabled, forKey: "focusModeEnabled") }
    }

    var focusEnterShortcut: String {
        didSet { defaults.set(focusEnterShortcut, forKey: "focusEnterShortcut") }
    }

    var focusExitShortcut: String {
        didSet { defaults.set(focusExitShortcut, forKey: "focusExitShortcut") }
    }

    var focusBlockDistractions: Bool {
        didSet { defaults.set(focusBlockDistractions, forKey: "focusBlockDistractions") }
    }

    var focusBlockedApps: String {
        didSet { defaults.set(focusBlockedApps, forKey: "focusBlockedApps") }
    }

    static let defaultFocusBlockedApps = "com.apple.MobileSMS,com.apple.mail,com.tinyspeck.slackmacgap,com.hnc.Discord,ru.keepcoder.Telegram,net.whatsapp.WhatsApp"

    var timerDefaultDuration: Double {
        didSet { defaults.set(timerDefaultDuration, forKey: "timerDefaultDuration") }
    }

    var timerPlaySound: Bool {
        didSet { defaults.set(timerPlaySound, forKey: "timerPlaySound") }
    }

    var calendarShowAllDayEvents: Bool {
        didSet { defaults.set(calendarShowAllDayEvents, forKey: "calendarShowAllDayEvents") }
    }

    var calendarMaxEventsShown: Int {
        didSet { defaults.set(calendarMaxEventsShown, forKey: "calendarMaxEventsShown") }
    }

    var calendarShowLocation: Bool {
        didSet { defaults.set(calendarShowLocation, forKey: "calendarShowLocation") }
    }

    var calendarLookaheadHours: Int {
        didSet { defaults.set(calendarLookaheadHours, forKey: "calendarLookaheadHours") }
    }

    var remindersShowCompleted: Bool {
        didSet { defaults.set(remindersShowCompleted, forKey: "remindersShowCompleted") }
    }

    var remindersShowDueDate: Bool {
        didSet { defaults.set(remindersShowDueDate, forKey: "remindersShowDueDate") }
    }

    var remindersSortByPriority: Bool {
        didSet { defaults.set(remindersSortByPriority, forKey: "remindersSortByPriority") }
    }

    var remindersMaxItems: Int {
        didSet { defaults.set(remindersMaxItems, forKey: "remindersMaxItems") }
    }

    var batteryShowThermalState: Bool {
        didSet { defaults.set(batteryShowThermalState, forKey: "batteryShowThermalState") }
    }

    var batteryShowCycleAndCapacity: Bool {
        didSet { defaults.set(batteryShowCycleAndCapacity, forKey: "batteryShowCycleAndCapacity") }
    }

    var batteryLowThreshold: Int {
        didSet { defaults.set(batteryLowThreshold, forKey: "batteryLowThreshold") }
    }

    var batteryShowDetailedMetrics: Bool {
        didSet { defaults.set(batteryShowDetailedMetrics, forKey: "batteryShowDetailedMetrics") }
    }

    var bluetoothHideDisconnected: Bool {
        didSet { defaults.set(bluetoothHideDisconnected, forKey: "bluetoothHideDisconnected") }
    }

    var bluetoothDefaultFilterConnected: Bool {
        didSet { defaults.set(bluetoothDefaultFilterConnected, forKey: "bluetoothDefaultFilterConnected") }
    }

    var bluetoothShowTechnicalDetails: Bool {
        didSet { defaults.set(bluetoothShowTechnicalDetails, forKey: "bluetoothShowTechnicalDetails") }
    }

    var shelfPersistItems: Bool {
        didSet { defaults.set(shelfPersistItems, forKey: "shelfPersistItems") }
    }

    var shelfClickAction: ShelfClickAction {
        didSet { defaults.set(shelfClickAction.rawValue, forKey: "shelfClickAction") }
    }

    var shelfMaxItems: Int {
        didSet { defaults.set(shelfMaxItems, forKey: "shelfMaxItems") }
    }

    var clipboardCaptureImages: Bool {
        didSet { defaults.set(clipboardCaptureImages, forKey: "clipboardCaptureImages") }
    }

    var clipboardShowSourceApp: Bool {
        didSet { defaults.set(clipboardShowSourceApp, forKey: "clipboardShowSourceApp") }
    }

    var hasIdleContentEnabled: Bool {
        idleAnimationStyle != .none
    }

    private(set) var tabTransitionDirection: CGFloat = 1

    var isMusicAudioMenuOpen: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        func number(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }

        displayTargetMode = DisplayTargetMode(rawValue: defaults.string(forKey: "displayTargetMode") ?? "") ?? .allDisplays
        customEnabledDisplayIDs = defaults.stringArray(forKey: "customEnabledDisplayIDs") ?? []
        targetDisplayUUID = defaults.string(forKey: "targetDisplayUUID") ?? "main"
        enableVirtualNotch = bool("enableVirtualNotch", true)

        closedNotchWidth = CGFloat(number("closedNotchWidth", 185))
        closedNotchHeight = CGFloat(number("closedNotchHeight", 32))
        closedTopCornerRadius = CGFloat(number("closedTopCornerRadius", 8))
        closedBottomCornerRadius = CGFloat(number("closedBottomCornerRadius", 14))
        openNotchWidth = CGFloat(number("openNotchWidth", 620))
        openNotchHeight = CGFloat(number("openNotchHeight", 260))
        autoAdjustHeight = bool("autoAdjustHeight", true)
        openCornerRadius = CGFloat(number("openCornerRadius", 24))

        enableHomeModule = bool("enableHomeModule", true)
        showHomeMusicCard = bool("showHomeMusicCard", true)
        showHomeCalendarCard = bool("showHomeCalendarCard", true)
        showHomeTimerCard = bool("showHomeTimerCard", true)
        showHomeBatteryCard = bool("showHomeBatteryCard", true)
        showHomeBluetoothCard = bool("showHomeBluetoothCard", false)
        showHomeClipboardCard = bool("showHomeClipboardCard", true)
        showHomeTeleprompterCard = bool("showHomeTeleprompterCard", true)
        showHomeAIQuotaCard = bool("showHomeAIQuotaCard", true)
        showHomeHeavyProcessCard = bool("showHomeHeavyProcessCard", true)

        enableMusicModule = bool("enableMusicModule", true)
        enableAudioModule = bool("enableAudioModule", true)
        enableTimerModule = bool("enableTimerModule", true)
        enableCalendarModule = bool("enableCalendarModule", true)
        enableRemindersModule = bool("enableRemindersModule", true)
        enableMirrorModule = bool("enableMirrorModule", true)
        enableBatteryModule = bool("enableBatteryModule", true)
        enableBluetoothModule = bool("enableBluetoothModule", true)
        enableShelfModule = bool("enableShelfModule", true)
        enableClipboardModule = bool("enableClipboardModule", true)
        clipboardHistoryLimit = defaults.object(forKey: "clipboardHistoryLimit") == nil ? 50 : defaults.integer(forKey: "clipboardHistoryLimit")
        clipboardAutoPaste = bool("clipboardAutoPaste", true)
        clipboardClickAction = ClipboardClickAction(rawValue: defaults.string(forKey: "clipboardClickAction") ?? "") ?? .paste
        enableTeleprompterModule = bool("enableTeleprompterModule", true)
        teleprompterSpeed = number("teleprompterSpeed", 35.0)
        teleprompterFontSize = number("teleprompterFontSize", 16.0)
        teleprompterShowFocusGuide = bool("teleprompterShowFocusGuide", true)
        teleprompterKeepOpenWhilePlaying = bool("teleprompterKeepOpenWhilePlaying", true)
        teleprompterIsMirrored = bool("teleprompterIsMirrored", false)
        enableSystemHUD = bool("enableSystemHUD", true)

        showMusicLiveActivity = bool("showMusicLiveActivity", true)
        showTimerLiveActivity = bool("showTimerLiveActivity", true)
        showCalendarLiveActivity = bool("showCalendarLiveActivity", true)
        showBatteryLiveActivity = bool("showBatteryLiveActivity", true)
        showAIQuotaLiveActivity = bool("showAIQuotaLiveActivity", true)
        showHeavyProcessLiveActivity = bool("showHeavyProcessLiveActivity", true)
        showQuotaResetPeek = bool("showQuotaResetPeek", true)
        showSystemAlertPeek = bool("showSystemAlertPeek", true)
        heavyProcessThreshold = number("heavyProcessThreshold", 70.0)
        thermalAlertThreshold = number("thermalAlertThreshold", 80.0)
        showClockWhenIdle = bool("showClockWhenIdle", true)

        hoverToExpand = bool("hoverToExpand", true)
        hoverDelay = number("hoverDelay", 0.35)
        autoCollapseDelay = number("autoCollapseDelay", 0.35)
        scrollAction = ScrollAction(rawValue: defaults.integer(forKey: "scrollAction")) ?? .adjustVolume
        showInMenuBar = bool("showInMenuBar", true)
        excludedAppBundleIDs = defaults.stringArray(forKey: "excludedAppBundleIDs") ?? []
        hideInFullScreenApps = bool("hideInFullScreenApps", true)
        activeTab = NotchTab(rawValue: defaults.string(forKey: "activeTab") ?? "") ?? .home

        homeCardOrder = Self.normalized((defaults.stringArray(forKey: "homeCardOrder") ?? []).compactMap(HomeCard.init(rawValue:)))
        homePrioritizeActive = bool("homePrioritizeActive", true)
        homeShowHeader = bool("homeShowHeader", true)
        homeShowHeaderDate = bool("homeShowHeaderDate", true)
        homeShowHeaderBattery = bool("homeShowHeaderBattery", false)
        homeShowHeaderClock = bool("homeShowHeaderClock", false)
        homeGridSingleColumn = bool("homeGridSingleColumn", false)

        bluetoothShowMacBattery = bool("bluetoothShowMacBattery", false)
        showBatteryWhenIdle = bool("showBatteryWhenIdle", false)

        liveActivityPriority = Self.normalized((defaults.stringArray(forKey: "liveActivityPriority") ?? []).compactMap(LiveActivityKind.init(rawValue:)))
        if defaults.object(forKey: "liveActivityLayout_v2") == nil {
            liveActivityLayout = .combined
            defaults.set(LiveActivityLayout.combined.rawValue, forKey: "liveActivityLayout")
            defaults.set(true, forKey: "liveActivityLayout_v2")
        } else {
            liveActivityLayout = LiveActivityLayout(rawValue: defaults.string(forKey: "liveActivityLayout") ?? "") ?? .combined
        }
        showPausedTimerActivity = bool("showPausedTimerActivity", true)
        showTrackChangePeek = bool("showTrackChangePeek", true)
        showTimerCompletionPeek = bool("showTimerCompletionPeek", true)
        dynamicIslandHoverBounce = bool("dynamicIslandHoverBounce", true)
        calendarLiveActivityLeadMinutes = defaults.object(forKey: "calendarLiveActivityLeadMinutes") == nil ? 15 : defaults.integer(forKey: "calendarLiveActivityLeadMinutes")

        tabOrder = Self.normalized((defaults.stringArray(forKey: "tabOrder") ?? []).compactMap(NotchTab.init(rawValue:)))
        tabLabelStyle = TabLabelStyle(rawValue: defaults.string(forKey: "tabLabelStyle") ?? "") ?? .selectedOnly
        showNotchBorder = bool("showNotchBorder", true)
        showNotchShadow = bool("showNotchShadow", true)
        hapticFeedback = bool("hapticFeedback", true)

        cameraCenterStageEnabled = bool("cameraCenterStageEnabled", false)
        cameraStudioLightEnabled = bool("cameraStudioLightEnabled", false)
        cameraPortraitEnabled = bool("cameraPortraitEnabled", false)
        cameraRingLightEnabled = bool("cameraRingLightEnabled", false)
        cameraShowGrid = bool("cameraShowGrid", false)
        cameraZoomFactor = number("cameraZoomFactor", 1.0)
        cameraExposureBias = number("cameraExposureBias", 0.0)
        cameraIsMirrored = bool("cameraIsMirrored", true)

        idleAnimationStyle = NotchIdleAnimation.fromStored(defaults.string(forKey: "idleAnimationStyle") ?? "")
        idleInteractionMode = NotchIdleInteractionMode(rawValue: defaults.string(forKey: "idleInteractionMode") ?? "") ?? .interactive
        idleWithActivityMode = NotchIdleWithActivityMode(rawValue: defaults.string(forKey: "idleWithActivityMode") ?? "") ?? .sideBySide
        idleAnimationSpeed = number("idleAnimationSpeed", 1.0)
        showIdleOnHardwareNotch = bool("showIdleOnHardwareNotch", true)
        idleWingWidth = CGFloat(number("idleWingWidth", 68))
        hardwareNotchTabBarStyle = HardwareNotchTabBarStyle(rawValue: defaults.string(forKey: "hardwareNotchTabBarStyle") ?? "") ?? .unifiedBelow

        musicShowVisualizer = bool("musicShowVisualizer", true)
        musicShowElapsedTimes = bool("musicShowElapsedTimes", true)
        musicShowArtworkGlow = bool("musicShowArtworkGlow", true)
        musicShowVolumeSlider = bool("musicShowVolumeSlider", true)
        musicShowAlbumTitle = bool("musicShowAlbumTitle", true)
        musicShowAudioRouteSelector = bool("musicShowAudioRouteSelector", true)
        musicEnableMicLevelMeter = bool("musicEnableMicLevelMeter", false)

        timerDefaultMinutes = defaults.object(forKey: "timerDefaultMinutes") == nil ? 5 : defaults.integer(forKey: "timerDefaultMinutes")
        timerPlayCompletionSound = bool("timerPlayCompletionSound", true)
        timerDefaultDuration = number("timerDefaultDuration", 1500.0)
        focusModeEnabled = bool("focusModeEnabled", false)
        focusEnterShortcut = defaults.string(forKey: "focusEnterShortcut") ?? ""
        focusExitShortcut = defaults.string(forKey: "focusExitShortcut") ?? ""
        focusBlockDistractions = bool("focusBlockDistractions", false)
        focusBlockedApps = defaults.string(forKey: "focusBlockedApps") ?? Self.defaultFocusBlockedApps
        timerPlaySound = bool("timerPlaySound", true)

        calendarShowAllDayEvents = bool("calendarShowAllDayEvents", true)
        calendarMaxEventsShown = defaults.object(forKey: "calendarMaxEventsShown") == nil ? 5 : defaults.integer(forKey: "calendarMaxEventsShown")
        calendarShowLocation = bool("calendarShowLocation", true)
        calendarLookaheadHours = defaults.object(forKey: "calendarLookaheadHours") == nil ? 36 : defaults.integer(forKey: "calendarLookaheadHours")

        remindersShowCompleted = bool("remindersShowCompleted", false)
        remindersShowDueDate = bool("remindersShowDueDate", true)
        remindersSortByPriority = bool("remindersSortByPriority", true)
        remindersMaxItems = defaults.object(forKey: "remindersMaxItems") == nil ? 25 : defaults.integer(forKey: "remindersMaxItems")

        batteryShowThermalState = bool("batteryShowThermalState", true)
        batteryShowCycleAndCapacity = bool("batteryShowCycleAndCapacity", true)
        batteryLowThreshold = defaults.object(forKey: "batteryLowThreshold") == nil ? 20 : defaults.integer(forKey: "batteryLowThreshold")
        batteryShowDetailedMetrics = bool("batteryShowDetailedMetrics", true)

        bluetoothHideDisconnected = bool("bluetoothHideDisconnected", false)
        bluetoothDefaultFilterConnected = bool("bluetoothDefaultFilterConnected", false)
        bluetoothShowTechnicalDetails = bool("bluetoothShowTechnicalDetails", true)

        shelfPersistItems = bool("shelfPersistItems", true)
        shelfClickAction = ShelfClickAction(rawValue: defaults.string(forKey: "shelfClickAction") ?? "") ?? .openFile
        shelfMaxItems = defaults.object(forKey: "shelfMaxItems") == nil ? 12 : defaults.integer(forKey: "shelfMaxItems")

        clipboardCaptureImages = bool("clipboardCaptureImages", true)
        clipboardShowSourceApp = bool("clipboardShowSourceApp", true)
    }

    var availableTabs: [NotchTab] {
        let ordered = tabOrder.filter { isTabEnabled($0) }
        return ordered.isEmpty ? [.home] : ordered
    }

    var resolvedActiveTab: NotchTab {
        let tabs = availableTabs
        return tabs.contains(activeTab) ? activeTab : (tabs.first ?? .home)
    }

    func selectTab(_ tab: NotchTab) {
        guard tab != activeTab else { return }
        let newIdx = tabOrder.firstIndex(of: tab) ?? tab.order
        let oldIdx = tabOrder.firstIndex(of: activeTab) ?? activeTab.order
        tabTransitionDirection = newIdx >= oldIdx ? 1 : -1
        activeTab = tab
    }

    func isTabEnabled(_ tab: NotchTab) -> Bool {
        switch tab {
        case .home: return enableHomeModule
        case .music: return enableMusicModule
        case .audio: return enableAudioModule
        case .timer: return enableTimerModule
        case .calendar: return enableCalendarModule
        case .reminders: return enableRemindersModule
        case .mirror: return enableMirrorModule
        case .battery: return enableBatteryModule
        case .bluetooth: return enableBluetoothModule
        case .shelf: return enableShelfModule
        case .clipboard: return enableClipboardModule
        case .teleprompter: return enableTeleprompterModule
        }
    }

    func setTab(_ tab: NotchTab, enabled: Bool) {
        switch tab {
        case .home: enableHomeModule = enabled
        case .music: enableMusicModule = enabled
        case .audio: enableAudioModule = enabled
        case .timer: enableTimerModule = enabled
        case .calendar: enableCalendarModule = enabled
        case .reminders: enableRemindersModule = enabled
        case .mirror: enableMirrorModule = enabled
        case .battery: enableBatteryModule = enabled
        case .bluetooth: enableBluetoothModule = enabled
        case .shelf: enableShelfModule = enabled
        case .clipboard: enableClipboardModule = enabled
        case .teleprompter: enableTeleprompterModule = enabled
        }
    }

    func isHomeCardEnabled(_ card: HomeCard) -> Bool {
        switch card {
        case .music: return showHomeMusicCard
        case .calendar: return showHomeCalendarCard
        case .timer: return showHomeTimerCard
        case .battery: return showHomeBatteryCard
        case .bluetooth: return showHomeBluetoothCard
        case .clipboard: return showHomeClipboardCard
        case .teleprompter: return showHomeTeleprompterCard
        case .aiQuota: return showHomeAIQuotaCard
        case .heavyProcess: return showHomeHeavyProcessCard
        }
    }

    func isHomeCardVisible(_ card: HomeCard) -> Bool {
        enableHomeModule && isHomeCardEnabled(card)
    }

    func setHomeCard(_ card: HomeCard, enabled: Bool) {
        switch card {
        case .music: showHomeMusicCard = enabled
        case .calendar: showHomeCalendarCard = enabled
        case .timer: showHomeTimerCard = enabled
        case .battery: showHomeBatteryCard = enabled
        case .bluetooth: showHomeBluetoothCard = enabled
        case .clipboard: showHomeClipboardCard = enabled
        case .teleprompter: showHomeTeleprompterCard = enabled
        case .aiQuota: showHomeAIQuotaCard = enabled
        case .heavyProcess: showHomeHeavyProcessCard = enabled
        }
    }

    var visibleHomeCards: [HomeCard] {
        homeCardOrder.filter { isHomeCardEnabled($0) }
    }

    func isLiveActivityEnabled(_ kind: LiveActivityKind) -> Bool {
        switch kind {
        case .timer: return showTimerLiveActivity
        case .music: return showMusicLiveActivity
        case .calendar: return showCalendarLiveActivity
        case .battery: return showBatteryLiveActivity
        case .aiQuota: return showAIQuotaLiveActivity
        case .heavyProcess: return showHeavyProcessLiveActivity
        }
    }

    func setLiveActivity(_ kind: LiveActivityKind, enabled: Bool) {
        switch kind {
        case .timer: showTimerLiveActivity = enabled
        case .music: showMusicLiveActivity = enabled
        case .calendar: showCalendarLiveActivity = enabled
        case .battery: showBatteryLiveActivity = enabled
        case .aiQuota: showAIQuotaLiveActivity = enabled
        case .heavyProcess: showHeavyProcessLiveActivity = enabled
        }
    }

    var engineDemand: NotchEngineDemand {
        let homeHeaderBattery = enableHomeModule && homeShowHeader && homeShowHeaderBattery
        let bluetoothMacBattery = enableBluetoothModule && bluetoothShowMacBattery
        return NotchEngineDemand(
            media: enableMusicModule || isHomeCardVisible(.music) || showMusicLiveActivity,
            calendar: enableCalendarModule || isHomeCardVisible(.calendar) || showCalendarLiveActivity,
            reminders: enableRemindersModule,
            battery: enableBatteryModule || isHomeCardVisible(.battery) || showBatteryLiveActivity
                || homeHeaderBattery || showBatteryWhenIdle || bluetoothMacBattery || enableSystemHUD,
            bluetooth: enableBluetoothModule || isHomeCardVisible(.bluetooth),
            timer: enableTimerModule || isHomeCardVisible(.timer),
            mirror: enableMirrorModule,
            systemHUD: enableSystemHUD,
            statusItem: showInMenuBar,
            scrollMonitor: scrollAction != .disabled,
            clipboard: enableClipboardModule || isHomeCardVisible(.clipboard),
            teleprompter: enableTeleprompterModule || isHomeCardVisible(.teleprompter),
            aiQuota: FeatureManager.shared.isEnabled(.aiQuota) && (isHomeCardVisible(.aiQuota) || showAIQuotaLiveActivity),
            systemStats: FeatureManager.shared.isEnabled(.systemMonitor)
                && (isHomeCardVisible(.heavyProcess) || showHeavyProcessLiveActivity)
        )
    }

    func effectiveExpandedHeight(for tab: NotchTab, headerHeight: CGFloat = ScreenNotchGeometry.standardHeaderHeight) -> CGFloat {
        let headerDelta = headerHeight - ScreenNotchGeometry.standardHeaderHeight
        guard autoAdjustHeight else {
            if tab == .music && isMusicAudioMenuOpen {
                return max(openNotchHeight, 424 + headerDelta)
            }
            return openNotchHeight
        }

        switch tab {
        case .home:
            let hasHeader = homeShowHeader && (homeShowHeaderDate || homeShowHeaderClock || homeShowHeaderBattery)
            let headerH: CGFloat = hasHeader ? 36 : 0
            let verticalPadding: CGFloat = 24
            let cardCount = visibleHomeCards.count
            let floor = 185 + headerDelta

            if cardCount == 0 {
                return floor
            }

            let cardH: CGFloat = 82
            let spacing: CGFloat = 10
            let rowCount: CGFloat = homeGridSingleColumn ? CGFloat(cardCount) : CGFloat((cardCount + 1) / 2)
            let cardsTotalH = (rowCount * cardH) + (max(0, rowCount - 1) * spacing)
            let computed = headerHeight + headerH + verticalPadding + cardsTotalH
            return min(max(computed, floor), 440 + headerDelta)

        case .music:
            let base: CGFloat = musicShowAudioRouteSelector ? 248 : 195
            return (isMusicAudioMenuOpen ? 424 : base) + headerDelta
        case .audio:
            return 298 + headerDelta
        case .timer:
            return 230 + headerDelta
        case .calendar, .reminders:
            return 250 + headerDelta
        case .mirror:
            return 315 + headerDelta
        case .battery:
            return 190 + headerDelta
        case .bluetooth:
            return 205 + headerDelta
        case .shelf:
            return 210 + headerDelta
        case .clipboard:
            return 340 + headerDelta
        case .teleprompter:
            return 330 + headerDelta
        }
    }

    func isDisplayEnabled(id: String, isBuiltin: Bool, isMain: Bool) -> Bool {
        switch displayTargetMode {
        case .allDisplays:
            return true
        case .mainOnly:
            return isMain
        case .builtinOnly:
            return isBuiltin
        case .externalOnly:
            return !isBuiltin
        case .custom:
            return customEnabledDisplayIDs.contains(id)
        }
    }

    func setDisplayEnabled(id: String, isEnabled: Bool) {
        if isEnabled {
            if !customEnabledDisplayIDs.contains(id) {
                customEnabledDisplayIDs.append(id)
            }
        } else {
            customEnabledDisplayIDs.removeAll(where: { $0 == id })
        }
    }

    func isAppExcluded(bundleID: String) -> Bool {
        excludedAppBundleIDs.contains(bundleID)
    }

    func setAppExcluded(bundleID: String, excluded: Bool) {
        if excluded {
            if !excludedAppBundleIDs.contains(bundleID) {
                excludedAppBundleIDs.append(bundleID)
            }
        } else {
            excludedAppBundleIDs.removeAll { $0 == bundleID }
        }
    }

    func toggleAppExclusion(bundleID: String) {
        setAppExcluded(bundleID: bundleID, excluded: !isAppExcluded(bundleID: bundleID))
    }

    static func normalized<T: CaseIterable & Equatable>(_ stored: [T]) -> [T] {
        var result: [T] = []
        for item in stored where !result.contains(item) {
            result.append(item)
        }
        for item in T.allCases where !result.contains(item) {
            result.append(item)
        }
        return result
    }

    static func moved<T>(_ list: [T], from source: Int, to destination: Int) -> [T] {
        list.moving(from: source, to: destination)
    }

    func resetToDefaults() {
        displayTargetMode = .allDisplays
        customEnabledDisplayIDs = []
        targetDisplayUUID = "main"
        enableVirtualNotch = true
        closedNotchWidth = 185
        closedNotchHeight = 32
        closedTopCornerRadius = 8
        closedBottomCornerRadius = 14
        openNotchWidth = 620
        openNotchHeight = 260
        autoAdjustHeight = true
        openCornerRadius = 24
        enableHomeModule = true
        showHomeMusicCard = true
        showHomeCalendarCard = true
        showHomeTimerCard = true
        showHomeBatteryCard = true
        showHomeBluetoothCard = false
        homeCardOrder = HomeCard.allCases
        homePrioritizeActive = true
        homeShowHeader = true
        homeShowHeaderDate = true
        homeShowHeaderBattery = false
        homeShowHeaderClock = false
        homeGridSingleColumn = false
        bluetoothShowMacBattery = false
        showBatteryWhenIdle = false
        enableMusicModule = true
        enableAudioModule = true
        enableTimerModule = true
        enableCalendarModule = true
        enableRemindersModule = true
        enableMirrorModule = true
        enableBatteryModule = true
        enableBluetoothModule = true
        enableShelfModule = true
        enableClipboardModule = true
        showHomeClipboardCard = true
        clipboardHistoryLimit = 50
        clipboardAutoPaste = true
        clipboardClickAction = .paste
        enableTeleprompterModule = true
        showHomeTeleprompterCard = true
        showHomeAIQuotaCard = true
        showHomeHeavyProcessCard = true
        teleprompterSpeed = 35.0
        teleprompterFontSize = 16.0
        teleprompterShowFocusGuide = true
        teleprompterKeepOpenWhilePlaying = true
        teleprompterIsMirrored = false
        enableSystemHUD = true
        showMusicLiveActivity = true
        showTimerLiveActivity = true
        showCalendarLiveActivity = true
        showBatteryLiveActivity = true
        showAIQuotaLiveActivity = true
        showHeavyProcessLiveActivity = true
        showClockWhenIdle = true
        liveActivityPriority = LiveActivityKind.allCases
        liveActivityLayout = .combined
        showPausedTimerActivity = true
        showTrackChangePeek = true
        showTimerCompletionPeek = true
        showQuotaResetPeek = true
        showSystemAlertPeek = true
        heavyProcessThreshold = 70.0
        thermalAlertThreshold = 80.0
        dynamicIslandHoverBounce = true
        calendarLiveActivityLeadMinutes = 15
        tabOrder = NotchTab.allCases
        tabLabelStyle = .selectedOnly
        showNotchBorder = true
        showNotchShadow = true
        hapticFeedback = true
        cameraCenterStageEnabled = false
        cameraStudioLightEnabled = false
        cameraPortraitEnabled = false
        cameraRingLightEnabled = false
        cameraShowGrid = false
        cameraZoomFactor = 1.0
        cameraExposureBias = 0.0
        cameraIsMirrored = true
        idleAnimationStyle = .bongoCat
        idleInteractionMode = .interactive
        idleWithActivityMode = .sideBySide
        idleAnimationSpeed = 1.0
        showIdleOnHardwareNotch = true
        idleWingWidth = 68
        hardwareNotchTabBarStyle = .unifiedBelow
        musicShowVisualizer = true
        musicShowElapsedTimes = true
        musicShowArtworkGlow = true
        musicShowVolumeSlider = true
        musicShowAlbumTitle = true
        musicShowAudioRouteSelector = true
        musicEnableMicLevelMeter = false
        timerDefaultMinutes = 5
        timerPlayCompletionSound = true
        timerDefaultDuration = 1500.0
        focusModeEnabled = false
        focusEnterShortcut = ""
        focusExitShortcut = ""
        focusBlockDistractions = false
        focusBlockedApps = Self.defaultFocusBlockedApps
        timerPlaySound = true
        calendarShowAllDayEvents = true
        calendarMaxEventsShown = 5
        calendarShowLocation = true
        calendarLookaheadHours = 36
        remindersShowCompleted = false
        remindersShowDueDate = true
        remindersSortByPriority = true
        remindersMaxItems = 25
        batteryShowThermalState = true
        batteryShowCycleAndCapacity = true
        batteryLowThreshold = 20
        batteryShowDetailedMetrics = true
        bluetoothHideDisconnected = false
        bluetoothDefaultFilterConnected = false
        bluetoothShowTechnicalDetails = true
        shelfPersistItems = true
        shelfClickAction = .openFile
        shelfMaxItems = 12
        clipboardCaptureImages = true
        clipboardShowSourceApp = true
        hoverToExpand = true
        hoverDelay = 0.35
        autoCollapseDelay = 0.35
        scrollAction = .adjustVolume
        showInMenuBar = true
        excludedAppBundleIDs = []
        hideInFullScreenApps = true
        activeTab = .home
    }
}
