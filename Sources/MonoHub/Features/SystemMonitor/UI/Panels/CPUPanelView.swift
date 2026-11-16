import SwiftUI

struct CPUPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let prefs = MonitorPreferences.shared
    private let hardware = HardwareInfo.shared

    var body: some View {
        let cpu = engine.cpuData
        let tint = ModuleType.cpu.tint

        PanelHeader(title: ModuleType.cpu.title, subtitle: hardware.chipName, symbol: "cpu", tint: tint) {
            HeroValue(value: Formatting.percent(cpu.totalUsage), tint: UsageColor.forRatio(cpu.totalUsage, base: .primary))
        }

        Platter {
            HistoryChart(values: cpu.history.values, tint: tint)
        }

        HStack(spacing: 8) {
            StatTile(title: localized("User"), value: Formatting.percent(cpu.userUsage), tint: tint)
            StatTile(title: localized("System"), value: Formatting.percent(cpu.systemUsage), tint: .red)
            StatTile(title: localized("Idle"), value: Formatting.percent(cpu.idleUsage), tint: .secondary)
        }

        PanelSection(title: localized("Cores")) {
            Text(localized("%d cores", hardware.logicalCores))
        } content: {
            Platter {
                VStack(alignment: .leading, spacing: 10) {
                    if hardware.efficiencyCores > 0 {
                        CoreClusterView(title: localized("Performance"), cluster: .performance, cpu: cpu, tint: tint)
                        CoreClusterView(title: localized("Efficiency"), cluster: .efficiency, cpu: cpu, tint: .mint)
                    } else {
                        CoreClusterView(title: localized("Cores"), cluster: .performance, cpu: cpu, tint: tint)
                    }
                }
            }
        }

        InfoList([
            (localized("Load average (1, 5, 15 min)"), "\(Formatting.decimal(cpu.loadAverage.one, digits: 2)) · \(Formatting.decimal(cpu.loadAverage.five, digits: 2)) · \(Formatting.decimal(cpu.loadAverage.fifteen, digits: 2))"),
            (localized("Processes"), cpu.processCount.map(Formatting.integer) ?? "—"),
            (localized("Threads"), cpu.threadCount.map(Formatting.integer) ?? "—"),
            (localized("Uptime"), Formatting.uptime(ProcessInfo.processInfo.systemUptime))
        ])

        TopProcessesSection(
            items: cpu.topProcesses,
            metric: .cpu,
            tint: tint,
            isEnabled: prefs.showTopProcessesCPU && prefs.topProcessesCount > 0
        )
    }
}

private struct CoreClusterView: View {
    let title: String
    let cluster: CoreCluster
    let cpu: CPUData
    let tint: Color

    var body: some View {
        let clusters = HardwareInfo.shared.coreClusters
        let usages = zip(cpu.coreUsages, clusters).filter { $0.1 == cluster }.map(\.0)
        let average = cpu.averageUsage(for: cluster, clusters: clusters)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatting.percent(average))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(UsageColor.forRatio(usage, base: tint).gradient)
                            .frame(height: max(26 * usage, 2))
                    }
                    .frame(height: 26)
                    .animation(.smooth(duration: 0.3), value: usage)
                }
            }
        }
    }
}
