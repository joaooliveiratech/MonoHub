import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import MonoHub

@Suite("MonoNotch Model Tests")
@MainActor
struct ModelTests {
    @Test("AppInfo version and build metadata are valid")
    func appInfoMetadata() {
        #expect(AppInfo.version == "0.17.8")
        #expect(AppInfo.build == "64")
        #expect(AppInfo.fullVersionString == "0.17.8 (64)")
        #expect(AppInfo.bundleIdentifier == "com.antigravity.monohub")
    }

    @Test("MusicTrack progress and time formatting calculations")
    func musicTrackProgress() {
        let track = MusicTrack(
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 200,
            elapsed: 100,
            isPlaying: true,
            playerType: .appleMusic
        )

        #expect(track.progress == 0.5)
        #expect(track.formattedElapsed == "1:40")
        #expect(track.formattedDuration == "3:20")
        #expect(!track.isEmpty)

        let emptyTrack = MusicTrack.empty
        #expect(emptyTrack.isEmpty)
        #expect(!emptyTrack.isPlaying)

        let placeholderTrack = MusicTrack(title: "No Playback", artist: "", isPlaying: false)
        #expect(placeholderTrack.isEmpty)
    }

    @Test("Universal MusicPlayerType resolution from bundleIdentifier and appName")
    func musicPlayerTypeResolution() {
        #expect(MusicPlayerType.from(bundleIdentifier: "com.apple.Music", appName: "Music") == .appleMusic)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.spotify.client", appName: "Spotify") == .spotify)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.apple.Safari", appName: "Safari") == .youtube)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome") == .youtube)
        #expect(MusicPlayerType.from(bundleIdentifier: "company.thebrowser.Browser", appName: "Arc") == .youtube)
        #expect(MusicPlayerType.from(bundleIdentifier: "org.videolan.vlc", appName: "VLC") == .video)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.colliderli.iina", appName: "IINA") == .video)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.apple.QuickTimePlayerX", appName: "QuickTime Player") == .quickTime)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.apple.podcasts", appName: "Podcasts") == .podcasts)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.apple.TV", appName: "TV") == .appleTV)
        #expect(MusicPlayerType.from(bundleIdentifier: "com.custom.app", appName: "Custom") == .system)
    }

    @Test("Timer countdown calculations and formatting")
    func timerCalculations() {
        var timer = TimerModel(
            mode: .countdown,
            targetDuration: 300,
            remainingSeconds: 150,
            elapsedTime: 0,
            isRunning: true
        )

        #expect(timer.progress == 0.5)
        #expect(timer.formattedDisplay == "02:30")

        timer.mode = .stopwatch
        timer.elapsedTime = 3665
        #expect(timer.formattedDisplay == "1:01:05")
    }

    @Test("Timer presets exist and have valid durations")
    func timerPresets() {
        let presets = TimerPreset.standardPresets
        #expect(presets.count >= 4)
        #expect(presets[0].durationInSeconds == 60)
        #expect(presets[1].durationInSeconds == 300)
    }

    @Test("Pomodoro phases, durations, and model formatting")
    func pomodoroPhaseDurations() {
        #expect(PomodoroPhase.focus.defaultDuration == 1500)
        #expect(PomodoroPhase.shortBreak.defaultDuration == 300)
        #expect(PomodoroPhase.longBreak.defaultDuration == 900)

        var pomodoroModel = TimerModel(
            mode: .pomodoro,
            targetDuration: PomodoroPhase.focus.defaultDuration,
            remainingSeconds: PomodoroPhase.focus.defaultDuration,
            elapsedTime: 0,
            isRunning: false,
            pomodoroPhase: .focus,
            completedPomodoros: 2
        )

        #expect(pomodoroModel.formattedDisplay == "25:00")
        #expect(pomodoroModel.pomodoroPhase.emoji == "🍅")

        pomodoroModel.pomodoroPhase = .shortBreak
        pomodoroModel.targetDuration = PomodoroPhase.shortBreak.defaultDuration
        pomodoroModel.remainingSeconds = PomodoroPhase.shortBreak.defaultDuration
        #expect(pomodoroModel.formattedDisplay == "05:00")
        #expect(pomodoroModel.pomodoroPhase.emoji == "☕️")
    }

    @Test("TimerManager Pomodoro phase switching and cycle progression")
    func timerManagerPomodoroCycles() {
        let timer = TimerManager.shared
        timer.setPomodoroPhase(.focus)
        #expect(timer.model.mode == .pomodoro)
        #expect(timer.model.pomodoroPhase == .focus)
        #expect(timer.model.remainingSeconds == 1500)

        timer.setPomodoroPhase(.shortBreak)
        #expect(timer.model.pomodoroPhase == .shortBreak)
        #expect(timer.model.remainingSeconds == 300)

        timer.setPomodoroPhase(.longBreak)
        #expect(timer.model.pomodoroPhase == .longBreak)
        #expect(timer.model.remainingSeconds == 900)

        // Reset to focus
        timer.setPomodoroPhase(.focus)
        #expect(timer.model.pomodoroPhase == .focus)
    }

    @Test("NotchWindowController navigation grace tracking")
    func notchNavigationGrace() {
        let controller = NotchWindowController.shared
        #expect(controller.navigationGraceUntil == nil)

        controller.recordNavigationFromExpanded(previousHeight: 440)
        #expect(controller.navigationGraceUntil != nil)
        #expect(controller.previousExpandedHeight == 440)
        #expect(Date() < controller.navigationGraceUntil!)
    }

