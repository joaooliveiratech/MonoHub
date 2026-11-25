import AppKit
import SwiftUI

enum MenuBarSettingsSectionID: String, CaseIterable, Identifiable {
    case general
    case dataCollection
    case modules
    case appearance
    case processes

    var id: String { rawValue }
}

struct MenuBarConfigView: View {
    @Bindable private var prefs = MonitorPreferences.shared
    @State private var launchAtLogin = PreferencesManager.shared.launchAtLogin
    @State private var expandedSections: Set<MenuBarSettingsSectionID> = []
    @State private var filterText = ""

    private static let refreshIntervals: [TimeInterval] = [1, 2, 3, 5]
    private static let presetStyles: [DisplayStyle] = [.combined, .stacked, .icon, .symbolStacked, .bar, .text]

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                overviewBanner

                if prefs.isMenuBarEnabled && !prefs.orderedEnabledModules.isEmpty {
                    livePreviewCard
                }

                HubAccordionSection(
                    title: localized("General"),
                    subtitle: localized("Disable to keep only the main panel; sampling stops when nothing is visible."),
                    badgeText: prefs.isMenuBarEnabled ? localized("Enabled") : localized("Disabled"),
                    badgeColor: prefs.isMenuBarEnabled ? .green : .secondary,
                    systemImage: "menubar.rectangle",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.general)
                ) {
                    generalSection
                }

                HubAccordionSection(
                    title: localized("Data Collection"),
                    subtitle: localized("Readings come straight from the kernel, in the background at low priority. Sampling also pauses while the menu bar is hidden."),
                    badgeText: "\(Int(prefs.refreshInterval))s",
                    badgeColor: .teal,
                    systemImage: "waveform.path.ecg",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.dataCollection)
                ) {
                    dataCollectionSection
                }

                HubAccordionSection(
                    title: localized("Modules"),
                    subtitle: localized("Drag to reorder. The list order matches the left-to-right order in the menu bar."),
                    badgeText: "\(prefs.orderedEnabledModules.count)/\(prefs.moduleOrder.count)",
                    badgeColor: .indigo,
                    systemImage: "square.grid.2x2.fill",
                    tint: .indigo,
                    isExpanded: $expandedSections.contains(.modules)
                ) {
                    modulesSection
                }

                HubAccordionSection(
                    title: localized("Appearance"),
                    subtitle: localized("Highlights in orange and red when usage gets high."),
                    badgeText: prefs.useDynamicColors ? localized("Alert colors") : localized("Appearance"),
                    badgeColor: .purple,
                    systemImage: "paintbrush.pointed.fill",
                    tint: .purple,
                    isExpanded: $expandedSections.contains(.appearance)
                ) {
                    appearanceSection
                }

                HubAccordionSection(
                    title: localized("Panels"),
                    subtitle: localized("The process list is only sampled while its panel is open."),
                    badgeText: prefs.topProcessesCount == 0 ? localized("None") : "\(prefs.topProcessesCount)",
                    badgeColor: .orange,
                    systemImage: "list.number",
                    tint: .orange,
                    isExpanded: $expandedSections.contains(.processes)
                ) {
                    processesSection
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                AccordionExpandToolbarButton(expandedSections: $expandedSections)
            }
        }
        .accordionFilter($filterText)
        .id(PreferencesManager.shared.language)
    }

    private var overviewBanner: some View {
        AccordionOverviewBanner(title: localized("Menu Bar"), systemImage: "menubar.rectangle", tint: .blue)
    }

    private var livePreviewCard: some View {
        HStack {
            Label(localized("Preview"), systemImage: "menubar.rectangle")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(prefs.orderedEnabledModules) { module in
                    MenuBarPreview(module: module, style: prefs.displayStyle(for: module))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hubCard(padding: 0)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Show widgets in menu bar"),
                subtitle: localized("Disable to keep only the main panel; sampling stops when nothing is visible."),
                isOn: $prefs.isMenuBarEnabled
            )
            Divider()
            HubToggleRow(
                title: localized("Open at login"),
                subtitle: localized("MonoHub appears in the menu bar when you log in to your Mac."),
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                guard newValue != PreferencesManager.shared.launchAtLogin else { return }
                PreferencesManager.shared.launchAtLogin = newValue
                launchAtLogin = PreferencesManager.shared.launchAtLogin
            }
        }
    }

    private var dataCollectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Update every"))
                        .font(.system(size: 12.5))
                    Text(localized("Longer intervals use less energy."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: refreshIntervalBinding) {
                    Text(localized("1 second")).tag(1.0)
                    Text(localized("2 seconds")).tag(2.0)
                    Text(localized("3 seconds")).tag(3.0)
                    Text(localized("5 seconds")).tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            Divider()
            HubToggleRow(
                title: localized("Pause when the display is off"),
                subtitle: localized("Stops sampling while the display sleeps or the session is locked."),
                isOn: $prefs.pauseWhenSleeping
            )
        }
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prefs.moduleOrder) { module in
                ModuleSettingsRow(module: module)
                    .reorderable(
                        scope: "menubar-module",
                        id: module.rawValue,
                        orderedIDs: prefs.moduleOrder.map(\.rawValue)
                    ) { moving, target in
                        guard let movingModule = ModuleType(rawValue: moving),
                              let targetModule = ModuleType(rawValue: target) else { return }
                        withAnimation(.snappy) {
                            prefs.moveModule(movingModule, onto: targetModule)
                        }
                    }
            }
        }
        .disabled(!prefs.isMenuBarEnabled)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Alert colors"),
                subtitle: localized("Highlights in orange and red when usage gets high."),
                isOn: $prefs.useDynamicColors
            )
            Divider()
            HubToggleRow(
                title: localized("Show percent symbol"),
                isOn: $prefs.showPercentSymbol
            )
            Divider()
            HubToggleRow(
                title: localized("Prominent value"),
                subtitle: localized("Uses larger numbers in the two-line style."),
                isOn: $prefs.prominentPercentage
            )
            Divider()
            HStack {
                Text(localized("Apply style to all"))
                    .font(.system(size: 12.5))
                Spacer()
                Menu(localized("Choose…")) {
                    ForEach(Self.presetStyles) { style in
                        Button {
                            prefs.applyPresetToAll(style)
                        } label: {
                            Label(style.title, systemImage: style.sfSymbol)
                        }
                    }
                }
                .fixedSize()
            }
        }
        .disabled(!prefs.isMenuBarEnabled)
    }

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Count"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.topProcessesCount) {
                    Text(localized("None")).tag(0)
                    Text(localized("3 processes")).tag(3)
                    Text(localized("5 processes")).tag(5)
                    Text(localized("8 processes")).tag(8)
                    Text(localized("10 processes")).tag(10)
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Divider()
            Group {
                HubToggleRow(title: localized("In the Processor panel"), isOn: $prefs.showTopProcessesCPU)
                HubToggleRow(title: localized("In the Memory panel"), isOn: $prefs.showTopProcessesRAM)
                HubToggleRow(title: localized("In the Graphics panel"), isOn: $prefs.showTopProcessesGPU)
                HubToggleRow(title: localized("In the Battery panel"), isOn: $prefs.showTopProcessesBattery)
                HubToggleRow(title: localized("In the Storage panel"), isOn: $prefs.showTopProcessesDisk)
            }
            .disabled(prefs.topProcessesCount == 0)
        }
    }

    private var refreshIntervalBinding: Binding<TimeInterval> {
        Binding {
            let current = prefs.refreshInterval
            return Self.refreshIntervals.min { abs($0 - current) < abs($1 - current) } ?? 2
        } set: { newValue in
            prefs.refreshInterval = newValue
        }
    }
}

