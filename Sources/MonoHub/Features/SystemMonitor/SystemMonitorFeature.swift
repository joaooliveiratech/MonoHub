import Foundation

@MainActor
enum SystemMonitorFeature: FeatureModule {
    static func activate() {
        SystemMonitorEngine.shared.activate()
        StatusItemController.shared.setup()
        SystemMonitorEngine.shared.reloadConfiguration()
    }

    static func deactivate() {
        StatusItemController.shared.teardown()

        let engine = SystemMonitorEngine.shared
        engine.setNotchAudience(false)
        engine.deactivate()
        ProcessBandwidthEngine.shared.stop()
        MenuBarRenderer.purgeCaches()
    }
}
