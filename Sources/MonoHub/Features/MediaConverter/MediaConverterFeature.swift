import Foundation

@MainActor
enum MediaConverterFeature: FeatureModule {
    static func activate() {}

    static func deactivate() {
        ConversionQueueManager.shared.cancelAll()
    }
}