private struct ModuleSettingsRow: View {
    let module: ModuleType
    @Bindable private var prefs = MonitorPreferences.shared

    init(module: ModuleType) {
        self.module = module
    }

    var body: some View {
        let isEnabled = prefs.isModuleEnabled(module)
        let isLastEnabled = isEnabled && prefs.enabledModules.count == 1

        HStack(spacing: 10) {
            ReorderGrip()
            HubIcon(systemName: module.sfSymbol, tint: module.tint)
            Text(module.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker(localized("Style"), selection: styleBinding) {
                ForEach(module.availableStyles) { option in
                    Text(option.title(for: module)).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!isEnabled)
            Toggle(localized("Show"), isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isLastEnabled)
                .help(isLastEnabled ? localized("At least one module must remain visible") : "")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(localized("Move Left")) { prefs.moveModuleUp(module) }
            Button(localized("Move Right")) { prefs.moveModuleDown(module) }
        }
    }

    private var styleBinding: Binding<DisplayStyle> {
        Binding {
            prefs.displayStyle(for: module)
        } set: { newValue in
            prefs.setDisplayStyle(newValue, for: module)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            prefs.isModuleEnabled(module)
        } set: { newValue in
            guard newValue != prefs.isModuleEnabled(module) else { return }
            prefs.toggleModule(module)
        }
    }
}

private struct MenuBarPreview: View {
    let module: ModuleType
    let style: DisplayStyle

    var body: some View {
        Image(nsImage: MenuBarRenderer.image(for: MenuBarContentFactory.content(for: module, style: style)))
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}
