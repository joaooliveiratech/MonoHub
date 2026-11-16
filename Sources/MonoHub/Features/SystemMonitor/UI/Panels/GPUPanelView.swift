import SwiftUI

struct GPUPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let prefs = MonitorPreferences.shared
    private let hardware = HardwareInfo.shared

    var body: some View {
        let gpu = engine.gpuData
        let tint = ModuleType.gpu.tint
        let subtitle = hardware.gpuCoreCount.map { "\(hardware.chipName) · \(localized("%d cores", $0))" } ?? hardware.chipName

        PanelHeader(title: localized("Graphics"), subtitle: subtitle, symbol: "cube.transparent", tint: tint) {
            HeroValue(value: Formatting.percent(gpu.deviceUtilization), tint: UsageColor.forRatio(gpu.deviceUtilization, base: .primary))
        }

        Platter {
            HistoryChart(values: gpu.history.values, tint: tint)
        }

        HStack(spacing: 8) {
            StatTile(title: localized("Renderer"), value: Formatting.percent(gpu.rendererUtilization), tint: tint)
            StatTile(title: "Tiler", value: Formatting.percent(gpu.tilerUtilization), tint: .indigo)
        }

        InfoList([
            (localized("Memory in Use"), Formatting.bytes(gpu.inUseMemoryBytes)),
            (localized("Allocated Memory"), Formatting.bytes(gpu.allocatedMemoryBytes))
        ])

        TopProcessesSection(
            items: gpu.topProcesses,
            metric: .gpu,
            tint: tint,
            isEnabled: prefs.showTopProcessesGPU && prefs.topProcessesCount > 0
        )
    }
}