    @Test("BatteryInfo status descriptions")
    func batteryInfoDescriptions() {
        let original = Localization.language
        defer { Localization.language = original }
        Localization.language = .portuguese

        let charging = BatteryInfo(percentage: 85, isCharging: true, isPluggedIn: true, timeRemainingMinutes: 45)
        #expect(charging.statusDescription == "45min até a carga completa")

        let plugged = BatteryInfo(percentage: 100, isCharging: false, isPluggedIn: true, timeRemainingMinutes: -1)
        #expect(plugged.statusDescription == "Conectada à alimentação")

        let onBattery = BatteryInfo(percentage: 50, isCharging: false, isPluggedIn: false, timeRemainingMinutes: 125)
        #expect(onBattery.statusDescription == "2h 5min restantes")

        Localization.language = .english
        #expect(charging.statusDescription == "45min until full")
        #expect(plugged.statusDescription == "Connected to power")
        #expect(onBattery.statusDescription == "2h 5min remaining")
    }

    @Test("HUDEvent percentage strings")
    func hudEventPercentages() {
        let original = Localization.language
        defer { Localization.language = original }
        Localization.language = .portuguese

        let volHUD = HUDEvent(type: .volume, value: 0.75, isMuted: false)
        #expect(volHUD.percentageString == "75%")

        let mutedHUD = HUDEvent(type: .volume, value: 0.75, isMuted: true)
        #expect(mutedHUD.percentageString == "Mudo")

        Localization.language = .english
        #expect(mutedHUD.percentageString == "Muted")

        let brightHUD = HUDEvent(type: .brightness, value: 0.5)
        #expect(brightHUD.percentageString == "50%")
    }

    @Test("Bluetooth device categories, battery levels, and rich metadata")
    func bluetoothCategories() {
        let mouse = BluetoothDeviceInfo(
            id: "1",
            name: "MX Master 4",
            batteryLevel: 55,
            vendorName: "Logitech",
            transportType: "BLE",
            rssi: -58,
            category: .mouse
        )
        #expect(mouse.category.iconName == "magicmouse")
        #expect(mouse.isAudioDevice == false)
        #expect(mouse.primaryBattery == 55)
        #expect(mouse.vendorName == "Logitech")
        #expect(mouse.transportType == "BLE")
        #expect(mouse.signalQualityLabel == "Bom")
        #expect(mouse.hasMultiPartBattery == false)

        let airpods = BluetoothDeviceInfo(
            id: "2",
            name: "AirPods Pro",
            batteryCaseLevel: 95,
            batteryLeftLevel: 80,
            batteryRightLevel: 85,
            isCharging: true,
            vendorName: "Apple",
            transportType: "Áudio",
            category: .airpods
        )
        #expect(airpods.category.iconName == "airpodspro")
        #expect(airpods.isAudioDevice == true)
        #expect(airpods.primaryBattery == 80)
        #expect(airpods.hasMultiPartBattery == true)
        #expect(airpods.isCharging == true)

        let gamepad = BluetoothDeviceInfo(id: "3", name: "DualShock 4", category: .gamepad)
        #expect(gamepad.category.iconName == "gamecontroller.fill")

        let phone = BluetoothDeviceInfo(id: "4", name: "iPhone 17 Pro", category: .phone)
        #expect(phone.category.iconName == "iphone")

        let watch = BluetoothDeviceInfo(id: "5", name: "Apple Watch", category: .watch)
        #expect(watch.category.iconName == "applewatch")

        let tv = BluetoothDeviceInfo(id: "6", name: "Living Room", category: .display)
        #expect(tv.category.iconName == "tv.fill")
    }
}

@MainActor
func makeIsolatedPreferences(_ name: String = #function) -> NotchPreferences {
    let sanitized = name.filter { $0.isLetter || $0.isNumber }
    let suite = "com.antigravity.monohub.tests.notch.\(sanitized)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return NotchPreferences(defaults: defaults)
}

@Suite("MonoNotch Preferences Tests")
@MainActor
struct PreferencesTests {
    @Test("Default preferences are initialized properly")
    func defaultPreferences() {
        let prefs = NotchPreferences.shared
        #expect(prefs.closedNotchWidth >= 150)
        #expect(prefs.closedNotchHeight >= 28)
        #expect(prefs.openNotchWidth >= 500)
        #expect(prefs.openNotchHeight >= 180)
        #expect(prefs.enableVirtualNotch == true)
    }

    @Test("All Notch tabs have icons and valid identifiers")
    func notchTabs() {
        #expect(NotchTab.allCases.contains(.home))
        for tab in NotchTab.allCases {
            #expect(!tab.iconName.isEmpty)
            #expect(!tab.id.isEmpty)
        }
    }

    @Test("Home module, header battery suppression, and custom tab ordering")
    func homePreferences() {
        let prefs = makeIsolatedPreferences()
        prefs.enableHomeModule = false
        prefs.resetToDefaults()
        #expect(prefs.enableHomeModule == true)
        #expect(prefs.homeShowHeader == true)
        #expect(prefs.homeShowHeaderDate == true)
        #expect(prefs.homeShowHeaderBattery == false)
        #expect(prefs.bluetoothShowMacBattery == false)
        #expect(prefs.dynamicIslandHoverBounce == true)
        #expect(prefs.calendarLiveActivityLeadMinutes == 15)
        #expect(prefs.showHomeMusicCard == true)
        #expect(prefs.showHomeCalendarCard == true)
        #expect(prefs.showHomeTimerCard == true)
        #expect(prefs.showHomeBatteryCard == true)
        #expect(prefs.showHomeBluetoothCard == false)
        #expect(prefs.tabOrder.count == NotchTab.allCases.count)
    }

    @Test("Display target modes and custom selection logic")
    func displayTargetModes() {
        let prefs = makeIsolatedPreferences()
        prefs.displayTargetMode = .allDisplays
        #expect(prefs.isDisplayEnabled(id: "1", isBuiltin: true, isMain: true))
        #expect(prefs.isDisplayEnabled(id: "3", isBuiltin: false, isMain: false))

        prefs.displayTargetMode = .builtinOnly
        #expect(prefs.isDisplayEnabled(id: "1", isBuiltin: true, isMain: true))
        #expect(!prefs.isDisplayEnabled(id: "3", isBuiltin: false, isMain: false))

        prefs.displayTargetMode = .externalOnly
        #expect(!prefs.isDisplayEnabled(id: "1", isBuiltin: true, isMain: true))
        #expect(prefs.isDisplayEnabled(id: "3", isBuiltin: false, isMain: false))

        prefs.displayTargetMode = .custom
        prefs.setDisplayEnabled(id: "3", isEnabled: true)
        #expect(prefs.isDisplayEnabled(id: "3", isBuiltin: false, isMain: false))
        #expect(!prefs.isDisplayEnabled(id: "1", isBuiltin: true, isMain: true))
    }

