import SwiftUI

enum AIQuotaStyle {
    static let symbol = "gauge.with.dots.needle.67percent"
    static let tint = Color(red: 0.91, green: 0.45, blue: 0.35)
}

@MainActor
enum AIQuotaFeature: FeatureModule {
    private(set) static var isActive = false

    static func activate() {
        guard !isActive else { return }
        isActive = true
        AIQuotaStatusItemController.shared.setup()
        QuotaManager.shared.start()
        if QuotaPreferencesManager.shared.notificationsEnabled {
            Task { await NotificationService.shared.requestAuthorization() }
        }
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false
        QuotaManager.shared.stop()
        AIQuotaStatusItemController.shared.teardown()
        LiveActivityCenter.shared.clearAIQuota()
    }
}
