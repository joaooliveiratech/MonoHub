import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TilingSettingsSectionID: String, CaseIterable, Identifiable {
    case general
    case snap
    case modifierDrag
    case spacing
    case fineTuning
    case shortcuts
    case exclusions
    case backup

    var id: String { rawValue }
}

struct WindowTilingView: View {
    @Bindable private var prefs = TilePreferencesManager.shared
    private let accessibility = TileAccessibilityManager.shared
    private let session = ShortcutRecordingSession.shared

    @State private var searchText = ""
    @State private var expandedSections: Set<TilingSettingsSectionID> = []

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if trimmedQuery.isEmpty {
                    overviewBanner
                    TilingPermissionsCard()

                    HubAccordionSection(
                        title: localized("General"),
                        subtitle: localized("Test on this window"),
                        badgeText: prefs.showMenuBarIcon ? localized("Menu bar icon") : localized("Automatic"),
                        badgeColor: .indigo,
                        systemImage: "rectangle.split.2x2.fill",
                        tint: .indigo,
                        isExpanded: $expandedSections.contains(.general)
                    ) {
                        TilingGeneralSection()
                    }

                    HubAccordionSection(
                        title: localized("Snap to edges"),
                        subtitle: localized("Drop a window at a screen edge or corner to arrange it."),
                        badgeText: prefs.isSnapEnabled ? "\(Int(prefs.snapThreshold)) pt" : localized("Disabled"),
                        badgeColor: prefs.isSnapEnabled ? .blue : .secondary,
                        systemImage: "rectangle.inset.topleft.filled",
                        tint: .blue,
                        isExpanded: $expandedSections.contains(.snap)
                    ) {
                        TilingSnapSection()
                    }

                    HubAccordionSection(
                        title: localized("Modifier drag"),
                        subtitle: localized("Move and resize with modifier keys"),
                        badgeText: prefs.isModifierDragEnabled ? prefs.dragModifier.title : localized("Disabled"),
                        badgeColor: prefs.isModifierDragEnabled ? .teal : .secondary,
                        systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                        tint: .teal,
                        isExpanded: $expandedSections.contains(.modifierDrag)
                    ) {
                        TilingModifierDragSection()
                    }

                    HubAccordionSection(
                        title: localized("Spacing"),
                        subtitle: "\(localized("Screen edge margin")) • \(localized("Gap between windows"))",
                        badgeText: "\(Int(prefs.outerMargin)) pt / \(Int(prefs.windowGap)) pt",
                        badgeColor: .purple,
                        systemImage: "square.resize",
                        tint: .purple,
                        isExpanded: $expandedSections.contains(.spacing)
                    ) {
                        TilingSpacingSection()
                    }

                    HubAccordionSection(
                        title: localized("Fine tuning"),
                        subtitle: localized("When repeating a half shortcut"),
                        badgeText: prefs.repeatBehavior.title,
                        badgeColor: .cyan,
                        systemImage: "slider.horizontal.3",
                        tint: .cyan,
                        isExpanded: $expandedSections.contains(.fineTuning)
                    ) {
                        TilingRepeatSection()
                    }

                    HubAccordionSection(
                        title: localized("Keyboard shortcuts"),
                        subtitle: localized("Click a shortcut and press the new combination. Esc cancels, Delete clears."),
                        badgeText: "\(WindowAction.allCases.filter { prefs.shortcut(for: $0) != nil }.count)",
                        badgeColor: .pink,
                        systemImage: "keyboard.fill",
                        tint: .pink,
                        isExpanded: $expandedSections.contains(.shortcuts)
                    ) {
                        TilingShortcutSections(query: "")
                    }

                    HubAccordionSection(
                        title: localized("Ignored apps"),
                        subtitle: localized("Shortcuts, snapping, and modifier drag do not affect windows of these apps."),
                        badgeText: localized("%d excluded", prefs.excludedBundleIdentifiers.count),
                        badgeColor: .orange,
                        systemImage: "eye.slash.fill",
                        tint: .orange,
                        isExpanded: $expandedSections.contains(.exclusions)
                    ) {
                        TilingExcludedAppsSection()
                    }

                    HubAccordionSection(
                        title: localized("Backup"),
                        subtitle: localized("Saves shortcuts, margins, snapping, and ignored apps to a local JSON file."),
                        badgeText: "JSON",
                        badgeColor: .green,
                        systemImage: "externaldrive.fill.badge.checkmark",
                        tint: .green,
                        isExpanded: $expandedSections.contains(.backup)
                    ) {
                        TilingBackupSection()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TilingShortcutSections(query: trimmedQuery)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(20)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Search shortcuts"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                AccordionExpandToolbarButton(expandedSections: $expandedSections)
            }
        }
        .task(id: accessibility.isTrusted) {
            await accessibility.monitorUntilTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility.refresh()
        }
        .onDisappear {
            session.cancel()
            session.clearNotice()
        }
    }

    private var overviewBanner: some View {
        AccordionOverviewBanner(title: localized("Window Tiling"), systemImage: "rectangle.split.2x2", tint: .indigo)
    }
}

