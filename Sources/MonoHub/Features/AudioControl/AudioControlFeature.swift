import Foundation

@MainActor
enum AudioControlFeature: FeatureModule {
    private static let clientID = "audioControlFeature"

    static func activate() {
        AudioDeviceManager.shared.startMonitoring(client: clientID)
        AudioProcessVolumeManager.shared.startMonitoring(client: clientID)
    }

    static func deactivate() {
        AudioProcessVolumeManager.shared.teardownAllTaps()
        AudioProcessVolumeManager.shared.stopMonitoring(client: clientID)
        AudioDeviceManager.shared.stopMonitoring(client: clientID)
    }
}