    @Test("App exclusion and full screen preferences")
    func appExclusionPreferences() {
        let prefs = makeIsolatedPreferences()
        let testID = "com.test.excludedApp"

        prefs.setAppExcluded(bundleID: testID, excluded: false)
        #expect(!prefs.isAppExcluded(bundleID: testID))

        prefs.setAppExcluded(bundleID: testID, excluded: true)
        #expect(prefs.isAppExcluded(bundleID: testID))

        prefs.toggleAppExclusion(bundleID: testID)
        #expect(!prefs.isAppExcluded(bundleID: testID))

        #expect(prefs.hideInFullScreenApps == true)
        #expect(prefs.hoverDelay == 0.35)
        #expect(prefs.openNotchHeight == 260)
    }

    @Test("AppExclusionManager instance evaluates suppression cleanly")
    func appExclusionManagerInstance() {
        let manager = AppExclusionManager.shared
        manager.evaluateSuppression()
        _ = manager.isSuppressed
    }
}

@Suite("MonoNotch Geometry & Sizing Tests")
@MainActor
struct SizingTests {
    @Test("Fallback geometry calculation for non-notch screens")
    func geometryFallback() {
        let prefs = NotchPreferences.shared
        let geometry = DisplayManager.calculateGeometry(for: nil, preferences: prefs)

        #expect(geometry.hasHardwareNotch == false)
        #expect(geometry.notchWidth == prefs.closedNotchWidth)
        #expect(geometry.notchHeight == prefs.closedNotchHeight)
    }

    @Test("NotchShape path generation does not produce empty paths")
    func notchShapePaths() {
        let shapeWithEars = NotchShape(topCornerRadius: 8, bottomCornerRadius: 14, hasTopEars: true)
        let pathWithEars = shapeWithEars.path(in: CGRect(x: 0, y: 0, width: 200, height: 35))
        #expect(!pathWithEars.isEmpty)

        let shapeWithoutEars = NotchShape(topCornerRadius: 0, bottomCornerRadius: 20, hasTopEars: false)
        let pathWithoutEars = shapeWithoutEars.path(in: CGRect(x: 0, y: 0, width: 600, height: 200))
        #expect(!pathWithoutEars.isEmpty)
    }
}

@Suite("Live Activity & Dynamic Island Tests")
@MainActor
struct LiveActivityTests {
    @Test("Resolve prioritizes multiple simultaneous activities")
    func activityResolution() {
        let priority: [LiveActivityKind] = [.timer, .music, .calendar, .battery]

        // Both timer and music active -> should resolve [timer, music]
        let resolved = LiveActivityCenter.resolve(priority: priority) { kind in
            kind == .timer || kind == .music
        }
        #expect(resolved == [.timer, .music])

        // Custom priority: music > timer
        let musicFirstPriority: [LiveActivityKind] = [.music, .timer, .calendar, .battery]
        let resolvedMusicFirst = LiveActivityCenter.resolve(priority: musicFirstPriority) { kind in
            kind == .timer || kind == .music
        }
        #expect(resolvedMusicFirst == [.music, .timer])
    }

    @Test("Metrics for split bubble vs combined layout with two activities")
    func metricsLayouts() {
        // Hardware notch with split bubble
        let splitMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: .music,
            layout: .split,
            hudVisible: false,
            hasPeek: false
        )
        #expect(splitMetrics.hasBubble == true)
        #expect(splitMetrics.bubbleDiameter == 32)
        #expect(splitMetrics.width == 185 + LiveActivityCenter.singleWing * 2)

