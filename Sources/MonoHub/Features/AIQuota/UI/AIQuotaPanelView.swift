import SwiftUI

struct AIQuotaPanelView: View {
    private let quota = QuotaManager.shared
    private let prefs = QuotaPreferencesManager.shared

    enum TabSelection: Hashable {
        case all
        case provider(ProviderType)
    }

    @State private var selectedTab: TabSelection = .all

    private static let tabTransition: Animation = .spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(
                title: localized("AI Quotas"),
                subtitle: healthSummary,
                symbol: AIQuotaStyle.symbol,
                tint: AIQuotaStyle.tint
            ) {
                refreshButton
            }

            if activeProviders.count > 1 {
                providerPicker
            }

            content

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var activeProviders: [ProviderType] {
        prefs.enabledProviders.isEmpty ? [.claude] : prefs.enabledProviders
    }

    private var resolvedTab: TabSelection {
        if case .provider(let provider) = selectedTab, !activeProviders.contains(provider) {
            return .all
        }
        return activeProviders.count > 1 ? selectedTab : .provider(activeProviders[0])
    }

    @ViewBuilder
    private var content: some View {
        switch resolvedTab {
        case .all:
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(activeProviders) { provider in
                        ProviderQuotaCard(status: quota.status(for: provider), isCompact: true) {
                            withAnimation(Self.tabTransition) { selectedTab = .provider(provider) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)

        case .provider(let provider):
            ProviderQuotaCard(status: quota.status(for: provider), isCompact: false)
                .id(provider)
                .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await quota.refreshAll(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeating, isActive: quota.isRefreshing)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("r")
        .help(localized("Refresh now (⌘R)"))
        .accessibilityLabel(localized("Refresh"))
        .disabled(quota.isRefreshing)
    }

    private var providerPicker: some View {
        Picker(localized("Provider"), selection: Binding(
            get: { resolvedTab },
            set: { newValue in withAnimation(Self.tabTransition) { selectedTab = newValue } }
        )) {
            Text(localized("All")).tag(TabSelection.all)
            ForEach(activeProviders) { provider in
                Group {
                    if activeProviders.count > 4 {
                        Image(nsImage: provider.brandIcon)
                            .accessibilityLabel(provider.displayName)
                    } else {
                        Text(provider.displayName)
                    }
                }
                .tag(TabSelection.provider(provider))
            }
        }
        .pickerStyle(.tabs)
        .labelsHidden()
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            HStack {
                if let lastRefreshed = quota.lastRefreshed {
                    Text(localized("Updated %@", lastRefreshed.formatted(.relative(presentation: .named))))
                } else {
                    Text(localized("Not yet updated"))
                }
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            PanelActionRow(title: localized("Configure AI Quotas…"), symbol: "gearshape") {
                AIQuotaStatusItemController.shared.openSettings()
            }
            PanelActionRow(title: localized("Open MonoHub"), symbol: "square.grid.2x2") {
                AIQuotaStatusItemController.shared.closePanel(animated: true)
                MainWindowController.shared.show(item: .dashboard)
            }
        }
    }

    private var statuses: [ProviderStatus] {
        activeProviders.map { quota.status(for: $0) }
    }

    private var healthSummary: String {
        let errors = statuses.filter(\.state.isError).count
        if errors > 0 {
            return errors == 1 ? localized("1 provider needs attention") : localized("%d providers need attention", errors)
        }
        let high = statuses.filter { $0.peakUsagePercent >= prefs.warningThreshold }.count
        if high > 0 {
            return high == 1 ? localized("1 limit at high level") : localized("%d limits at high level", high)
        }
        return localized("All limits healthy")
    }
}
