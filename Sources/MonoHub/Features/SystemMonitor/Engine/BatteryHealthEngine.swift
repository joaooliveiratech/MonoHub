import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor
@Observable
final class BatteryHealthEngine {
    static let shared = BatteryHealthEngine()

    struct BatterySample: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let levelPercent: Int
        let watts: Double
        let temperatureCelsius: Double?
        let isCharging: Bool
    }

    private(set) var history: [BatterySample] = []
    private let maxHistorySamples = 60

    var alertAt80Percent: Bool {
        didSet { UserDefaults.standard.set(alertAt80Percent, forKey: "MonoBattery_Alert80") }
    }
    var alertAt100Percent: Bool {
        didSet { UserDefaults.standard.set(alertAt100Percent, forKey: "MonoBattery_Alert100") }
    }
    var alertOnHighTemp: Bool {
        didSet { UserDefaults.standard.set(alertOnHighTemp, forKey: "MonoBattery_AlertHighTemp") }
    }

    private var hasAlerted80ThisSession = false
    private var hasAlerted100ThisSession = false
    private var hasAlertedHighTempThisSession = false
    private var lastChargingState = false

    private init() {
        self.alertAt80Percent = UserDefaults.standard.bool(forKey: "MonoBattery_Alert80")
        self.alertAt100Percent = UserDefaults.standard.bool(forKey: "MonoBattery_Alert100")
        self.alertOnHighTemp = UserDefaults.standard.bool(forKey: "MonoBattery_AlertHighTemp")
    }

    func recordSample(from battery: BatteryData) {
        guard battery.hasBattery else { return }

        if !battery.isCharging && lastChargingState {
            hasAlerted80ThisSession = false
            hasAlerted100ThisSession = false
        }
        if battery.levelPercent < 78 {
            hasAlerted80ThisSession = false
        }
        if battery.levelPercent < 98 {
            hasAlerted100ThisSession = false
        }
        if let temp = battery.temperatureCelsius, temp < 38 {
            hasAlertedHighTempThisSession = false
        }
        lastChargingState = battery.isCharging

        let sample = BatterySample(
            timestamp: Date(),
            levelPercent: battery.levelPercent,
            watts: battery.batteryPowerWatts,
            temperatureCelsius: battery.temperatureCelsius,
            isCharging: battery.isCharging
        )

        history.append(sample)
        if history.count > maxHistorySamples {
            history.removeFirst(history.count - maxHistorySamples)
        }

        evaluateAlerts(for: battery)
    }

    private func evaluateAlerts(for battery: BatteryData) {
        if battery.isCharging {
            if alertAt80Percent, !hasAlerted80ThisSession, battery.levelPercent >= 80, battery.levelPercent < 90 {
                hasAlerted80ThisSession = true
                sendNotification(
                    title: localized("Battery at 80%"),
                    body: localized("Battery has reached 80% charge. You can disconnect power to optimize battery longevity.")
                )
            }

            if alertAt100Percent, !hasAlerted100ThisSession, battery.levelPercent >= 100 {
                hasAlerted100ThisSession = true
                sendNotification(
                    title: localized("Battery Fully Charged"),
                    body: localized("Battery is at 100% capacity.")
                )
            }
        }

        if alertOnHighTemp, !hasAlertedHighTempThisSession, let temp = battery.temperatureCelsius, temp >= 42.0 {
            hasAlertedHighTempThisSession = true
            sendNotification(
                title: localized("High Battery Temperature"),
                body: localized("Battery temperature reached %@. Reduce intense workloads or allow cooling.", Formatting.temperature(temp))
            )
        }
    }

    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
