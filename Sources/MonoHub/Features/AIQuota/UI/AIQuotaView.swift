import AppKit
import SwiftUI

enum AIQuotaSettingsSectionID: String, CaseIterable, Identifiable {
    case providers
    case menuBar
    case refresh
    case alerts
    case antigravity
    case apiKeys

    var id: String { rawValue }
}

struct AIQuotaView: View {
    @Bindable private var prefs = QuotaPreferencesManager.shared
    private let quota = QuotaManager.shared

    @State private var customClaudeToken = ""
    @State private var apiKeys: [ProviderType: String] = [:]
    @State private var didLoadSecrets = false
    @State private var alertsAllowed = true
    @State private var savedConfirmation = false
    @State private var isRescanning = false
    @State private var expandedSections: Set<AIQuotaSettingsSectionID> = []
    @State private var filterText = ""

    private static let keyedProviders: [ProviderType] = ProviderType.allCases.filter {
        $0.usesAPIKey || $0 == .codex || $0 == .copilot || $0 == .cursor
    }

    private var activeSectionIDs: [AIQuotaSettingsSectionID] {
        var ids: [AIQuotaSettingsSectionID] = [.providers, .menuBar, .refresh, .alerts]
        if prefs.isProviderEnabled(.antigravity) {
            ids.append(.antigravity)
        }
        ids.append(.apiKeys)
        return ids
    }

    private var allExpanded: Bool {
        activeSectionIDs.allSatisfy { expandedSections.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                overviewBanner

                if !prefs.enabledProviders.isEmpty {
                    livePreviewCard
                }

                HubAccordionSection(
                    title: localized("Providers"),
                    subtitle: localized("Drag to reorder, or use the context menu. List order is the left-to-right order in the menu bar. Only enabled providers are queried."),
                    badgeText: "\(prefs.enabledProviders.count)/\(prefs.providerOrder.count)",
                    badgeColor: .indigo,
                    systemImage: "sparkles",
                    tint: .indigo,
                    isExpanded: $expandedSections.contains(.providers)
                ) {
                    providersSection
                }

                HubAccordionSection(
                    title: localized("Menu Bar"),
                    subtitle: localized("Highlights in orange and red when usage exceeds warning threshold or provider fails."),
                    badgeText: prefs.showInMenuBar ? prefs.displayMode.title : localized("Disabled"),
                    badgeColor: prefs.showInMenuBar ? .blue : .secondary,
                    systemImage: "menubar.rectangle",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.menuBar)
                ) {
                    menuBarSection
                }

                HubAccordionSection(
                    title: localized("Refresh"),
                    subtitle: localized("Frequency of automatic background queries."),
                    badgeText: prefs.availableIntervals.first(where: { $0.seconds == prefs.refreshInterval })?.label ?? "",
                    badgeColor: .teal,
                    systemImage: "arrow.clockwise.circle.fill",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.refresh)
                ) {
                    refreshSection
                }

                HubAccordionSection(
                    title: localized("Alerts"),
                    subtitle: localized("Notifies when a model quota reaches warning level and when a limit is renewed."),
                    badgeText: prefs.notificationsEnabled ? "\(Int(prefs.warningThreshold))%" : localized("Disabled"),
                    badgeColor: prefs.notificationsEnabled ? thresholdColor(prefs.warningThreshold) : .secondary,
                    systemImage: "bell.badge.fill",
                    tint: .orange,
                    isExpanded: $expandedSections.contains(.alerts)
                ) {
                    alertsSection
                }

                if prefs.isProviderEnabled(.antigravity) {
                    HubAccordionSection(
                        title: localized("Antigravity"),
                        subtitle: localized("Queries in the background via CLI when IDE is closed."),
                        badgeText: prefs.antigravityCLIEnabled ? localized("Enabled") : localized("Disabled"),
                        badgeColor: prefs.antigravityCLIEnabled ? .green : .secondary,
                        systemImage: "terminal.fill",
                        tint: .purple,
                        isExpanded: $expandedSections.contains(.antigravity)
                    ) {
                        antigravitySection
                    }
                }

