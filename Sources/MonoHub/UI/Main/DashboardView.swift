import SwiftUI

struct DashboardView: View {
    @Binding var selectedSidebarItem: SidebarItem
    private let features = FeatureManager.shared
    @State private var volumeStats: VolumeStats?
    @State private var appsCount: Int?
    @State private var isRefreshing = false

    init(selectedSidebarItem: Binding<SidebarItem>) {
        self._selectedSidebarItem = selectedSidebarItem
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubMetrics.sectionSpacing) {
                HubPageHeader(
                    title: AppInfo.name,
                    subtitle: "\(HardwareInfo.shared.chipName) • \(HardwareInfo.shared.coresSummary) • \(localized("without telemetry"))",
                    systemImage: "square.grid.2x2.fill",
                    tint: .blue
                )

                if features.isEnabled(.systemMonitor) {
                    DashboardMetricsGrid(volumeStats: volumeStats, selectedSidebarItem: $selectedSidebarItem)
                } else if let volumeStats {
                    StorageOnlyCard(volumeStats: volumeStats) {
                        selectedSidebarItem = .disk
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(localized("Modules"))
                            .font(.headline)
                        Spacer()
                        Button(localized("Manage…")) {
                            selectedSidebarItem = .modules
                        }
                        .buttonStyle(.link)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: HubMetrics.itemSpacing)], spacing: HubMetrics.itemSpacing) {
                        ForEach(HubFeature.allCases) { feature in
                            FeatureSummaryCard(
                                feature: feature,
                                isEnabled: features.isEnabled(feature),
                                status: status(for: feature),
                                selectedSidebarItem: $selectedSidebarItem
                            )
                        }
                    }
                }
            }
            .padding(HubMetrics.pagePadding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                .help(localized("Refresh information"))
            }
        }
        .task {
            await refresh()
        }
    }

    private func status(for feature: HubFeature) -> String {
        guard features.isEnabled(feature) else { return localized("Disabled") }
        switch feature {
        case .systemMonitor:
            let prefs = MonitorPreferences.shared
            return prefs.isMenuBarEnabled
                ? localized("%d widgets in menu bar", prefs.orderedEnabledModules.count)
                : localized("Menu bar widgets hidden")
        case .dynamicNotch:
            return DisplayManager.shared.hasPhysicalNotch ? localized("Physical notch") : localized("Virtual notch")
        case .windowSwitcher:
            let prefs = SwitcherPreferencesManager.shared
            return "\(prefs.shortcut.shortName) • \(prefs.displayMode == .compact ? localized("Floating panel") : localized("Full screen"))"
        case .windowTiling:
            return TilePreferencesManager.shared.isSnapEnabled ? localized("Magnetic snapping and active shortcuts") : localized("Active shortcuts")
        case .screenshot:
            let prefs = ScreenshotPreferences.shared
            return "\(prefs.shortcut(for: .area).displayString) • \(localized("area capture"))"
        case .aiQuota:
            let prefs = QuotaPreferencesManager.shared
            let count = prefs.enabledProviders.count
            return count == 1 ? localized("1 provider monitored") : localized("%d providers monitored", count)
        case .cleanupTools:
            if let appsCount {
                return localized("%d apps installed", appsCount)
            }
            return localized("Ready to analyze")
        case .mediaConverter:
            return localized("Apple Silicon ARM64 Acceleration • Videos and Images")
        case .productivity:
            return localized("URL Router, Snippets & Quick Bluetooth")
        case .audioControl:
            let mic = AudioDeviceManager.shared.currentInputDevice?.name ?? localized("Microphone")
            return AudioDeviceManager.shared.isMicrophoneLocked
                ? "\(mic) (\(localized("Locked Default")))"
                : localized("Per-Application Volume Mixer")
        case .displayControl:
            let extCount = DisplayControlFeature.isActive ? ExternalDisplayManager.shared.activeExternalDisplays.count : 0
            return extCount == 1
                ? localized("1 external display connected")
                : localized("%d external displays connected", extCount)
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        volumeStats = DiskAnalyzerEngine.shared.getVolumeStats()
        guard features.isEnabled(.cleanupTools) else {
            appsCount = nil
            return
        }
        appsCount = await Task.detached(priority: .utility) {
            AppScanner.quickInstalledAppsCount()
        }.value
    }
}

