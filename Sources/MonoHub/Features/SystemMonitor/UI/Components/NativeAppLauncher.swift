import AppKit
import Foundation

@MainActor
enum NativeAppLauncher {
    private static let activityMonitor = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")

    static func openActivityMonitor() {
        guard !AppInfo.isRunningTests else { return }
        NSWorkspace.shared.openApplication(at: activityMonitor, configuration: .init(), completionHandler: nil)
    }

    static func openSystemTool(for module: ModuleType) {
        switch module {
        case .cpu, .ram, .gpu, .sensors:
            openActivityMonitor()
        case .disk:
            PermissionsManager.openSettingsPane("com.apple.settings.Storage")
        case .network:
            PermissionsManager.openSettingsPane("com.apple.Network-Settings.extension")
        case .battery:
            PermissionsManager.openSettingsPane("com.apple.Battery-Settings.extension")
        }
    }

    static func toolTitle(for module: ModuleType) -> String {
        switch module {
        case .cpu, .ram, .gpu, .sensors: return localized("Open Activity Monitor")
        case .disk: return localized("Storage Settings…")
        case .network: return localized("Network Settings…")
        case .battery: return localized("Battery Settings…")
        }
    }

    static func toolSymbol(for module: ModuleType) -> String {
        switch module {
        case .cpu, .ram, .gpu, .sensors: return "waveform.path.ecg.rectangle"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100percent"
        }
    }
}