        // Hardware notch with combined layout (side by side in wings)
        let combinedMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: .music,
            layout: .combined,
            hudVisible: false,
            hasPeek: false
        )
        #expect(combinedMetrics.hasBubble == false)
        #expect(combinedMetrics.width == 185 + LiveActivityCenter.combinedWing * 2)

        // Single activity only
        let singleMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: nil,
            layout: .split,
            hudVisible: false,
            hasPeek: false
        )
        #expect(singleMetrics.hasBubble == false)

        // Virtual notch with combined layout dividing space
        let virtualCombinedMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: false,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: .music,
            layout: .combined,
            hudVisible: false,
            hasPeek: false
        )
        #expect(virtualCombinedMetrics.hasBubble == false)
        #expect(virtualCombinedMetrics.width == 330)
    }

    @Test("Peek deduplication suppresses track peek when music is active")
    func peekDeduplication() {
        let center = LiveActivityCenter.shared
        let trackPeek = NotchPeek.track(title: "Song", artist: "Artist")
        let timerPeek = NotchPeek.timerFinished

        // Non-track peek (timer) is always effective
        #expect(center.isPeekEffective(for: timerPeek) == true)

        // When music is not in primary or secondary, track peek is effective
        if center.primary != .music && center.secondary != .music {
            #expect(center.isPeekEffective(for: trackPeek) == true)
        }
    }

    @Test("SystemHUDInterceptor instance is initialized")
    func systemHUDInterceptorInstance() {
        let interceptor = SystemHUDInterceptor.shared
        _ = interceptor.hasAccessibilityPermission
    }

    @Test("Tab transition direction tracks ordering")
    func tabDirection() {
        let prefs = makeIsolatedPreferences()
        prefs.selectTab(.home)
        #expect(prefs.activeTab == .home)

        // Moving right to music
        prefs.selectTab(.music)
        #expect(prefs.tabTransitionDirection == 1)

        // Moving left back to home
        prefs.selectTab(.home)
        #expect(prefs.tabTransitionDirection == -1)
    }

    @Test("AI Quota and Heavy Process live activities resolution and properties")
    func aiQuotaAndHeavyProcessLiveActivities() {
        #expect(LiveActivityKind.aiQuota.id == "aiQuota")
        #expect(LiveActivityKind.heavyProcess.id == "heavyProcess")
        #expect(!LiveActivityKind.aiQuota.title.isEmpty)
        #expect(!LiveActivityKind.heavyProcess.title.isEmpty)
        #expect(LiveActivityKind.aiQuota.destinationTab == .home)
        #expect(LiveActivityKind.heavyProcess.destinationTab == .home)

        let priority: [LiveActivityKind] = [.aiQuota, .heavyProcess, .timer, .music]
        let resolved = LiveActivityCenter.resolve(priority: priority) { kind in
            kind == .aiQuota || kind == .heavyProcess
        }
        #expect(resolved == [.aiQuota, .heavyProcess])
    }

    @Test("Heavy process and thermal alert conditions")
    func heavyProcessConditions() {
        var cpu = CPUData()
        var sensors = SensorsData()

        // Nominal & low CPU -> not active
        #expect(LiveActivityCenter.isHeavyProcessActive(cpu: cpu, sensors: sensors, cpuThreshold: 70, tempThreshold: 80) == false)

        // Thermal state fair / serious -> active
        sensors.thermalState = .serious
        #expect(LiveActivityCenter.isHeavyProcessActive(cpu: cpu, sensors: sensors, cpuThreshold: 70, tempThreshold: 80) == true)
        sensors.thermalState = .nominal

        // High temperature -> active
        sensors.socTemperature = 85.0
        #expect(LiveActivityCenter.isHeavyProcessActive(cpu: cpu, sensors: sensors, cpuThreshold: 70, tempThreshold: 80) == true)
        sensors.socTemperature = 50.0

        // Top process CPU spike -> active
        cpu.topProcesses = [ProcessItem(pid: 1234, name: "clang", cpuPercent: 95.0)]
        #expect(LiveActivityCenter.isHeavyProcessActive(cpu: cpu, sensors: sensors, cpuThreshold: 70, tempThreshold: 80) == true)
    }

    @Test("NotchPeek for quota reset, thermal alert, and CPU peak")
    func quotaAndSystemNotchPeeks() {
        let center = LiveActivityCenter.shared
        let quotaPeek = NotchPeek.quotaReset(provider: "Claude", window: "5h")
        let thermalPeek = NotchPeek.thermalAlert(temperature: 84.0, state: "Elevado")
        let cpuPeek = NotchPeek.cpuPeak(process: "Xcode", usage: 85.0)

        #expect(center.isPeekEffective(for: quotaPeek) == true)
        #expect(center.isPeekEffective(for: thermalPeek) == true)
        #expect(center.isPeekEffective(for: cpuPeek) == true)
    }

    @Test("HomeCard AI Quotas and Heavy Processes properties and preferences")
    func homeCardsAIAndHeavyProcess() {
        let prefs = makeIsolatedPreferences()

        #expect(HomeCard.aiQuota.id == "aiQuota")
        #expect(HomeCard.heavyProcess.id == "heavyProcess")
        #expect(HomeCard.aiQuota.destinationTab == .home)
        #expect(HomeCard.heavyProcess.destinationTab == .home)
        #expect(!HomeCard.aiQuota.title.isEmpty)
        #expect(!HomeCard.heavyProcess.title.isEmpty)

        #expect(prefs.isHomeCardEnabled(.aiQuota) == true)
        #expect(prefs.isHomeCardEnabled(.heavyProcess) == true)

        prefs.setHomeCard(.aiQuota, enabled: false)
        #expect(prefs.isHomeCardEnabled(.aiQuota) == false)
        prefs.setHomeCard(.aiQuota, enabled: true)
        #expect(prefs.isHomeCardEnabled(.aiQuota) == true)

        #expect(prefs.isLiveActivityEnabled(.aiQuota) == true)
        #expect(prefs.isLiveActivityEnabled(.heavyProcess) == true)

        prefs.setLiveActivity(.heavyProcess, enabled: false)
        #expect(prefs.isLiveActivityEnabled(.heavyProcess) == false)
        prefs.setLiveActivity(.heavyProcess, enabled: true)
        #expect(prefs.isLiveActivityEnabled(.heavyProcess) == true)

        // Engine demand includes aiQuota and systemStats
        #expect(prefs.engineDemand.aiQuota == true)
        #expect(prefs.engineDemand.systemStats == true)
    }

    @Test("SystemMonitorEngine notch audience configures CPU and sensors sampling")
    func systemMonitorEngineNotchAudience() {
        let prefs = MonitorPreferences.shared
        let requestWithoutNotch = SystemMonitorEngine.makeRequest(
            prefs: prefs,
            panelModule: nil,
            windowActive: false,
            windowFocus: nil,
            dashboardActive: false,
            windowRankings: .cpu,
            notchAudience: false
        )
        #expect(requestWithoutNotch.processLimit == 0)

        let requestWithNotch = SystemMonitorEngine.makeRequest(
            prefs: prefs,
            panelModule: nil,
            windowActive: false,
            windowFocus: nil,
            dashboardActive: false,
            windowRankings: .cpu,
            notchAudience: true
        )
        #expect(requestWithNotch.processLimit == 3)
        #expect(requestWithNotch.processRankings.contains(.cpu))
        #expect(requestWithNotch.menuBarModules.contains(.cpu))
        #expect(requestWithNotch.menuBarModules.contains(.sensors))
        #expect(requestWithNotch.windowAudience == false)
    }
}

