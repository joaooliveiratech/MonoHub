import SwiftUI

struct SystemMonitorView: View {
    @State private var selectedModule: ModuleType?
    @State private var processMetric: ProcessMetric = .cpu
    private let engine = SystemMonitorEngine.shared

    init() {}

    var body: some View {
        ScrollView {
            Group {
                if let module = selectedModule {
                    ModuleDetailView(module: module)
                } else {
                    overview
                }
            }
            .padding(HubMetrics.pagePadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .toolbar {
            if let module = selectedModule {
                ToolbarItem(placement: .navigation) {
                    Button {
                        select(nil)
                    } label: {
                        Label(localized("Overview"), systemImage: "chevron.backward")
                    }
                    .help(localized("Back to overview"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NativeAppLauncher.openSystemTool(for: module)
                    } label: {
                        Label(NativeAppLauncher.toolTitle(for: module), systemImage: NativeAppLauncher.toolSymbol(for: module))
                    }
                    .help(NativeAppLauncher.toolTitle(for: module))
                }
            }
        }
        .onAppear {
            engine.setWindowProcessRanking(processMetric.rankings)
            engine.setWindowMonitoring(active: true, focusedModule: selectedModule)
        }
        .onChange(of: processMetric) { _, metric in
            engine.setWindowProcessRanking(metric.rankings)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: HubMetrics.sectionSpacing) {
            HardwareSummaryCard()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: HubMetrics.itemSpacing)],
                spacing: HubMetrics.itemSpacing
            ) {
                ForEach(ModuleType.allCases) { module in
                    Button {
                        select(module)
                    } label: {
                        ModuleOverviewCard(module: module)
                    }
                    .buttonStyle(.plain)
                    .help(String(format: localized("Show details for %@"), module.title))
                }
            }

            TopProcessesCard(metric: $processMetric)
        }
    }

    private func select(_ module: ModuleType?) {
        selectedModule = module
        engine.setWindowMonitoring(active: true, focusedModule: module)
    }
}

private extension ProcessMetric {
    var rankings: ProcessRankings {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .gpu: return .gpu
        case .energy: return .energy
        case .disk: return .disk
        }
    }
}

private struct HardwareSummaryCard: View {
    private let hardware = HardwareInfo.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubIcon(systemName: "desktopcomputer", tint: .gray, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(hardware.chipName)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            ThermalBadge()
        }
        .hubCard()
    }

    private var summary: String {
        var parts = [hardware.coresSummary]
        if let gpuCores = hardware.gpuCoreCount {
            parts.append(String(format: localized("%d GPU cores"), gpuCores))
        }
        parts.append(String(format: localized("%@ memory"), Formatting.bytes(hardware.totalMemoryBytes)))
        parts.append(hardware.modelIdentifier)
        return parts.joined(separator: " · ")
    }
}

private struct ThermalBadge: View {
    private let engine = SystemMonitorEngine.shared

    var body: some View {
        let sensors = engine.sensorsData
        StatusBadge(
            String(format: localized("Thermal: %@"), sensors.thermalDescription),
            icon: "thermometer.medium",
            color: UsageColor.forThermal(sensors.thermalState)
        )
    }
}

