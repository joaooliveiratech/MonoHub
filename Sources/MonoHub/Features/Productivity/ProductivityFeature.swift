import Foundation

@MainActor
enum ProductivityFeature: FeatureModule {
    static func activate() {
        URLRouterService.shared.start()
        SnippetManager.shared.start()
        BluetoothQuickConnectManager.shared.start()
        AudioDeviceManager.shared.startMonitoring(client: "ProductivityFeature")
    }

    static func deactivate() {
        URLRouterService.shared.stop()
        SnippetManager.shared.stop()
        BluetoothQuickConnectManager.shared.stop()
        AudioDeviceManager.shared.stopMonitoring(client: "ProductivityFeature")
    }
}
