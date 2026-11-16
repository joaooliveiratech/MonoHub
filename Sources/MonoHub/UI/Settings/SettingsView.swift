import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general
        case cleanup
        case privacy
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return localized("General")
            case .cleanup: return localized("Cleanup")
            case .privacy: return localized("Privacy")
            case .about: return localized("About")
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .cleanup: return "sparkles"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .general: GeneralSettingsForm()
        case .cleanup: CleanupSettingsView()
        case .privacy: PrivacySettingsForm()
        case .about: AboutSettingsForm()
        }
    }
}

private enum GeneralSectionID: String, CaseIterable, Identifiable {
    case appearance, language, startup, modules
    var id: String { rawValue }
}

private struct GeneralSettingsForm: View {
    @Bindable private var prefs = PreferencesManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginRequiresApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var expandedSections: Set<GeneralSectionID> = Set(GeneralSectionID.allCases)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HubAccordionSection(
                    title: localized("Appearance"),
                    subtitle: localized("Switch between dark, light mode or follow macOS settings automatically."),
                    badgeText: localized("Theme"),
                    badgeColor: .purple,
                    systemImage: "paintbrush.pointed.fill",
                    tint: .purple,
                    isExpanded: $expandedSections.contains(.appearance)
                ) {
                    HStack {
                        Text(localized("Theme"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Picker(localized("Theme"), selection: $prefs.appTheme) {
                            Label(localized("System"), systemImage: "circle.lefthalf.filled").tag(AppTheme.system)
                            Label(localized("Light", context: "theme"), systemImage: "sun.max.fill").tag(AppTheme.light)
                            Label(localized("Dark", context: "theme"), systemImage: "moon.fill").tag(AppTheme.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 280)
                    }
                }

                HubAccordionSection(
                    title: localized("Language"),
                    subtitle: localized("Changes the language of the menu bar, panels and settings."),
                    badgeText: prefs.language.displayName,
                    badgeColor: .blue,
                    systemImage: "globe",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.language)
                ) {
                    HStack {
                        Text(localized("Language"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Picker(localized("Language"), selection: $prefs.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }

                HubAccordionSection(
                    title: localized("Startup"),
                    subtitle: localized("When enabled, closing the window or using ⌘Q keeps modules active in the menu bar. To truly quit, use ⌥⌘Q."),
                    badgeText: launchAtLogin ? localized("Enabled") : localized("Startup"),
                    badgeColor: .teal,
                    systemImage: "power.circle.fill",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.startup)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HubToggleRow(title: localized("Open at login"), isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                prefs.launchAtLogin = enabled
                                refreshLaunchAtLogin()
                            }
                        if launchAtLoginRequiresApproval {
                            HStack {
                                Text(localized("Pending approval"))
                                    .font(.system(size: 12.5))
                                Spacer()
                                Button(localized("Open Login Items…")) {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        Divider()
                        HubToggleRow(title: localized("Keep running in background when closed"), isOn: $prefs.keepRunningInBackgroundOnQuit)
                    }
                }

                HubAccordionSection(
                    title: localized("Modules"),
                    subtitle: localized("Disable modules you don't use so they don't consume CPU, memory, or battery."),
                    badgeText: localized("%d of %d", FeatureManager.shared.enabledFeatures.count, HubFeature.allCases.count),
                    badgeColor: .indigo,
                    systemImage: "square.grid.2x2.fill",
                    tint: .indigo,
                    isExpanded: $expandedSections.contains(.modules)
                ) {
                    HStack {
                        Text(localized("Active modules"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Text(localized("%d of %d", FeatureManager.shared.enabledFeatures.count, HubFeature.allCases.count))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button(localized("Manage Modules…")) {
                            HubNavigation.shared.select(.modules)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(20)
        }
        .onAppear(perform: refreshLaunchAtLogin)
    }

    private func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }
}

private enum PrivacySectionID: String, CaseIterable, Identifiable {
    case privacy, permissions, audit
    var id: String { rawValue }
}

private struct PrivacySettingsForm: View {
    private let permissions = PermissionsManager.shared
    @State private var showPermissionGuide = false
    @State private var expandedSections: Set<PrivacySectionID> = Set(PrivacySectionID.allCases)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HubAccordionSection(
                    title: localized("Privacy"),
                    subtitle: localized("With AI Quotas disabled, MonoHub makes no network connections. When enabled, it only queries the usage endpoints of enabled providers, without sending prompts or consuming tokens."),
                    badgeText: localized("Privacy"),
                    badgeColor: .green,
                    systemImage: "hand.raised.fill",
                    tint: .green,
                    isExpanded: $expandedSections.contains(.privacy)
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(localized("Zero telemetry, analytics, or remote reporting"), systemImage: "eye.slash")
                            .font(.system(size: 12.5))
                        Label(localized("Network access strictly limited to AI Quotas module"), systemImage: "network")
                            .font(.system(size: 12.5))
                        Label(localized("Keys and tokens stored exclusively in Keychain"), systemImage: "key.fill")
                            .font(.system(size: 12.5))
                    }
                }

                HubAccordionSection(
                    title: localized("Permissions"),
                    subtitle: localized("Required to safely analyze and remove remnants in ~/Library/Containers."),
                    badgeText: (permissions.hasAccessibility && permissions.hasScreenRecording && permissions.hasFullDiskAccess) ? localized("Granted") : localized("Not granted"),
                    badgeColor: (permissions.hasAccessibility && permissions.hasScreenRecording && permissions.hasFullDiskAccess) ? .green : .orange,
                    systemImage: "lock.open.display",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.permissions)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(localized("Accessibility"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            if permissions.hasAccessibility {
                                StatusBadge(localized("Granted"), icon: "checkmark.circle.fill", color: .green)
                            } else {
                                StatusBadge(localized("Not granted"), icon: "exclamationmark.triangle.fill", color: .orange)
                            }
                            Button(localized("Open System Settings…")) {
                                permissions.openSettings(for: .accessibility)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Divider()
                        HStack {
                            Text(localized("Screen Recording"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            if permissions.hasScreenRecording {
                                StatusBadge(localized("Granted"), icon: "checkmark.circle.fill", color: .green)
                            } else {
                                StatusBadge(localized("Not granted"), icon: "exclamationmark.triangle.fill", color: .orange)
                            }
                            Button(localized("Open System Settings…")) {
                                permissions.openSettings(for: .screenRecording)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Divider()
                        HStack {
                            Text(localized("Full Disk Access"))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            if permissions.hasFullDiskAccess {
                                StatusBadge(localized("Granted"), icon: "checkmark.circle.fill", color: .green)
                            } else {
                                StatusBadge(localized("Not granted"), icon: "exclamationmark.triangle.fill", color: .orange)
                            }
                        }
                        HStack {
                            Button(permissions.hasFullDiskAccess ? localized("Open System Settings…") : localized("How to Grant…")) {
                                permissions.openFullDiskAccessSettingsAndRevealApp()
                                showPermissionGuide = !permissions.hasFullDiskAccess
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if !permissions.hasFullDiskAccess {
                                Button(localized("Copy App Path")) {
                                    permissions.copyAppPathToClipboard()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                HubAccordionSection(
                    title: localized("Audit"),
                    subtitle: "~/Library/Logs/MonoHub/operations.log",
                    badgeText: localized("Log file"),
                    badgeColor: .teal,
                    systemImage: "doc.text.magnifyingglass",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.audit)
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Log file"))
                                .font(.system(size: 12.5))
                            Text("~/Library/Logs/MonoHub/operations.log")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button(localized("Reveal in Finder")) {
                            let logURL = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Library/Logs/MonoHub/operations.log")
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showPermissionGuide) {
            FullDiskAccessGuideModal()
        }
    }
}

private struct AboutSettingsForm: View {
    private let hardware = HardwareInfo.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppIconView(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.appName)
                            .font(.title2.weight(.semibold))
                        Text(localized("Version %@", AppInfo.fullVersionString))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("macOS 27 • Apple Silicon")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(localized("This Mac")) {
                LabeledContent(localized("Chip"), value: hardware.chipName)
                LabeledContent(localized("Cores"), value: hardware.coresSummary)
                if let gpuCores = hardware.gpuCoreCount {
                    LabeledContent(localized("GPU"), value: localized("%d cores", gpuCores))
                }
                LabeledContent(localized("Memory"), value: Formatting.bytes(hardware.totalMemoryBytes))
                LabeledContent(localized("Model"), value: hardware.modelIdentifier)
            }

            Section {
                if let url = URL(string: AppInfo.githubUrl) {
                    Link(localized("Source code on GitHub"), destination: url)
                }
                Button(localized("Quit %@", AppInfo.appName), role: .destructive) {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.forceTerminate()
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            } footer: {
                Text(AppInfo.copyright)
            }
        }
        .formStyle(.grouped)
    }
}