private struct TilingPermissionsCard: View {
    private let accessibility = TileAccessibilityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WindowPermissionRow(
                title: localized("Accessibility"),
                detail: localized("Required to move and resize windows of other apps."),
                systemImage: "accessibility",
                tint: .blue,
                isGranted: accessibility.isTrusted,
                missingLabel: localized("Required")
            ) {
                accessibility.promptIfNeeded()
                accessibility.openSystemSettings()
            }

            if !accessibility.isTrusted {
                Text(localized("Shortcuts remain registered, but only act on windows after access is granted."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            accessibility.isTrusted ? Color.primary.opacity(0.08) : Color.orange.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }
}

private struct TilingGeneralSection: View {
    @Bindable private var prefs = TilePreferencesManager.shared

    private static let quickActions: [WindowAction] = [.leftHalf, .rightHalf, .maximize, .almostMaximize, .center, .restore]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Move to adjacent display when repeating at edge"),
                subtitle: localized("Pressing Left/Right Half or Move again (e.g. ⌥⇧H / ⌥⇧L) moves the window to the next monitor in that direction."),
                isOn: $prefs.moveToAdjacentDisplayOnEdge
            )

            Divider()

            HubToggleRow(
                title: localized("Menu bar icon"),
                isOn: $prefs.showMenuBarIcon
            )

            Divider()

            HStack {
                Text(localized("Test on this window"))
                    .font(.system(size: 12.5))
                Spacer()
                ControlGroup {
                    ForEach(Self.quickActions) { action in
                        Button {
                            WindowManager.shared.perform(action: action)
                        } label: {
                            Label(action.displayName, systemImage: action.sfSymbol)
                        }
                        .help(action.displayName)
                    }
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
        }
    }
}

private struct TilingSnapSection: View {
    @Bindable private var prefs = TilePreferencesManager.shared
    @State private var isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Snap by dragging to screen edges"),
                subtitle: localized("Drop a window at a screen edge or corner to arrange it."),
                isOn: $prefs.isSnapEnabled
            )