                HubAccordionSection(
                    title: localized("API Keys"),
                    subtitle: localized("Keys stay solely in the macOS login Keychain and are never written to disk or synced to the cloud."),
                    badgeText: localized("Keys by provider"),
                    badgeColor: .pink,
                    systemImage: "key.fill",
                    tint: .pink,
                    isExpanded: $expandedSections.contains(.apiKeys)
                ) {
                    apiKeysSection
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await quota.refreshAll(force: true) }
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(quota.isRefreshing)
                .help(localized("Query active providers now"))

                AccordionExpandToolbarButton(allExpanded: allExpanded) {
                    if allExpanded {
                        expandedSections.removeAll()
                    } else {
                        expandedSections = Set(activeSectionIDs)
                    }
                }
            }
        }
        .accordionFilter($filterText)
        .task {
            guard !didLoadSecrets else { return }
            didLoadSecrets = true
            customClaudeToken = await CredentialStore.shared.customClaudeToken()
            for provider in Self.keyedProviders {
                apiKeys[provider] = await CredentialStore.shared.apiKey(for: provider)
            }
            alertsAllowed = await NotificationService.shared.alertsAllowed()
        }
    }

    private var overviewBanner: some View {
        AccordionOverviewBanner(title: localized("AI Quotas"), systemImage: "chart.bar.doc.horizontal", tint: .indigo)
    }

    private var livePreviewCard: some View {
        HStack {
            Text(localized("Preview"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Image(nsImage: AIQuotaMenuBarRenderer.image(mode: prefs.displayMode, columns: AIQuotaMenuBarRenderer.currentColumns()))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prefs.providerOrder) { provider in
                ProviderToggleRow(provider: provider)
                    .reorderable(
                        scope: "aiquota-provider",
                        id: provider.id,
                        orderedIDs: prefs.providerOrder.map(\.id)
                    ) { moving, target in
                        guard let movingProvider = ProviderType.allCases.first(where: { $0.id == moving }),
                              let targetProvider = ProviderType.allCases.first(where: { $0.id == target }) else { return }
                        withAnimation(.snappy) {
                            prefs.moveProvider(movingProvider, onto: targetProvider)
                        }
                    }
            }
        }
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(title: localized("Show in menu bar"), isOn: $prefs.showInMenuBar)
            Divider()
            HStack {
                Text(localized("Style"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .disabled(!prefs.showInMenuBar)
            }
            Divider()
            HubToggleRow(
                title: localized("Alert colors"),
                subtitle: localized("Highlights in orange and red when usage exceeds warning threshold or provider fails."),
                isOn: $prefs.alertColors
            )
            .disabled(!prefs.showInMenuBar)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Refresh every"))
                        .font(.system(size: 12.5))
                    Text(localized("Frequency of automatic background queries."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $prefs.refreshInterval) {
                    ForEach(prefs.availableIntervals, id: \.seconds) { interval in
                        Text(interval.label).tag(interval.seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Divider()
            HStack {
                Text(localized("CLI Sessions"))
                    .font(.system(size: 12.5))
                Spacer()
                Button {
                    isRescanning = true
                    Task {
                        _ = await CredentialStore.shared.resyncClaude()
                        await QuotaManager.shared.refreshAll(force: true)
                        try? await Task.sleep(for: .seconds(0.6))
                        isRescanning = false
                    }
                } label: {
                    Text(isRescanning ? localized("Checking…") : localized("Rescan"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRescanning)
            }
            Text(localized("MonoHub reads sessions already opened by Claude Code, Codex, Kimi, and agy without renewing them. Queries use only account telemetry endpoints and never consume tokens. This is the only MonoHub module that accesses the network, and only for enabled providers."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Usage warnings"),
                subtitle: localized("Notifies when a model quota reaches warning level and when a limit is renewed."),
                isOn: Binding(
                    get: { prefs.notificationsEnabled },
                    set: { isOn in
                        prefs.notificationsEnabled = isOn
                        guard isOn else { return }
                        Task {
                            await NotificationService.shared.requestAuthorization()
                            alertsAllowed = await NotificationService.shared.alertsAllowed()
                        }
                    }
                )
            )

            if prefs.notificationsEnabled {
                Divider()
                HStack {
                    Text(localized("Warning threshold"))
                        .font(.system(size: 12.5))
                    Spacer()
                    HStack(spacing: 10) {
                        Slider(value: $prefs.warningThreshold, in: 50...95, step: 5)
                            .frame(width: 180)
                        StatusBadge("\(Int(prefs.warningThreshold))%", color: thresholdColor(prefs.warningThreshold))
                    }
                }
                if !alertsAllowed {
                    HStack {
                        Label(localized("Notifications disabled in macOS"), systemImage: "bell.slash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(localized("Open System Settings…")) {
                            PermissionsManager.openSettingsPane("com.apple.Notifications-Settings.extension")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var antigravitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubToggleRow(
                title: localized("Antigravity quota via agy"),
                subtitle: localized("Queries in the background via CLI when IDE is closed."),
                isOn: $prefs.antigravityCLIEnabled
            )
            Text(AntigravityUsageService.cliExecutable() == nil
                 ? localized("Install agy CLI to read Antigravity quota with IDE closed.")
                 : localized("With IDE closed, runs `agy -p /usage` every 90 s (0 tokens)."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.keyedProviders) { provider in
                HStack(spacing: 10) {
                    BrandTile(provider: provider, size: 22)
                    Text(provider.displayName)
                        .font(.system(size: 12.5))
                        .frame(width: 96, alignment: .leading)
                    SecureField(provider == .codex ? localized("Optional key") : "sk-…", text: Binding(
                        get: { apiKeys[provider] ?? "" },
                        set: { apiKeys[provider] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 10) {
                BrandTile(provider: .claude, size: 22)
                Text("Claude")
                    .font(.system(size: 12.5))
                    .frame(width: 96, alignment: .leading)
                SecureField(localized("sk-ant-oat01-… (1-year token)"), text: $customClaudeToken)
                    .textFieldStyle(.roundedBorder)
            }
            Divider()
            HStack {
                Text(localized("Run `claude setup-token` in Terminal to generate a 1-year token."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localized("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("claude setup-token", forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack {
                Spacer()
                Button(action: save) {
                    Label(savedConfirmation ? localized("Saved") : localized("Save Keys"), systemImage: savedConfirmation ? "checkmark" : "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(savedConfirmation ? .green : .accentColor)
                .disabled(savedConfirmation)
            }
        }
    }

    private func save() {
        let claudeToken = customClaudeToken
        let keys = apiKeys
        Task {
            await CredentialStore.shared.setCustomClaudeToken(claudeToken)
            for (provider, key) in keys {
                await CredentialStore.shared.setAPIKey(key, for: provider)
            }
            savedConfirmation = true
            await QuotaManager.shared.refreshAll(force: true)
            try? await Task.sleep(for: .seconds(1.5))
            savedConfirmation = false
        }
    }

    private func thresholdColor(_ value: Double) -> Color {
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return .green
    }
}

private struct ProviderToggleRow: View {
    let provider: ProviderType
    @Bindable private var prefs = QuotaPreferencesManager.shared

    var body: some View {
        let isEnabled = prefs.isProviderEnabled(provider)
        let isLastEnabled = isEnabled && prefs.enabledProviders.count == 1
        let status = QuotaManager.shared.status(for: provider)

        HStack(spacing: 10) {
            ReorderGrip()
            BrandTile(provider: provider, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(status.authSource)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isEnabled {
                StatusBadge(status.state.statusBadgeTitle, icon: status.state.statusSymbol, color: status.state.statusBadgeColor)
            }
            Toggle(localized("Monitor"), isOn: Binding(
                get: { isEnabled },
                set: { _ in prefs.toggleProvider(provider) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isLastEnabled)
            .help(isLastEnabled ? localized("At least one provider must remain active") : "")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(localized("Move Up")) { prefs.moveProviderUp(provider) }
            Button(localized("Move Down")) { prefs.moveProviderDown(provider) }
        }
    }
}