private struct DashboardMetricsGrid: View {
    let volumeStats: VolumeStats?
    @Binding var selectedSidebarItem: SidebarItem
    @State private var availableWidth: CGFloat = 800

    var body: some View {
        let columnsCount = availableWidth < 360 ? 1 : (availableWidth < 680 ? 2 : 4)
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: HubMetrics.itemSpacing), count: columnsCount),
            spacing: HubMetrics.itemSpacing
        ) {
            CPUMetricCard { selectedSidebarItem = .monitor }
            MemoryMetricCard { selectedSidebarItem = .monitor }
            MetricCard(
                title: localized("Storage"),
                value: volumeStats.map { localized("%@ free", $0.formattedFree) } ?? "—",
                subtitle: volumeStats.map { localized("%@ used of %@", $0.formattedUsed, $0.formattedTotal) } ?? localized("Calculating…"),
                icon: "internaldrive",
                color: ModuleType.disk.tint,
                progress: volumeStats?.usedPercentage
            ) {
                selectedSidebarItem = .disk
            }
            PowerOrNetworkMetricCard { selectedSidebarItem = .monitor }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DashboardWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(DashboardWidthKey.self) { newWidth in
            if newWidth > 0 && abs(availableWidth - newWidth) > 1 {
                availableWidth = newWidth
            }
        }
    }
}

private struct DashboardWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 800
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct CPUMetricCard: View {
    let action: () -> Void

    var body: some View {
        let usage = SystemMonitorEngine.shared.cpuData.totalUsage
        MetricCard(
            title: localized("Processor"),
            value: Formatting.percent(usage),
            subtitle: HardwareInfo.shared.coresSummary,
            icon: "cpu",
            color: ModuleType.cpu.tint,
            progress: usage,
            action: action
        )
    }
}

private struct MemoryMetricCard: View {
    let action: () -> Void

    var body: some View {
        let ram = SystemMonitorEngine.shared.ramData
        MetricCard(
            title: localized("Memory"),
            value: Formatting.percent(ram.usedPercent),
            subtitle: "\(Formatting.bytes(ram.usedBytes)) \(localized("of %@", Formatting.bytes(ram.totalBytes)))",
            icon: "memorychip",
            color: ModuleType.ram.tint,
            progress: ram.usedPercent,
            action: action
        )
    }
}

private struct PowerOrNetworkMetricCard: View {
    let action: () -> Void

    var body: some View {
        let battery = SystemMonitorEngine.shared.batteryData
        if battery.hasBattery {
            MetricCard(
                title: localized("Battery"),
                value: "\(battery.levelPercent)%",
                subtitle: battery.systemPowerWatts.map { "\(battery.stateTitle) • \(Formatting.watts($0))" } ?? battery.stateTitle,
                icon: "battery.100percent.bolt",
                color: ModuleType.battery.tint,
                progress: battery.level,
                action: action
            )
        } else {
            let network = SystemMonitorEngine.shared.networkData
            MetricCard(
                title: localized("Network"),
                value: "↓ \(Formatting.speed(network.downloadBytesPerSec))",
                subtitle: "↑ \(Formatting.speed(network.uploadBytesPerSec))",
                icon: "network",
                color: ModuleType.network.tint,
                action: action
            )
        }
    }
}

private struct StorageOnlyCard: View {
    let volumeStats: VolumeStats
    let action: () -> Void

    var body: some View {
        MetricCard(
            title: localized("Storage"),
            value: localized("%@ free", volumeStats.formattedFree),
            subtitle: localized("%@ used of %@", volumeStats.formattedUsed, volumeStats.formattedTotal),
            icon: "internaldrive",
            color: .orange,
            progress: volumeStats.usedPercentage,
            action: action
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureSummaryCard: View {
    let feature: HubFeature
    let isEnabled: Bool
    let status: String
    @Binding var selectedSidebarItem: SidebarItem

    var body: some View {
        Button {
            if isEnabled {
                if let item = feature.sidebarItems.first {
                    selectedSidebarItem = item
                }
            } else {
                FeatureManager.shared.setEnabled(feature, true)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                HubIcon(systemName: feature.systemImage, tint: isEnabled ? tint : .gray, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Button(localized("Enable")) {
                        FeatureManager.shared.setEnabled(feature, true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hubCard(isInteractive: true)
    }

    private var tint: Color {
        feature.sidebarItems.first?.badgeColor ?? .accentColor
    }
}
