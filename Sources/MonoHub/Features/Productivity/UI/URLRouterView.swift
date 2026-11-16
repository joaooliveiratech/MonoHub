import SwiftUI
import AppKit

struct URLRouterView: View {
    @Bindable private var router = URLRouterService.shared
    @State private var showingAddRuleSheet = false
    @State private var editingRule: URLRoutingRule?
    @State private var testURLInput = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=123456&utm_source=slack"

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                defaultBrowserBanner
                fallbackBrowserCard
                utmStripperCard
                meetingLinksCard
                rulesCard
                testSimulatorCard
            }
            .padding(20)
        }
        .sheet(isPresented: $showingAddRuleSheet) {
            RuleEditSheet(rule: nil) { newRule in
                router.addRule(newRule)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(rule: rule) { updatedRule in
                router.updateRule(updatedRule)
            }
        }
        .onAppear {
            router.refreshInstalledBrowsers()
        }
    }

    private var defaultBrowserBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(router.isDefaultBrowser ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 44, height: 44)

                Image(systemName: router.isDefaultBrowser ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(router.isDefaultBrowser ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(router.isDefaultBrowser ? localized("MonoHub is your Default Browser") : localized("MonoHub is not the Default Browser"))
                    .font(.headline)
                    .foregroundStyle(Color.primary)

                Text(router.isDefaultBrowser ?
                     localized("All app links are intercepted, cleaned, and routed according to your rules.") :
                     localized("To intercept link clicks, strip trackers, and route to browsers per app, set MonoHub as default."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !router.isDefaultBrowser {
                Button {
                    router.setAsDefaultBrowser()
                } label: {
                    Label(localized("Set as Default"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Button {
                    router.openSystemDefaultBrowserSettings()
                } label: {
                    Text(localized("System Settings"))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(router.isDefaultBrowser ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var fallbackBrowserCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("Fallback Default Browser"), systemImage: "globe")
                    .font(.headline)
                Spacer()
            }

            Text(localized("Used when no specific rule matches the link or source application."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: $router.defaultBrowserBundleID) {
                ForEach(router.installedBrowsers) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var utmStripperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Color.indigo)
                        Text(localized("Tracking Parameter Cleaner (UTM Stripper)"))
                            .font(.headline)
                    }

                    Text(localized("Automatically removes parameters like utm_source, fbclid, gclid, and YouTube si, protecting your privacy."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $router.stripTrackers)
                    .toggleStyle(.switch)
            }

            if router.stripTrackers {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Parameters stripped:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let tags = ["utm_source", "utm_medium", "utm_campaign", "fbclid", "gclid", "si (YouTube)", "twclid", "ttclid", "mc_cid", "ref"]
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.indigo.opacity(0.12)))
                                .foregroundStyle(Color.indigo)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var meetingLinksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.badge.waveform")
                            .foregroundStyle(Color.purple)
                        Text(localized("Direct Meeting and App Routing"))
                            .font(.headline)
                    }

                    Text(localized("Opens meeting links directly in installed native apps, bypassing intermediate browser tabs."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $router.routeMeetingLinks)
                    .toggleStyle(.switch)
            }

            if router.routeMeetingLinks {
                Divider()

                HStack(spacing: 12) {
                    appPill(name: "Zoom", scheme: "zoommtg://", icon: "video.fill")
                    appPill(name: "MS Teams", scheme: "msteams://", icon: "person.2.fill")
                    appPill(name: "Figma", scheme: "figma://", icon: "square.3.layers.3d")
                    appPill(name: "Notion", scheme: "notion://", icon: "doc.text.fill")
                    appPill(name: "Telegram", scheme: "tg://", icon: "paperplane.fill")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func appPill(name: String, scheme: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(name)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.purple.opacity(0.12)))
        .foregroundStyle(Color.purple)
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(Color.teal)
                        Text(localized("Rules by Source App and Domain"))
                            .font(.headline)
                    }

                    Text(localized("Define rules to open links in Helium when in Slack, or in Chrome for work domains."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingAddRuleSheet = true
                } label: {
                    Label(localized("Add Rule"), systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            if router.rules.isEmpty {
                Text(localized("No rules configured. Click 'Add Rule' to create the first one."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(router.rules) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func ruleRow(_ rule: URLRoutingRule) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in router.toggleRule(id: rule.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 6) {

                    if let appName = rule.sourceAppName ?? rule.sourceAppBundleID, !appName.isEmpty {
                        badgeView(text: "App: \(appName)", color: .blue)
                    } else {
                        badgeView(text: "Qualquer App", color: .gray)
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    badgeView(text: rule.domainPattern == "*" ? "Todos os links" : rule.domainPattern, color: .purple)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    badgeView(text: rule.targetBrowserName ?? rule.targetBrowserBundleID, color: .teal)
                }
            }

            Spacer()

            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                router.removeRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
        )
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    private var testSimulatorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(localized("Routing Simulator"), systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            Text(localized("Paste a link to see how it would be cleaned and which app or browser it would open in:"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("https://...", text: $testURLInput)
                .textFieldStyle(.roundedBorder)

            if let url = URL(string: testURLInput) {
                let cleaned = router.stripTrackers ? TrackingParameterCleaner.clean(url: url) : url
                let action = router.resolveRouting(for: url, sourceAppBundleID: "com.tinyspeck.slackmacgap")

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(localized("Cleaned URL:"))
                            .font(.caption.weight(.bold))
                        Text(cleaned.absoluteString)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }

                    HStack {
                        Text(localized("Destination if clicked in Slack:"))
                            .font(.caption.weight(.bold))

                        switch action {
                        case .nativeApp(let appURL):
                            Text("Abrir direto no App Nativo: \(appURL.scheme ?? "")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                        case .browser(let bundleID, _):
                            let browserName = router.installedBrowsers.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
                            Text("Abrir no Navegador: \(browserName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.teal)
                        case .unhandled(let fallback):
                            Text("Padrão: \(fallback.absoluteString)")
                                .font(.caption)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct RuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: URLRoutingRule?
    let onSave: (URLRoutingRule) -> Void

    @State private var name: String = ""
    @State private var sourceAppName: String = "Slack"
    @State private var sourceAppBundleID: String = "com.tinyspeck.slackmacgap"
    @State private var useSourceApp: Bool = true
    @State private var domainPattern: String = "*"
    @State private var targetBrowserBundleID: String = "net.imput.helium"

    private let router = URLRouterService.shared

    private let popularApps: [(name: String, bundleID: String)] = [
        ("Slack", "com.tinyspeck.slackmacgap"),
        ("Discord", "com.hnc.Discord"),
        ("Microsoft Teams", "com.microsoft.teams2"),
        ("Telegram", "ru.keepcoder.Telegram"),
        ("Mail (Apple)", "com.apple.mail"),
        ("Terminal", "com.apple.Terminal")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rule == nil ? localized("New Routing Rule") : localized("Edit Rule"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Rule Name:"))
                    .font(.caption.weight(.medium))
                TextField(localized("e.g. Slack opens in Helium"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(localized("Filter by Source Application"), isOn: $useSourceApp)
                    .font(.caption.weight(.medium))

                if useSourceApp {
                    Picker(localized("Source App:"), selection: $sourceAppBundleID) {
                        ForEach(popularApps, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sourceAppBundleID) { _, newID in
                        if let match = popularApps.first(where: { $0.bundleID == newID }) {
                            sourceAppName = match.name
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Domain Pattern:"))
                    .font(.caption.weight(.medium))
                TextField("* (todos) ou github.com, *.notion.so, meet.google.com", text: $domainPattern)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Target Browser:"))
                    .font(.caption.weight(.medium))
                Picker("", selection: $targetBrowserBundleID) {
                    ForEach(router.installedBrowsers) { b in
                        Text(b.name).tag(b.bundleID)
                    }
                }
                .pickerStyle(.menu)
            }

            Spacer()

            HStack {
                Button(localized("Cancel")) {
                    dismiss()
                }
                Spacer()
                Button(localized("Save")) {
                    let targetName = router.installedBrowsers.first(where: { $0.bundleID == targetBrowserBundleID })?.name
                    let newRule = URLRoutingRule(
                        id: rule?.id ?? UUID(),
                        name: name.isEmpty ? "Nova Regra" : name,
                        isEnabled: rule?.isEnabled ?? true,
                        sourceAppBundleID: useSourceApp ? sourceAppBundleID : nil,
                        sourceAppName: useSourceApp ? sourceAppName : nil,
                        domainPattern: domainPattern.isEmpty ? "*" : domainPattern,
                        targetBrowserBundleID: targetBrowserBundleID,
                        targetBrowserName: targetName
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
        .onAppear {
            if let r = rule {
                name = r.name
                useSourceApp = r.sourceAppBundleID != nil
                sourceAppBundleID = r.sourceAppBundleID ?? "com.tinyspeck.slackmacgap"
                sourceAppName = r.sourceAppName ?? "Slack"
                domainPattern = r.domainPattern
                targetBrowserBundleID = r.targetBrowserBundleID
            } else {
                if let helium = router.installedBrowsers.first(where: { $0.bundleID.contains("helium") }) {
                    targetBrowserBundleID = helium.bundleID
                } else if let first = router.installedBrowsers.first {
                    targetBrowserBundleID = first.bundleID
                }
            }
        }
    }
}