@Suite("MonoNotch Service & Manager Tests")
@MainActor
struct ServiceManagerTests {
    @Test("TimerManager operations: preset, nudging, laps, and reset")
    func timerManagerOperations() {
        let timer = TimerManager.shared
        timer.setPreset(120)

        #expect(timer.model.mode == .countdown)
        #expect(timer.model.remainingSeconds == 120)
        #expect(timer.model.targetDuration == 120)
        #expect(timer.model.isRunning == true)

        timer.addSeconds(30)
        #expect(timer.model.remainingSeconds == 150)
        #expect(timer.model.targetDuration == 150)

        timer.reset()
        #expect(timer.model.isRunning == false)
        #expect(timer.model.remainingSeconds == 150)
        #expect(timer.laps.isEmpty)

        // Stopwatch mode lap recording
        timer.model.mode = .stopwatch
        timer.model.isRunning = true
        timer.model.elapsedTime = 42
        timer.recordLap()
        #expect(timer.laps.count == 1)
        #expect(timer.laps.first == 42)

        timer.reset()
        #expect(timer.laps.isEmpty)
    }

    @Test("ShelfManager operations: add, deduplicate, remove, and clear")
    func shelfManagerOperations() {
        let shelf = ShelfManager.shared
        shelf.clearAll()
        #expect(shelf.items.isEmpty)

        let file1 = URL(fileURLWithPath: "/tmp/mononotch_test_file1.txt")
        let file2 = URL(fileURLWithPath: "/tmp/mononotch_test_file2.txt")

        shelf.addURLs([file1, file2])
        #expect(shelf.items.count == 2)

        // Adding duplicate URL should not create duplicate shelf items
        shelf.addURLs([file1])
        #expect(shelf.items.count == 2)

        if let firstID = shelf.items.first?.id {
            shelf.removeItem(id: firstID)
            #expect(shelf.items.count == 1)
        }

        shelf.clearAll()
        #expect(shelf.items.isEmpty)
    }

    @Test("CameraMirrorManager mirror toggle, effects, zoom, and exposure controls")
    func cameraMirrorOperations() {
        let camera = CameraMirrorManager.shared
        let prefs = NotchPreferences.shared
        let initialMirror = camera.isMirrored
        camera.toggleMirror()
        #expect(camera.isMirrored == !initialMirror)
        camera.toggleMirror()
        #expect(camera.isMirrored == initialMirror)

        let initialRing = prefs.cameraRingLightEnabled
        camera.toggleRingLight()
        #expect(prefs.cameraRingLightEnabled == !initialRing)
        camera.toggleRingLight()

        let initialGrid = prefs.cameraShowGrid
        camera.toggleGrid()
        #expect(prefs.cameraShowGrid == !initialGrid)
        camera.toggleGrid()

        camera.exposureBias = 0.5
        #expect(prefs.cameraExposureBias == 0.5)
        camera.resetEffects()
        #expect(prefs.cameraExposureBias == 0.0)
        #expect(prefs.cameraZoomFactor == 1.0)
    }

    @Test("Audio and display brightness clamping never touches the real hardware")
    func audioAndDisplayClamping() {
        #expect(AudioVolumeManager.clamped(1.5) == 1.0)
        #expect(AudioVolumeManager.clamped(-0.5) == 0.0)
        #expect(AudioVolumeManager.clamped(0.4) == 0.4)
        #expect(DisplayBrightnessManager.clamped(1.5) == 1.0)
        #expect(DisplayBrightnessManager.clamped(-0.5) == 0.0)
        #expect(AudioVolumeManager.shared.isMonitoring == false)
    }

    @Test("CalendarEventItem formatting, relativity, and all-day vs timed behavior")
    func calendarEventItemModel() {
        let now = Date()
        let inTenMinutes = now.addingTimeInterval(600)
        let inThirtyMinutes = now.addingTimeInterval(1800)
        let inNinetyMinutes = now.addingTimeInterval(5400)

        let upcomingEvent = CalendarEventItem(
            title: "Sprint Review",
            startDate: inThirtyMinutes,
            endDate: inNinetyMinutes,
            calendarTitle: "Trabalho"
        )

        #expect(upcomingEvent.title == "Sprint Review")
        #expect(!upcomingEvent.isAllDay)
        #expect(!upcomingEvent.isNow)
        #expect(upcomingEvent.startRelativeString.contains("in"))
        #expect(upcomingEvent.calendarTitle == "Trabalho")
        #expect(!upcomingEvent.isActiveOrStartingSoon(withinMinutes: 15))
        #expect(upcomingEvent.isActiveOrStartingSoon(withinMinutes: 45))

        let soonEvent = CalendarEventItem(
            title: "Daily Standup",
            startDate: inTenMinutes,
            endDate: inThirtyMinutes
        )
        #expect(soonEvent.isActiveOrStartingSoon(withinMinutes: 15))

        let allDayEvent = CalendarEventItem(
            title: "Holiday",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(86400),
            isAllDay: true
        )
        let originalLang = Localization.language
        defer { Localization.language = originalLang }
        Localization.language = .english
        #expect(allDayEvent.timeString == "All Day")
        #expect(allDayEvent.isNow == false)

        Localization.language = .portuguese
        #expect(soonEvent.shortIslandCountdown.contains("em "))
        #expect(allDayEvent.localizedTimeString == "Dia inteiro")
    }

    @Test("ReminderTask model and priority")
    func reminderTaskModel() {
        var task = ReminderTask(
            title: "Ship MonoNotch v0.0.1",
            isCompleted: false,
            dueDate: Date(),
            priority: 1
        )

        #expect(task.title == "Ship MonoNotch v0.0.1")
        #expect(task.isCompleted == false)
        #expect(task.dueDateString != nil)

        task.isCompleted = true
        #expect(task.isCompleted == true)
    }

    @Test("Long duration MusicTrack time formatting")
    func musicTrackLongDurations() {
        let longTrack = MusicTrack(
            title: "Podcast Episode",
            artist: "Host",
            album: "Show",
            duration: 3665,
            elapsed: 3600,
            isPlaying: true,
            playerType: .podcasts
        )

        #expect(longTrack.formattedDuration == "1:01:05")
        #expect(longTrack.formattedElapsed == "1:00:00")
    }

