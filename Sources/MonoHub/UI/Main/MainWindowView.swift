import SwiftUI

struct MainWindowView: View {
    @Bindable private var navigation = HubNavigation.shared
    @Bindable private var prefs = PreferencesManager.shared
    private let features = FeatureManager.shared

    init() {}

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $navigation.selectedItem)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail(for: navigation.selectedItem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigation.selectedItem.title)
        }
        .onChange(of: navigation.selectedItem, initial: true) { _, newItem in
            updateMonitoring(for: newItem)
        }
        .onChange(of: features.enabledFeatures) { _, _ in
            updateMonitoring(for: navigation.selectedItem)
        }
        .onDisappear {
            SystemMonitorEngine.shared.stopAllWindowMonitoring()
        }
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(prefs.resolvedColorScheme)
        .id(prefs.language.rawValue)
    }

    private func updateMonitoring(for item: SidebarItem) {
        let engine = SystemMonitorEngine.shared
        let monitorEnabled = features.isEnabled(.systemMonitor)
        engine.setDashboardMonitoring(active: monitorEnabled && item == .dashboard)
        let isMonitoringItem = item == .monitor || item == .battery || item == .ports
        let focused: ModuleType? = (item == .battery) ? .battery : ((item == .ports) ? .network : nil)
        engine.setWindowMonitoring(active: monitorEnabled && isMonitoringItem, focusedModule: focused)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        if let feature = item.feature, !features.isEnabled(feature) {
            FeatureDisabledView(feature: feature)
        } else {
            destinationView(for: item)
        }
    }

    @ViewBuilder
    private func destinationView(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(selectedSidebarItem: $navigation.selectedItem)
        case .modules:
            ModulesView()
        case .monitor:
            SystemMonitorView()
        case .ports:
            PortsView()
        case .battery:
            BatteryHealthView()
        case .displayControl:
            ExternalDisplayControlView()
        case .menuBar:
            MenuBarConfigView()
        case .aiQuota:
            AIQuotaView()
        case .notch:
            DynamicNotchView()
        case .windowSwitcher:
            WindowSwitcherView()
        case .windowTiling:
            WindowTilingView()
        case .screenshot:
            ScreenshotView()
        case .mediaConverter:
            MediaConverterView()
        case .urlRouter:
            URLRouterView()
        case .snippets:
            SnippetsView()
        case .bluetoothQuickConnect:
            BluetoothQuickConnectView()
        case .audioControl:
            AudioControlView()
        case .uninstaller:
            UninstallerView()
        case .orphans:
            OrphanedRemnantsView()
        case .cleaner:
            SystemCleanView()
        case .purge:
            ProjectPurgeView()
        case .env:
            DevEnvView()
        case .dupes:
            DuplicatesView()
        case .startup:
            StartupView()
        case .disk:
            DiskAnalyzerView()
        case .maintenance:
            MaintenanceView()
        case .history:
            OperationLogView()
        case .settings:
            SettingsView()
        }
    }
}
