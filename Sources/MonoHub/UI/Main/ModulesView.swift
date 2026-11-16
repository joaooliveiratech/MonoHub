import SwiftUI

struct ModulesView: View {
    private let features = FeatureManager.shared
    @State private var filterText = ""

    private var visibleFeatures: [HubFeature] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return HubFeature.allCases.map { $0 } }
        return HubFeature.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(visibleFeatures) { feature in
                    FeatureToggleRow(feature: feature, isOn: binding(for: feature))
                }
            } header: {
                Text(localized("Modules"))
            } footer: {
                Text(localized("Disabled modules are completely shut down: timers, observers, global shortcuts, and menu bar icons cease to exist until you enable them again."))
            }

            Section(localized("Current Usage")) {
                LabeledContent(localized("Active modules")) {
                    Text(localized("%d of %d", features.enabledFeatures.count, HubFeature.allCases.count))
                        .monospacedDigit()
                }
                LabeledContent(localized("In background")) {
                    Text(backgroundSummary)
                }
            }
        }
        .formStyle(.grouped)
        .searchable(text: $filterText, placement: .toolbar, prompt: localized("Filter options…"))
    }

    private var backgroundSummary: String {
        let running = HubFeature.allCases.filter { $0.runsInBackground && features.isEnabled($0) }
        guard !running.isEmpty else { return localized("None") }
        return running.map(\.title).joined(separator: ", ")
    }

    private func binding(for feature: HubFeature) -> Binding<Bool> {
        Binding(
            get: { features.isEnabled(feature) },
            set: { features.setEnabled(feature, $0) }
        )
    }
}

private struct FeatureToggleRow: View {
    let feature: HubFeature
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 10) {
                HubIcon(systemName: feature.systemImage, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                    Text(feature.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(feature.resourceNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.switch)
    }

    private var tint: Color {
        feature.sidebarItems.first?.badgeColor ?? .accentColor
    }
}
