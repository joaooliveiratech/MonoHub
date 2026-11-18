import Foundation

@MainActor
enum ProductivityFeature: FeatureModule {
    static func activate() {
        URLRouterService.shared.start()
        SnippetManager.shared.start()
        BluetoothQuickConnectManager.shared.start()
    }

    static func deactivate() {
        URLRouterService.shared.stop()
        SnippetManager.shared.stop()
        BluetoothQuickConnectManager.shared.stop()
    }
}
