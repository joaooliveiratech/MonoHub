import Foundation

nonisolated struct SensorsData: Sendable, Equatable {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var socTemperature: Double?
    var socTemperatureMax: Double?
    var ssdTemperature: Double?
    var batteryTemperature: Double?
    var history = RollingHistory()
    var uptimeSeconds: TimeInterval = 0

    var thermalDescription: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return localized("Fair")
        case .serious: return localized("Serious")
        case .critical: return localized("Critical")
        @unknown default: return "Normal"
        }
    }

    var thermalDetail: String {
        switch thermalState {
        case .nominal: return localized("None")
        case .fair: return localized("Light")
        case .serious: return localized("Moderate")
        case .critical: return localized("Heavy")
        @unknown default: return localized("None")
        }
    }

    var formattedTemperature: String {
        Formatting.temperature(socTemperature)
    }

    var formattedUptime: String {
        Formatting.uptime(uptimeSeconds)
    }
}