    @Test("Notch autoAdjustHeight and effectiveExpandedHeight per tab")
    func autoAdjustHeightCalculation() {
        let prefs = makeIsolatedPreferences()
        prefs.autoAdjustHeight = true

        let homeHeight = prefs.effectiveExpandedHeight(for: .home)
        #expect(homeHeight >= 185 && homeHeight <= 492)

        let musicHeight = prefs.effectiveExpandedHeight(for: .music)
        #expect(musicHeight == (prefs.musicShowAudioRouteSelector ? 248 : 195))

        let timerHeight = prefs.effectiveExpandedHeight(for: .timer)
        #expect(timerHeight == 230)

        let mirrorHeight = prefs.effectiveExpandedHeight(for: .mirror)
        #expect(mirrorHeight == 315)

        // When autoAdjustHeight is disabled, effectiveExpandedHeight returns openNotchHeight
        prefs.autoAdjustHeight = false
        prefs.openNotchHeight = 220
        #expect(prefs.effectiveExpandedHeight(for: .home) == 220)
        #expect(prefs.effectiveExpandedHeight(for: .music) == 220)
        #expect(prefs.effectiveExpandedHeight(for: .timer) == 220)
    }
}

@Suite("MonoNotch Lifecycle & Engine Demand Tests")
@MainActor
struct EngineDemandTests {
    @Test("Default preferences demand every engine")
    func defaultDemand() {
        let demand = makeIsolatedPreferences().engineDemand
        #expect(demand.media)
        #expect(demand.calendar)
        #expect(demand.reminders)
        #expect(demand.battery)
        #expect(demand.bluetooth)
        #expect(demand.timer)
        #expect(demand.mirror)
        #expect(demand.systemHUD)
        #expect(demand.statusItem)
        #expect(demand.scrollMonitor)
    }

    @Test("Disabling a module and everything that needs it stops its engine")
    func disabledModulesHaveNoDemand() {
        let prefs = makeIsolatedPreferences()
        prefs.enableMusicModule = false
        #expect(prefs.engineDemand.media)
        prefs.showMusicLiveActivity = false
        #expect(prefs.engineDemand.media)
        prefs.showHomeMusicCard = false
        #expect(!prefs.engineDemand.media)

        prefs.enableCalendarModule = false
        prefs.showCalendarLiveActivity = false
        prefs.enableHomeModule = false
        #expect(!prefs.engineDemand.calendar)
        #expect(!prefs.engineDemand.timer || prefs.enableTimerModule)

        prefs.enableBluetoothModule = false
        #expect(!prefs.engineDemand.bluetooth)

        prefs.enableRemindersModule = false
        prefs.enableMirrorModule = false
        prefs.enableTimerModule = false
        prefs.scrollAction = .disabled
        prefs.showInMenuBar = false
        #expect(!prefs.engineDemand.reminders)
        #expect(!prefs.engineDemand.mirror)
        #expect(!prefs.engineDemand.timer)
        #expect(!prefs.engineDemand.scrollMonitor)
        #expect(!prefs.engineDemand.statusItem)

        prefs.enableBatteryModule = false
        prefs.showBatteryLiveActivity = false
        prefs.enableSystemHUD = false
        #expect(!prefs.engineDemand.battery)
        #expect(!prefs.engineDemand.systemHUD)
    }

    @Test("Home card only keeps an engine alive while the Home module is enabled")
    func homeCardDemand() {
        let prefs = makeIsolatedPreferences()
        prefs.enableBluetoothModule = false
        prefs.showHomeBluetoothCard = true
        #expect(prefs.engineDemand.bluetooth)
        prefs.enableHomeModule = false
        #expect(!prefs.engineDemand.bluetooth)
    }

    @Test("Active tab falls back to the first enabled tab")
    func resolvedActiveTab() {
        let prefs = makeIsolatedPreferences()
        prefs.selectTab(.mirror)
        #expect(prefs.resolvedActiveTab == .mirror)
        prefs.enableMirrorModule = false
        #expect(prefs.resolvedActiveTab == prefs.availableTabs.first)
        #expect(!prefs.availableTabs.contains(.mirror))

        for tab in NotchTab.allCases {
            prefs.setTab(tab, enabled: false)
        }
        #expect(prefs.availableTabs == [.home])
        #expect(prefs.resolvedActiveTab == .home)
    }

    @Test("Reordering helper ignores out-of-range moves")
    func movedHelper() {
        let list: [HomeCard] = [.music, .calendar, .timer]
        #expect(NotchPreferences.moved(list, from: 0, to: 1) == [.calendar, .music, .timer])
        #expect(NotchPreferences.moved(list, from: 2, to: 1) == [.music, .timer, .calendar])
        #expect(NotchPreferences.moved(list, from: 0, to: -1) == list)
        #expect(NotchPreferences.moved(list, from: 2, to: 3) == list)
    }
}

@Suite("MonoNotch Engine Logic Tests")
@MainActor
struct EngineLogicTests {
    @Test("Calendar boundary picks the next lead, start, or end moment")
    func calendarBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let event = CalendarEventItem(
            title: "Review",
            startDate: now.addingTimeInterval(30 * 60),
            endDate: now.addingTimeInterval(60 * 60)
        )
        let allDay = CalendarEventItem(
            title: "Feriado",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(86_400),
            isAllDay: true
        )
        let next = LiveActivityCenter.nextCalendarBoundary(after: now, events: [event, allDay], leadMinutes: 15)
        #expect(next == now.addingTimeInterval(15 * 60))

        let insideLead = LiveActivityCenter.nextCalendarBoundary(after: now.addingTimeInterval(20 * 60), events: [event], leadMinutes: 15)
        #expect(insideLead == event.startDate)

        let during = LiveActivityCenter.nextCalendarBoundary(after: now.addingTimeInterval(45 * 60), events: [event], leadMinutes: 15)
        #expect(during == event.endDate)

