import SwiftUI

struct RAMPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let prefs = MonitorPreferences.shared

    var body: some View {
        let ram = engine.ramData
        let tint = ModuleType.ram.tint
        let segments = [
            BarSegment(id: "app", title: localized("Apps"), value: Double(ram.appBytes), tint: tint, detail: Formatting.bytes(ram.appBytes)),
            BarSegment(id: "wired", title: localized("Wired"), value: Double(ram.wiredBytes), tint: .orange, detail: Formatting.bytes(ram.wiredBytes)),
            BarSegment(id: "compressed", title: localized("Compressed"), value: Double(ram.compressedBytes), tint: .pink, detail: Formatting.bytes(ram.compressedBytes)),
            BarSegment(id: "cached", title: localized("Cached Files"), value: Double(ram.cachedBytes), tint: .gray, detail: Formatting.bytes(ram.cachedBytes)),
            BarSegment(id: "free", title: localized("Free"), value: Double(ram.freeBytes), tint: Color.primary.opacity(0.12), detail: Formatting.bytes(ram.freeBytes))
        ]

        PanelHeader(
            title: localized("Memory"),
            subtitle: localized("%@ of %@ in use", Formatting.bytes(ram.usedBytes), Formatting.bytes(ram.totalBytes)),
            symbol: "memorychip",
            tint: tint
        ) {
            HeroValue(value: Formatting.percent(ram.usedPercent), tint: UsageColor.forRatio(ram.usedPercent, base: .primary))
        }

        Platter {
            HistoryChart(values: ram.history.values, tint: tint)
        }

        HStack(spacing: 8) {
            StatTile(
                title: localized("Pressure"),
                value: ram.pressureLevel.title,
                detail: Formatting.percent(ram.pressure),
                tint: UsageColor.forPressure(ram.pressureLevel)
            )
            StatTile(
                title: "Swap",
                value: Formatting.bytes(ram.swapUsedBytes),
                detail: ram.swapTotalBytes > 0 ? localized("of %@", Formatting.bytes(ram.swapTotalBytes)) : localized("not used"),
                tint: ram.swapUsedBytes > 0 ? .orange : .secondary
            )
        }

        PanelSection(title: localized("Composition")) {
            Platter {
                VStack(alignment: .leading, spacing: 10) {
                    SegmentedBar(segments: segments)
                    SegmentLegend(segments: segments)
                }
            }
        }

        TopProcessesSection(
            items: ram.topProcesses,
            metric: .memory,
            tint: tint,
            isEnabled: prefs.showTopProcessesRAM && prefs.topProcessesCount > 0
        )
    }
}