private struct ModuleOverviewCard: View {
    let module: ModuleType
    private let engine = SystemMonitorEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HubIcon(systemName: module.sfSymbol, tint: module.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(content.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(content.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(content.valueTint)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            chart
                .frame(height: 46)

            if let top = topConsumer {
                HStack(spacing: 6) {
                    Image(nsImage: AppIconCache.shared.icon(for: top.item.bundlePath))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                    Text(top.item.name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(top.value)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .hubCard(isInteractive: true)
        .accessibilityElement(children: .combine)
    }

    private var topConsumer: (item: ProcessItem, value: String)? {
        switch module {
        case .cpu:
            guard let first = engine.cpuData.topProcesses.first, first.cpuPercent >= 0.1 else { return nil }
            return (first, first.formattedCPU)
        case .ram:
            guard let first = engine.ramData.topProcesses.first, first.residentMemoryBytes > 0 else { return nil }
            return (first, first.formattedMemory)
        case .gpu:
            guard let first = engine.gpuData.topProcesses.first, first.gpuPercent >= 0.1 else { return nil }
            return (first, first.formattedGPU)
        case .disk:
            guard let first = engine.diskData.topProcesses.first, first.diskBytesPerSec > 0 else { return nil }
            return (first, first.formattedDiskSpeed)
        case .battery:
            guard let first = engine.batteryData.topProcesses.first else { return nil }
            return (first, first.formattedPower)
        case .network, .sensors:
            return nil
        }
    }

    private var content: (value: String, detail: String, valueTint: Color) {
        switch module {
        case .cpu:
            let cpu = engine.cpuData
            return (
                Formatting.percent(cpu.totalUsage),
                String(format: localized("%@ user · %@ system"), Formatting.percent(cpu.userUsage), Formatting.percent(cpu.systemUsage)),
                UsageColor.forRatio(cpu.totalUsage, base: .primary)
            )
        case .ram:
            let ram = engine.ramData
            return (
                Formatting.percent(ram.usedPercent),
                String(format: localized("%@ of %@ · pressure %@"), Formatting.bytes(ram.usedBytes), Formatting.bytes(ram.totalBytes), ram.pressureLevel.title.lowercased()),
                UsageColor.forRatio(ram.usedPercent, base: .primary)
            )
        case .gpu:
            let gpu = engine.gpuData
            return (
                Formatting.percent(gpu.deviceUtilization),
                String(format: localized("%@ memory in use"), Formatting.bytes(gpu.inUseMemoryBytes)),
                UsageColor.forRatio(gpu.deviceUtilization, base: .primary)
            )
        case .disk:
            let disk = engine.diskData
            return (
                Formatting.percent(disk.usedPercent),
                String(format: localized("%@ free · R %@ · W %@"), Formatting.storage(disk.freeBytes), Formatting.speed(disk.readBytesPerSec), Formatting.speed(disk.writeBytesPerSec)),
                UsageColor.forRatio(disk.usedPercent, base: .primary)
            )
        case .network:
            let net = engine.networkData
            let interface = net.isConnected ? (net.interfaceName ?? localized("Connected")) : localized("No connection")
            return (
                "↓ \(Formatting.speed(net.downloadBytesPerSec))",
                "↑ \(Formatting.speed(net.uploadBytesPerSec)) · \(interface)",
                .primary
            )
        case .battery:
            let battery = engine.batteryData
            guard battery.hasBattery else {
                return ("—", battery.stateTitle, .secondary)
            }
            let power = battery.systemPowerWatts.map { " · \(Formatting.watts($0))" } ?? ""
            return (
                "\(battery.levelPercent)%",
                "\(battery.stateTitle)\(power)",
                battery.level <= 0.2 && !battery.isConnectedToPower ? .red : .primary
            )
        case .sensors:
            let sensors = engine.sensorsData
            return (
                sensors.formattedTemperature,
                String(format: localized("Max %@ · %@"), Formatting.temperature(sensors.socTemperatureMax), sensors.thermalDescription),
                UsageColor.forTemperature(sensors.socTemperature)
            )
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch module {
        case .cpu:
            HistoryChart(values: engine.cpuData.history.values, tint: module.tint, height: 46)
        case .ram:
            HistoryChart(values: engine.ramData.history.values, tint: module.tint, height: 46)
        case .gpu:
            HistoryChart(values: engine.gpuData.history.values, tint: module.tint, height: 46)
        case .disk:
            HistoryChart(series: [
                ChartSeries(values: engine.diskData.readHistory.values, tint: .blue),
                ChartSeries(values: engine.diskData.writeHistory.values, tint: .red)
            ], height: 46)
        case .network:
            HistoryChart(series: [
                ChartSeries(values: engine.networkData.downloadHistory.values, tint: .blue),
                ChartSeries(values: engine.networkData.uploadHistory.values, tint: .orange)
            ], height: 46)
        case .battery:
            let battery = engine.batteryData
            if battery.hasBattery {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(max(battery.level, 0), 1))
                        .tint(battery.isCharging ? .green : module.tint)
                    Text(battery.stateDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                Label(localized("This Mac uses continuous external power"), systemImage: "powerplug.portrait")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        case .sensors:
            HistoryChart(values: engine.sensorsData.history.values, tint: module.tint, fixedMaximum: 110, height: 46)
        }
    }
}

private struct TopProcessesCard: View {
    @Binding var metric: ProcessMetric
    private let engine = SystemMonitorEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HubIcon(systemName: "list.bullet.rectangle", tint: .indigo)
                Text(localized("Top Usage Processes"))
                    .font(.headline)
                Spacer(minLength: 8)
                Picker(localized("Sort by"), selection: $metric) {
                    Text(localized("CPU")).tag(ProcessMetric.cpu)
                    Text(localized("Memory")).tag(ProcessMetric.memory)
                    Text(localized("GPU")).tag(ProcessMetric.gpu)
                    Text(localized("Energy")).tag(ProcessMetric.energy)
                    Text(localized("Disk")).tag(ProcessMetric.disk)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            let items = processes
            if items.isEmpty {
                HStack(spacing: 8) {
                    if metric != .gpu && metric != .disk {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(emptyStateText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ProcessListView(items: items, metric: metric, tint: tint)
            }
        }
        .hubCard()
    }

    private var emptyStateText: String {
        switch metric {
        case .gpu: return localized("No process using GPU at the moment")
        case .disk: return localized("No active disk I/O at the moment")
        default: return localized("Collecting processes…")
        }
    }

    private var processes: [ProcessItem] {
        switch metric {
        case .cpu: return engine.cpuData.topProcesses
        case .memory: return engine.ramData.topProcesses
        case .gpu: return engine.gpuData.topProcesses
        case .energy: return engine.batteryData.topProcesses
        case .disk: return engine.diskData.topProcesses
        }
    }

    private var tint: Color {
        switch metric {
        case .cpu: return ModuleType.cpu.tint
        case .memory: return ModuleType.ram.tint
        case .gpu: return ModuleType.gpu.tint
        case .energy: return .orange
        case .disk: return ModuleType.disk.tint
        }
    }
}

private struct ModuleDetailView: View {
    let module: ModuleType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch module {
            case .cpu: CPUPanelView()
            case .ram: RAMPanelView()
            case .gpu: GPUPanelView()
            case .disk: DiskPanelView()
            case .network: NetworkPanelView()
            case .battery: BatteryPanelView()
            case .sensors: SensorsPanelView()
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .hubCard(padding: 18)
        .frame(maxWidth: .infinity)
    }
}