        #expect(LiveActivityCenter.nextCalendarBoundary(after: now.addingTimeInterval(2 * 3600), events: [event], leadMinutes: 15) == nil)
    }

    @Test("AppleScript now-playing output parsing")
    func scriptParsing() {
        let music = NowPlayingSnapshot.parseScriptResult("Song:::Artist:::Album:::245,5:::12,25:::true", playerHint: .appleMusic)
        #expect(music?.title == "Song")
        #expect(music?.duration == 245.5)
        #expect(music?.elapsed == 12.25)
        #expect(music?.isPlaying == true)
        #expect(music?.bundleID == "com.apple.Music")

        let spotify = NowPlayingSnapshot.parseScriptResult("Track:::Band:::LP:::180000:::30:::false", playerHint: .spotify, durationDivisor: 1000)
        #expect(spotify?.duration == 180)
        #expect(spotify?.isPlaying == false)
        #expect(spotify?.appName == "Spotify")

        #expect(NowPlayingSnapshot.parseScriptResult("NONE", playerHint: .appleMusic) == nil)
        #expect(NowPlayingSnapshot.parseScriptResult(":::a:::b:::1:::0:::true", playerHint: .appleMusic) == nil)
        #expect(NowPlayingSnapshot.parseClock("1:02:03") == 3723)
        #expect(MusicTrack.format(3723) == "1:02:03")
    }

    @Test("Bluetooth merge keeps stable IDs, enriches batteries, and sorts connected first")
    func bluetoothMerge() {
        let native = [
            BluetoothNativeDevice(name: "Magic Keyboard", address: "AA:BB:CC:DD:EE:01", isConnected: false, rssi: nil),
            BluetoothNativeDevice(name: "AirPods Pro", address: "AA:BB:CC:DD:EE:02", isConnected: true, rssi: -50)
        ]
        var power = BluetoothTelemetryEntry(name: "AirPods Pro")
        power.batteryLeft = 80
        power.batteryRight = 70
        power.batteryCase = 50
        let merged = BluetoothManager.merge(
            nativeDevices: native,
            telemetry: [:],
            accessoryPower: ["airpods pro": power],
            hidBatteries: ["aa-bb-cc-dd-ee-01": 42]
        )
        #expect(merged.count == 2)
        #expect(merged[0].name == "AirPods Pro")
        #expect(merged[0].id == "aa-bb-cc-dd-ee-02")
        #expect(merged[0].batteryLeftLevel == 80)
        #expect(merged[0].category == .airpods)
        #expect(merged[1].batteryLevel == 42)
        #expect(merged[1].category == .keyboard)
    }

    @Test("Timer mode switch pauses and resets, nudging to zero completes")
    func timerModeAndCompletion() {
        let timer = TimerManager.shared
        timer.setPreset(60)
        #expect(timer.isTicking)
        timer.setMode(.stopwatch)
        #expect(timer.model.mode == .stopwatch)
        #expect(timer.model.isRunning == false)
        #expect(timer.isTicking == false)
        #expect(timer.model.elapsedTime == 0)

        timer.setMode(.countdown)
        timer.setPreset(60)
        let completions = timer.completionCount
        timer.addSeconds(-120)
        #expect(timer.completionCount == completions + 1)
        #expect(timer.model.isRunning == false)
        #expect(timer.isTicking == false)
        timer.reset()
    }

    @Test("Engines stay idle until the feature activates them")
    func enginesIdleByDefault() {
        #expect(MediaPlaybackManager.shared.isRunning == false)
        #expect(CalendarManager.shared.isRunning == false)
        #expect(RemindersManager.shared.isRunning == false)
        #expect(BluetoothManager.shared.isEnabled == false)
        #expect(BatteryManager.shared.isMonitoring == false)
        #expect(SystemHUDInterceptor.shared.isInterceptionActive == false)
        #expect(NotchFeature.isRunning == false)
    }
}

@Suite("Notch header around the hardware notch")
@MainActor
struct NotchHardwareHeaderTests {
    @Test("Hardware notch header keeps content height and shrinks the island")
    func headerHeightKeepsContentArea() {
        let prefs = NotchPreferences.shared
        let wasAuto = prefs.autoAdjustHeight
        prefs.autoAdjustHeight = true
        defer { prefs.autoAdjustHeight = wasAuto }

        let hardware = ScreenNotchGeometry(
            hasHardwareNotch: true,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            notchWidth: 190,
            notchHeight: 32
        )
        let external = ScreenNotchGeometry(
            hasHardwareNotch: false,
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            notchWidth: 160,
            notchHeight: 28
        )

        #expect(hardware.expandedHeaderHeight >= 34)
        #expect(hardware.expandedNotchGap == 206)
        #expect(external.expandedNotchGap == 0)
        #expect(external.expandedHeaderHeight == ScreenNotchGeometry.standardHeaderHeight)

        for tab in NotchTab.allCases where tab != .home {
            let onHardware = prefs.effectiveExpandedHeight(for: tab, headerHeight: hardware.expandedHeaderHeight)
            let standard = prefs.effectiveExpandedHeight(for: tab)
            #expect(onHardware - hardware.expandedHeaderHeight == standard - ScreenNotchGeometry.standardHeaderHeight)
        }
    }

