import AppKit
import SwiftUI

extension ModuleType {
    var tint: Color {
        switch self {
        case .cpu: return .blue
        case .ram: return .purple
        case .gpu: return .teal
        case .disk: return .orange
        case .network: return .cyan
        case .battery: return .green
        case .sensors: return .red
        }
    }
}

extension UsageColor {
    static func forPressure(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    static func forThermal(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .green
        }
    }

    static func forBatteryTemperature(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        if celsius >= 45 { return .red }
        if celsius >= 38 { return .orange }
        return .primary
    }

    static func forTemperature(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        if celsius >= 90 { return .red }
        if celsius >= 75 { return .orange }
        if celsius >= 60 { return .yellow }
        return .green
    }
}

struct PanelFooter: View {
    let module: ModuleType

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            PanelActionRow(title: NativeAppLauncher.toolTitle(for: module), symbol: NativeAppLauncher.toolSymbol(for: module)) {
                StatusItemController.shared.closePanel(animated: true)
                NativeAppLauncher.openSystemTool(for: module)
            }
            PanelActionRow(title: localized("Open MonoHub"), symbol: "square.grid.2x2") {
                StatusItemController.shared.openMainWindow()
            }
            PanelActionRow(title: localized("MonoHub Settings…"), symbol: "menubar.rectangle") {
                StatusItemController.shared.openSettings()
            }
        }
    }
}

struct PanelRootView: View {
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
            PanelFooter(module: module)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}
