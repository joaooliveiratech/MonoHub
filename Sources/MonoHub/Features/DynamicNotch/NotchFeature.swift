import Foundation
import Observation

@MainActor
enum NotchFeature: FeatureModule {
    private static var isActive = false
    private static var demandTask: Task<Void, Never>?
    private static var audienceTask: Task<Void, Never>?
    private static var appliedDemand: NotchEngineDemand = .none

    static var isRunning: Bool { isActive }

    static func activate() {
        guard !isActive else { return }
        isActive = true

        DisplayManager.shared.start()
        AppExclusionManager.shared.start()
        NotchWindowController.shared.start()
        LiveActivityCenter.shared.start()
        AppExclusionManager.shared.evaluateSuppression()

        apply(NotchPreferences.shared.engineDemand)
        syncDynamicAudience()

        demandTask = Task {
            let stream = Observations { @MainActor in
                NotchPreferences.shared.engineDemand
            }
            for await demand in stream {
                guard isActive, !Task.isCancelled else { break }
                apply(demand)
                syncDynamicAudience()
            }
        }

        audienceTask = Task {
            let stream = Observations { @MainActor in
                NotchAudienceSnapshot(
                    isExpanded: NotchWindowController.shared.isExpanded,
                    activeTab: NotchPreferences.shared.resolvedActiveTab,
                    isDisplayAsleep: NotchWindowController.shared.isDisplayAsleep,
                    isSuppressed: AppExclusionManager.shared.isSuppressed,
                    idleInteractionMode: NotchPreferences.shared.idleInteractionMode
                )
            }
            for await _ in stream {
                guard isActive, !Task.isCancelled else { break }
                syncDynamicAudience()
            }
        }
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false
        demandTask?.cancel()
        demandTask = nil
        audienceTask?.cancel()
        audienceTask = nil

        apply(.none)
        IdleInteractionMonitor.shared.stop()
        LiveActivityCenter.shared.stop()
        HUDManager.shared.hide()
        NotchWindowController.shared.stop()
        AppExclusionManager.shared.stop()
        DisplayManager.shared.stop()
    }

    static func syncDynamicAudience() {
        guard isActive else { return }
        let controller = NotchWindowController.shared
        let prefs = NotchPreferences.shared
        let demand = appliedDemand
        let awakeAndVisible = !controller.isDisplayAsleep && !AppExclusionManager.shared.isSuppressed

        let needsSystemStatsAudience = FeatureManager.shared.isEnabled(.systemMonitor)
            && awakeAndVisible
            && (demand.systemStatsBackground
                || (demand.systemStats && controller.isExpanded && prefs.resolvedActiveTab == .home))

        let monitorEngine = SystemMonitorEngine.shared
        monitorEngine.setNotchAudience(needsSystemStatsAudience)
        if needsSystemStatsAudience && !monitorEngine.isActive {
            monitorEngine.activate()
        } else if !needsSystemStatsAudience && !FeatureManager.shared.isEnabled(.systemMonitor) && monitorEngine.isActive {
            monitorEngine.deactivate()
        }

        if demand.idleMonitor && awakeAndVisible {
            IdleInteractionMonitor.shared.ensureStarted()
            IdleInteractionMonitor.shared.syncInteractionMonitors()
            IdleInteractionMonitor.shared.syncRenderTimer()
        } else {
            IdleInteractionMonitor.shared.stop()
        }

        NotchWindowController.shared.setScrollMonitoring(demand.scrollMonitor && awakeAndVisible)

        if controller.isExpanded && awakeAndVisible {
            let tab = prefs.resolvedActiveTab
            if demand.clipboard && (tab == .clipboard || (tab == .home && prefs.isHomeCardVisible(.clipboard))) {
                ClipboardManager.shared.pollPasteboard()
            }
        } else if !controller.isExpanded {
            let teleprompter = TeleprompterManager.shared
            if teleprompter.isPlaying && !prefs.teleprompterKeepOpenWhilePlaying {
                teleprompter.pause()
            }
        }
    }

    private static func apply(_ demand: NotchEngineDemand) {
        let previous = appliedDemand
        guard demand != previous || demand == .none else { return }
        appliedDemand = demand

        toggle(demand.media, MediaPlaybackManager.shared.start, MediaPlaybackManager.shared.stop)
        toggle(demand.calendar, CalendarManager.shared.start, CalendarManager.shared.stop)
        toggle(demand.reminders, RemindersManager.shared.start, RemindersManager.shared.stop)
        toggle(demand.battery, BatteryManager.shared.startMonitoring, BatteryManager.shared.stopMonitoring)
        toggle(demand.bluetooth, BluetoothManager.shared.start, BluetoothManager.shared.stop)
        toggle(demand.systemHUD, SystemHUDInterceptor.shared.start, SystemHUDInterceptor.shared.stop)
        toggle(demand.systemHUD, AudioVolumeManager.shared.startMonitoring, AudioVolumeManager.shared.stopMonitoring)
        toggle(demand.media || demand.systemHUD, { AudioDeviceManager.shared.startMonitoring(client: "NotchFeature") }, { AudioDeviceManager.shared.stopMonitoring(client: "NotchFeature") })
        toggle(demand.clipboard, ClipboardManager.shared.start, ClipboardManager.shared.stop)
        toggle(demand.aiQuota, {
            if FeatureManager.shared.isEnabled(.aiQuota) && !AIQuotaFeature.isActive {
                AIQuotaFeature.activate()
            }
        }, {
            if !FeatureManager.shared.isEnabled(.aiQuota) && AIQuotaFeature.isActive {
                AIQuotaFeature.deactivate()
            }
        })

        if !demand.systemStats {
            let engine = SystemMonitorEngine.shared
            engine.setNotchAudience(false)
            if !FeatureManager.shared.isEnabled(.systemMonitor), engine.isActive {
                engine.deactivate()
            }
        }
        if !demand.idleMonitor {
            IdleInteractionMonitor.shared.stop()
        }
        if !demand.systemHUD {
            HUDManager.shared.hide()
        }
        if !demand.mirror && !demand.teleprompter {
            CameraMirrorManager.shared.releaseResources()
        }
        if !demand.timer {
            TimerManager.shared.reset()
        }
        if !demand.teleprompter {
            TeleprompterManager.shared.pause()
        }
        NotchStatusItemController.shared.setVisible(demand.statusItem)
        NotchWindowController.shared.setScrollMonitoring(demand.scrollMonitor && !NotchWindowController.shared.isDisplayAsleep && !AppExclusionManager.shared.isSuppressed)
    }

    private static func toggle(_ enabled: Bool, _ start: @MainActor () -> Void, _ stop: @MainActor () -> Void) {
        if enabled {
            start()
        } else {
            stop()
        }
    }
}

private nonisolated struct NotchAudienceSnapshot: Equatable, Sendable {
    let isExpanded: Bool
    let activeTab: NotchTab
    let isDisplayAsleep: Bool
    let isSuppressed: Bool
    let idleInteractionMode: NotchIdleInteractionMode
}
