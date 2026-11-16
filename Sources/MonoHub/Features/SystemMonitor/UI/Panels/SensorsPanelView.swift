import SwiftUI

struct SensorsPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let hardware = HardwareInfo.shared

    var body: some View {
        let sensors = engine.sensorsData
        let thermalTint = UsageColor.forThermal(sensors.thermalState)

        PanelHeader(title: localized("Temperature"), subtitle: localized("Thermal state: %@", sensors.thermalDescription), symbol: "thermometer.medium", tint: ModuleType.sensors.tint) {
            HeroValue(value: sensors.formattedTemperature, tint: UsageColor.forTemperature(sensors.socTemperature))
        }

        if sensors.history.values.count > 1 {
            Platter {
                HistoryChart(values: sensors.history.values, tint: .orange, fixedMaximum: 110)
            }
        }

        HStack(spacing: 8) {
            StatTile(title: localized("Chip (average)"), value: Formatting.temperature(sensors.socTemperature), tint: UsageColor.forTemperature(sensors.socTemperature))
            StatTile(title: localized("Chip (max)"), value: Formatting.temperature(sensors.socTemperatureMax), tint: UsageColor.forTemperature(sensors.socTemperatureMax))
        }
        HStack(spacing: 8) {
            StatTile(title: "SSD", value: Formatting.temperature(sensors.ssdTemperature), tint: .orange)
            StatTile(title: localized("Battery"), value: Formatting.temperature(sensors.batteryTemperature), tint: .green)
        }

        PanelSection(title: localized("System")) {
            InfoList(tinted: [
                (localized("Thermal Throttling"), sensors.thermalDetail, thermalTint),
                ("Chip", hardware.chipName, .primary),
                (localized("Cores"), hardware.coresSummary, .primary),
                (localized("Unified Memory"), Formatting.bytes(hardware.totalMemoryBytes), .primary),
                (localized("Model"), hardware.modelIdentifier, .primary),
                (localized("Uptime"), sensors.formattedUptime, .primary)
            ])
        }
    }
}
