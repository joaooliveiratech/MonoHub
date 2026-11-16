import Foundation
import Observation

@MainActor
enum NotchFeature: FeatureModule {
    private static var isActive = false
    private static var demandTask: Task<Void, Never>?
    private static var appliedDemand: NotchEngineDemand = .none

    static var isRunning: Bool { isActive }

    static func activate() {
        guard !isActive else { return }
        isActive = true

        DisplayManager.shared.start()
        AppExclusionManager.shared.start()
        NotchWindowController.shared.start()
        LiveActivityCenter.shared.start()
        IdleInteractionMonitor.shared.ensureStarted()
        AppExclusionManager.shared.evaluateSuppression()

        apply(NotchPreferences.shared.engineDemand)
        demandTask = Task {
            let stream = Observations { @MainActor in
                NotchPreferences.shared.engineDemand
            }
            for await demand in stream {
                guard isActive, !Task.isCancelled else { break }
                apply(demand)
            }
        }
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false
        demandTask?.cancel()
        demandTask = nil

        apply(.none)
        IdleInteractionMonitor.shared.stop()
        LiveActivityCenter.shared.stop()
        HUDManager.shared.hide()
        NotchWindowController.shared.stop()
        AppExclusionManager.shared.stop()
        DisplayManager.shared.stop()
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
        toggle(demand.systemStats, {
            guard FeatureManager.shared.isEnabled(.systemMonitor) else { return }
            SystemMonitorEngine.shared.setNotchAudience(true)
            if !SystemMonitorEngine.shared.isActive {
                SystemMonitorEngine.shared.activate()
            }
        }, {
            let engine = SystemMonitorEngine.shared
            engine.setNotchAudience(false)
            if !FeatureManager.shared.isEnabled(.systemMonitor), engine.isActive {
                engine.deactivate()
            }
        })
        toggle(demand.aiQuota, {
            if FeatureManager.shared.isEnabled(.aiQuota) && !AIQuotaFeature.isActive {
                AIQuotaFeature.activate()
            }
        }, {
            if !FeatureManager.shared.isEnabled(.aiQuota) && AIQuotaFeature.isActive {
                AIQuotaFeature.deactivate()
            }
        })

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
        NotchWindowController.shared.setScrollMonitoring(demand.scrollMonitor)
    }

    private static func toggle(_ enabled: Bool, _ start: @MainActor () -> Void, _ stop: @MainActor () -> Void) {
        if enabled {
            start()
        } else {
            stop()
        }
    }
}