            if prefs.isSnapEnabled {
                Divider()

                if isSystemTilingEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(localized("macOS native tiling is active"))
                                .font(.system(size: 12, weight: .medium))
                            Text(localized("Disable “Drag windows to screen edges” in Desktop & Dock to avoid conflicts."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(localized("Open System Settings")) {
                            SystemTiling.openDesktopAndDockSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                }

                HubToggleRow(
                    title: localized("Show snap area preview"),
                    isOn: $prefs.isSnapPreviewEnabled
                )
                HubToggleRow(
                    title: localized("Haptic feedback on trackpad"),
                    isOn: $prefs.isSnapHapticEnabled
                )

                HStack {
                    Text(localized("Edge sensitivity"))
                        .font(.system(size: 12.5))
                    Spacer()
                    ValueSlider(
                        value: $prefs.snapThreshold,
                        range: TilePreferencesManager.snapThresholdRange,
                        step: 5,
                        unit: "pt"
                    )
                }

                HStack {
                    Text(localized("Bottom edge"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $prefs.bottomEdgeBehavior) {
                        ForEach(BottomEdgeBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SnapAreaDiagram(options: prefs.tileOptions, bottomEdge: prefs.bottomEdgeBehavior)
                    .padding(.vertical, 4)
            }

            Divider()

            HubToggleRow(
                title: localized("Restore size when dragging"),
                subtitle: localized("A tiled window returns to its original size when you drag it."),
                isOn: $prefs.restoresSizeOnDrag
            )

            Text(localized("Mouse events are only tracked during a drag, and only with one of these options enabled."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled
        }
    }
}

private struct TilingModifierDragSection: View {
    @Bindable private var prefs = TilePreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Move and resize with modifier keys"),
                subtitle: localized("Hold %@ and drag anywhere on the window with the left button to move or right button to resize.", prefs.dragModifier.title),
                isOn: $prefs.isModifierDragEnabled
            )

            if prefs.isModifierDragEnabled {
                Divider()
                HStack {
                    Text(localized("Keys"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $prefs.dragModifier) {
                        ForEach(DragModifier.allCases, id: \.self) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        }
    }
}

private struct TilingSpacingSection: View {
    @Bindable private var prefs = TilePreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Screen edge margin"))
                    .font(.system(size: 12.5))
                Spacer()
                ValueSlider(value: $prefs.outerMargin, range: TilePreferencesManager.marginRange, step: 2, unit: "pt")
            }
            Divider()
            HStack {
                Text(localized("Gap between windows"))
                    .font(.system(size: 12.5))
                Spacer()
                ValueSlider(value: $prefs.windowGap, range: TilePreferencesManager.gapRange, step: 2, unit: "pt")
            }
            Divider()
            HubToggleRow(
                title: localized("Keep margin when maximizing"),
                isOn: $prefs.marginOnMaximize
            )
        }
    }
}

private struct TilingRepeatSection: View {
    @Bindable private var prefs = TilePreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Move to adjacent display when repeating at edge"),
                subtitle: localized("Pressing Left/Right Half or Move again (e.g. ⌥⇧H / ⌥⇧L) moves the window to the next monitor in that direction."),
                isOn: $prefs.moveToAdjacentDisplayOnEdge
            )
            Divider()
            HStack {
                Text(localized("When repeating a half shortcut"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.repeatBehavior) {
                    ForEach(RepeatBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            Divider()
            HStack {
                Text(localized("Move and resize step"))
                    .font(.system(size: 12.5))
                Spacer()
                ValueSlider(value: $prefs.actionStep, range: TilePreferencesManager.stepRange, step: 10, unit: "pt")
            }
            Divider()
            HStack {
                Text(localized("Almost maximize"))
                    .font(.system(size: 12.5))
                Spacer()
                ValueSlider(value: $prefs.almostMaximizePercent, range: TilePreferencesManager.almostMaximizeRange, step: 5, unit: "%")
            }
        }
    }
}

private struct TilingShortcutSections: View {
    let query: String

    private let prefs = TilePreferencesManager.shared
    private let session = ShortcutRecordingSession.shared

    @State private var isConfirmingReset = false
    @State private var expandedCategories: Set<ActionCategory> = [.halves]

    var body: some View {
        let categories = filteredCategories()

        VStack(alignment: .leading, spacing: 10) {
            if query.isEmpty {
                HStack {
                    if let notice = session.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(localized("Click a shortcut and press the new combination. Esc cancels, Delete clears."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(localized("Custom shortcuts"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button(localized("Restore Defaults…")) {
                        isConfirmingReset = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(prefs.customShortcuts.isEmpty && prefs.disabledShortcuts.isEmpty)
                }
                .confirmationDialog(localized("Restore all window shortcuts?"), isPresented: $isConfirmingReset) {
                    Button(localized("Restore Defaults"), role: .destructive) {
                        session.cancel()
                        session.clearNotice()
                        prefs.resetShortcutsToDefaults()
                    }
                } message: {
                    Text(localized("Custom and removed shortcuts return to their original values."))
                }
            }

            if categories.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(categories, id: \.category) { entry in
                    let isOpen = !query.isEmpty || expandedCategories.contains(entry.category)
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            guard query.isEmpty else { return }
                            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                                if expandedCategories.contains(entry.category) {
                                    expandedCategories.remove(entry.category)
                                } else {
                                    expandedCategories.insert(entry.category)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if query.isEmpty {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                                        .frame(width: 14)
                                }
                                Text(entry.category.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(entry.actions.count)")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isOpen {
                            Divider()
                                .padding(.horizontal, 12)
                            VStack(spacing: 6) {
                                ForEach(entry.actions) { action in
                                    ShortcutRow(action: action, shortcut: prefs.shortcut(for: action))
                                }
                            }
                            .padding(12)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.025))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private func filteredCategories() -> [(category: ActionCategory, actions: [WindowAction])] {
        let normalized = query.lowercased()
        return ActionCategory.allCases.compactMap { category in
            let actions = normalized.isEmpty ? category.actions : category.actions.filter { matches($0, category: category, query: normalized) }
            return actions.isEmpty ? nil : (category, actions)
        }
    }

    private func matches(_ action: WindowAction, category: ActionCategory, query: String) -> Bool {
        action.displayName.lowercased().contains(query)
            || action.englishDisplayName.lowercased().contains(query)
            || action.commandName.contains(query)
            || category.title.lowercased().contains(query)
            || (prefs.shortcut(for: action)?.displayString.lowercased().contains(query) ?? false)
    }
}

private struct ShortcutRow: View {
    let action: WindowAction
    let shortcut: ShortcutKey?

    private var session: ShortcutRecordingSession { .shared }

    var body: some View {
        HStack {
            Label(action.displayName, systemImage: action.sfSymbol)
                .font(.system(size: 12.5))
            Spacer()
            ShortcutRecorderView(action: action, shortcut: shortcut)
        }
        .contextMenu {
            Button(localized("Execute on Active Window")) {
                WindowManager.shared.perform(action: action)
            }
            Divider()
            Button(localized("Restore Default")) {
                session.assign(action.defaultShortcut, to: action)
            }
            .disabled(shortcut == action.defaultShortcut)
            Button(localized("Clear Shortcut")) {
                session.assign(nil, to: action)
            }
            .disabled(shortcut == nil)
        }
    }
}

private struct TilingExcludedAppsSection: View {
    private let prefs = TilePreferencesManager.shared

    @State private var excludedApps: [AppMetadata] = []
    @State private var runningApps: [RunningAppChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if excludedApps.isEmpty {
                Text(localized("No ignored apps"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(excludedApps) { app in
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(app.name)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            prefs.setExcluded(false, bundleIdentifier: app.bundleIdentifier)
                        } label: {
                            Label(localized("Remove"), systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(localized("Resume managing windows for %@", app.name))
                    }
                }
            }

            Divider()

            HStack {
                Menu(localized("Add Running App")) {
                    let candidates = runningApps.filter { !prefs.isExcluded(bundleIdentifier: $0.bundleIdentifier) }
                    if candidates.isEmpty {
                        Text(localized("No other running apps"))
                    } else {
                        ForEach(candidates) { app in
                            Button(app.name) {
                                prefs.setExcluded(true, bundleIdentifier: app.bundleIdentifier)
                            }
                        }
                    }
                }
                .fixedSize()

                Button(localized("Choose in Finder…"), action: chooseAppFromFinder)
                    .buttonStyle(.bordered)

                Spacer()
            }
        }
        .onAppear {
            refreshRunningApps()
            excludedApps = prefs.excludedBundleIdentifiers.map { AppMetadata(bundleIdentifier: $0) }
        }
        .onChange(of: prefs.excludedBundleIdentifiers) { _, identifiers in
            excludedApps = identifiers.map { AppMetadata(bundleIdentifier: $0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRunningApps()
        }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningAppChoice? in
                guard app.activationPolicy == .regular,
                      let identifier = app.bundleIdentifier,
                      identifier != AppInfo.bundleId else { return nil }
                return RunningAppChoice(bundleIdentifier: identifier, name: app.localizedName ?? identifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier {
                prefs.setExcluded(true, bundleIdentifier: identifier)
            }
        }
    }
}

private struct TilingBackupSection: View {
    private let prefs = TilePreferencesManager.shared

    var body: some View {
        HStack {
            Text(localized("Saves shortcuts, margins, snapping, and ignored apps to a local JSON file."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(localized("Export…")) {
                SettingsBackup.presentExportPanel(for: prefs)
            }
            .buttonStyle(.bordered)
            Button(localized("Import…")) {
                SettingsBackup.presentImportPanel(for: prefs)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ValueSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .frame(minWidth: 140, maxWidth: 200)
            Text(unit == "%" ? "\(Int(value))%" : "\(Int(value)) \(unit)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .frame(minWidth: 54, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }
}

private struct RunningAppChoice: Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}