    @Test("Idle animations, hardware notch wings, and module customization preferences")
    func idleAnimationsAndModuleCustomizations() {
        let prefs = makeIsolatedPreferences()
        #expect(prefs.idleAnimation == .bongoCat)
        #expect(prefs.idleInteractionMode == .interactive)
        #expect(prefs.hasIdleContentEnabled == true)

        prefs.idleAnimation = .none
        #expect(prefs.hasIdleContentEnabled == false)
        #expect(prefs.engineDemand.idleMonitor == false)

        prefs.idleAnimation = .starWars
        prefs.idleInteractionMode = .onlyWhenTyping
        #expect(prefs.idleInteractionMode == .onlyWhenTyping)
        #expect(prefs.hasIdleContentEnabled == true)
        #expect(prefs.engineDemand.idleMonitor == true)

        let monitor = IdleInteractionMonitor.shared
        let initialStrokes = monitor.strokeCount
        monitor.recordEvent(isKey: true)
        #expect(monitor.strokeCount == initialStrokes + 1)
        #expect(monitor.isInteracting == true)
        #expect(monitor.energy > 0)

        // Mouse clicks must not increment keyboard strokeCount (so Bongo Cat text never advances without keys)
        monitor.recordEvent(isKey: false)
        #expect(monitor.strokeCount == initialStrokes + 1)

        // Phase snapshot must be smooth and never jump by millions when energy decays
        let now = Date()
        let snap1 = monitor.snapshot(at: now, mode: .interactive, speedMultiplier: 1.0)
        let snap2 = monitor.snapshot(at: now.addingTimeInterval(0.05), mode: .interactive, speedMultiplier: 1.0)
        #expect(snap2.phase >= snap1.phase)
        #expect(snap2.phase - snap1.phase < 1.0)
        #expect(NotchIdleAnimation.bongoCat.resolved(at: Date()) == .bongoCat)
        #expect(NotchIdleAnimation.fromStored("kittScanner") == .lordOfTheRings)
        #expect(NotchIdleAnimation.fromStored("hal9000") == .samurai)
        #expect(NotchIdleAnimation.fromStored("codingTerminal") == .pokemon)
        #expect(NotchIdleAnimation.random.resolved(at: Date()) != .none)
        #expect(NotchIdleAnimation.random.resolved(at: Date()) != .random)
        #expect(prefs.idleWithActivityMode == .sideBySide)

        let sharedSideBySideMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .music,
            secondary: nil,
            layout: .combined,
            hudVisible: false,
            hasPeek: false,
            hasIdleContent: true,
            idleWingWidth: 70,
            idleWithActivityMode: .sideBySide
        )
        #expect(sharedSideBySideMetrics.width >= 377)
        #expect(sharedSideBySideMetrics.hasAnimationBubble == false)

        let timerMusicAndAnimHardware = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: .music,
            layout: .split,
            hudVisible: false,
            hasPeek: false,
            hasIdleContent: true,
            idleWingWidth: 66,
            idleWithActivityMode: .sideBySide
        )
        #expect(timerMusicAndAnimHardware.width >= 377)
        #expect(timerMusicAndAnimHardware.hasBubble == true)
        #expect(timerMusicAndAnimHardware.hasAnimationBubble == false)

        let timerMusicAndAnimVirtual = LiveActivityCenter.metrics(
            hasHardwareNotch: false,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: .music,
            layout: .split,
            hudVisible: false,
            hasPeek: false,
            hasIdleContent: true,
            idleWingWidth: 66,
            idleWithActivityMode: .sideBySide
        )
        #expect(timerMusicAndAnimVirtual.width == 285)
        #expect(timerMusicAndAnimVirtual.hasBubble == true)

        let sharedBubbleMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: .timer,
            secondary: nil,
            layout: .combined,
            hudVisible: false,
            hasPeek: false,
            hasIdleContent: true,
            idleWingWidth: 70,
            idleWithActivityMode: .detachedBubble
        )
        #expect(sharedBubbleMetrics.hasBubble == true)
        #expect(sharedBubbleMetrics.hasAnimationBubble == true)

        let idleHardwareMetrics = LiveActivityCenter.metrics(
            hasHardwareNotch: true,
            notchWidth: 185,
            notchHeight: 32,
            idleVirtualWidth: 185,
            primary: nil,
            secondary: nil,
            layout: .split,
            hudVisible: false,
            hasPeek: false,
            hasIdleContent: true,
            idleWingWidth: 70
        )
        #expect(Int(idleHardwareMetrics.width) == 325)

        prefs.hardwareNotchTabBarStyle = .splitEars
        #expect(prefs.hardwareNotchTabBarStyle == .splitEars)

        prefs.musicShowVisualizer = false
        prefs.timerDefaultMinutes = 25
        prefs.calendarMaxEventsShown = 8
        prefs.remindersShowCompleted = true
        prefs.batteryShowThermalState = false
        prefs.bluetoothHideDisconnected = true
        prefs.shelfClickAction = .revealInFinder
        prefs.shelfMaxItems = 16

        prefs.resetToDefaults()
        #expect(prefs.idleAnimation == .bongoCat)
        #expect(prefs.hardwareNotchTabBarStyle == .unifiedBelow)
        #expect(prefs.musicShowVisualizer == true)
        #expect(prefs.timerDefaultMinutes == 5)
        #expect(prefs.calendarMaxEventsShown == 5)
        #expect(prefs.remindersShowCompleted == false)
        #expect(prefs.batteryShowThermalState == true)
        #expect(prefs.bluetoothHideDisconnected == false)
        #expect(prefs.shelfClickAction == .openFile)
        #expect(prefs.shelfMaxItems == 12)
    }

    @Test("System stats background demand separates live alerts from expanded-only Home card")
    func systemStatsBackgroundDemandSeparation() {
        let prefs = makeIsolatedPreferences()
        prefs.showHomeHeavyProcessCard = true
        prefs.showHeavyProcessLiveActivity = false
        prefs.showSystemAlertPeek = false
        #expect(prefs.engineDemand.systemStats == true)
        #expect(prefs.engineDemand.systemStatsBackground == false)

        prefs.showHeavyProcessLiveActivity = true
        #expect(prefs.engineDemand.systemStatsBackground == true)

        prefs.showHeavyProcessLiveActivity = false
        prefs.showSystemAlertPeek = true
        #expect(prefs.engineDemand.systemStatsBackground == true)

        prefs.showHomeHeavyProcessCard = false
        prefs.showSystemAlertPeek = false
        #expect(prefs.engineDemand.systemStats == false)
        #expect(prefs.engineDemand.systemStatsBackground == false)
    }
}
