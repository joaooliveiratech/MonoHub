import Foundation

nonisolated struct BatteryInfo: Sendable, Equatable {
    let percentage: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isLowPowerMode: Bool
    let timeRemainingMinutes: Int
    let maxCapacity: Int

    init(
        percentage: Int = 100,
        isCharging: Bool = false,
        isPluggedIn: Bool = true,
        isLowPowerMode: Bool = false,
        timeRemainingMinutes: Int = -1,
        maxCapacity: Int = 100
    ) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isLowPowerMode = isLowPowerMode
        self.timeRemainingMinutes = timeRemainingMinutes
        self.maxCapacity = maxCapacity
    }

    static let standard = BatteryInfo()

    var statusDescription: String {
        if isCharging {
            if timeRemainingMinutes > 0 {
                return localized("%@ until full", Self.format(minutes: timeRemainingMinutes))
            }
            return localized("Charging")
        } else if isPluggedIn {
            return localized("Connected to power")
        } else {
            if timeRemainingMinutes > 0 {
                return localized("%@ remaining", Self.format(minutes: timeRemainingMinutes))
            }
            return localized("On battery")
        }
    }

    static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)min" : "\(remainder)min"
    }
}
