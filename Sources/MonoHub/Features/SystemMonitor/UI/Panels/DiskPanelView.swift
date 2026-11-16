import SwiftUI

struct DiskPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let prefs = MonitorPreferences.shared

    var body: some View {
        let disk = engine.diskData
        let tint = ModuleType.disk.tint
        let subtitle = [disk.fileSystem, Formatting.storage(disk.totalBytes)].compactMap { $0 }.joined(separator: " · ")

        PanelHeader(title: disk.volumeName, subtitle: subtitle, symbol: "internaldrive", tint: tint) {
            HeroValue(value: Formatting.percent(disk.usedPercent), tint: UsageColor.forRatio(disk.usedPercent, base: .primary))
        }

        Platter {
            VStack(alignment: .leading, spacing: 6) {
                UsageBar(ratio: disk.usedPercent, tint: UsageColor.forRatio(disk.usedPercent, base: tint), height: 8)
                HStack {
                    Text(localized("%@ used", Formatting.storage(disk.usedBytes)))
                    Spacer()
                    Text(localized("%@ free", Formatting.storage(disk.freeBytes)))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }

        HStack(spacing: 8) {
            StatTile(title: localized("Read"), value: Formatting.speed(disk.readBytesPerSec), tint: .blue)
            StatTile(title: localized("Write"), value: Formatting.speed(disk.writeBytesPerSec), tint: .red)
        }

        PanelSection(title: localized("Activity")) {
            HStack(spacing: 10) {
                ChartLegendItem(title: localized("Peak R"), value: Formatting.speed(UInt64(disk.readHistory.peak)), tint: .blue)
                ChartLegendItem(title: localized("W"), value: Formatting.speed(UInt64(disk.writeHistory.peak)), tint: .red)
            }
        } content: {
            Platter {
                HistoryChart(series: [
                    ChartSeries(values: disk.readHistory.values, tint: .blue),
                    ChartSeries(values: disk.writeHistory.values, tint: .red)
                ])
            }
        }

        InfoList([
            (localized("Available (including purgeable)"), disk.availableForImportantUsageBytes.map(Formatting.storage) ?? "—"),
            (localized("Read since startup"), Formatting.storage(disk.totalReadBytes)),
            (localized("Written since startup"), Formatting.storage(disk.totalWrittenBytes))
        ])

        if !disk.topProcesses.isEmpty {
            TopProcessesSection(
                items: disk.topProcesses,
                metric: .disk,
                tint: tint,
                isEnabled: prefs.showTopProcessesDisk && prefs.topProcessesCount > 0
            )
        }
    }
}
