import AppKit
import SwiftUI

enum SwitcherSettingsSectionID: String, CaseIterable, Identifiable {
    case activation
    case behavior
    case appearance
    case shortcuts

    var id: String { rawValue }
}

struct WindowSwitcherView: View {
    @Bindable private var prefs = SwitcherPreferencesManager.shared
    private let permissions = SwitcherPermissionsManager.shared

    @State private var expandedSections: Set<SwitcherSettingsSectionID> = []
    @State private var filterText = ""
    @State private var isConfirmingReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                overviewBanner

                permissionsCard

                HubAccordionSection(
                    title: localized("Activation"),
                    subtitle: prefs.shortcut.hint,
                    badgeText: prefs.shortcut.shortName,
                    badgeColor: .purple,
                    systemImage: "command.square.fill",
                    tint: .purple,
                    isExpanded: $expandedSections.contains(.activation)
                ) {
                    activationContent
                }

                HubAccordionSection(
                    title: localized("Behavior"),
                    subtitle: localized("The most recently used window appears first, like in macOS ⌘ Tab."),
                    badgeText: prefs.useRecentOrdering ? localized("Order by recent usage") : localized("Automatic"),
                    badgeColor: .blue,
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.behavior)
                ) {
                    behaviorContent
                }

                HubAccordionSection(
                    title: localized("Appearance"),
                    subtitle: localized("Thumbnails scale down automatically when there are many windows. System Reduce Motion and Reduce Transparency are respected."),
                    badgeText: "\(prefs.displayMode.displayName) • \(prefs.thumbnailSize.displayName)",
                    badgeColor: prefs.accent.color,
                    systemImage: "sparkles.rectangle.stack.fill",
                    tint: prefs.accent.color,
                    isExpanded: $expandedSections.contains(.appearance)
                ) {
                    appearanceContent
                }

                HubAccordionSection(
                    title: localized("Keyboard shortcuts"),
                    subtitle: localized("View keyboard shortcuts"),
                    badgeText: "\(ShortcutCatalog.groups.reduce(0) { $0 + $1.items.count })",
                    badgeColor: .teal,
                    systemImage: "keyboard.fill",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.shortcuts)
                ) {
                    shortcutsContent
                }

                resetFooter
            }
            .padding(20)
        }
        .confirmationDialog(localized("Restore switcher settings?"), isPresented: $isConfirmingReset) {
            Button(localized("Restore Defaults"), role: .destructive) {
                prefs.restoreDefaults()
            }
        } message: {
            Text(localized("Shortcut, appearance, and behavior return to original values."))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    SwitcherPanelController.shared.show()
                } label: {
                    Label(localized("Test Switcher"), systemImage: "play.fill")
                }
                .help(localized("Opens window switcher now"))

                AccordionExpandToolbarButton(expandedSections: $expandedSections)
            }
        }
        .accordionFilter($filterText)
        .task(id: permissions.allGranted) {
            await permissions.monitorUntilGranted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh(force: true)
        }
    }

    private var overviewBanner: some View {
        AccordionOverviewBanner(title: localized("Window Switcher"), systemImage: "macwindow.on.rectangle", tint: .purple)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HubIcon(
                    systemName: permissions.allGranted ? "checkmark.shield.fill" : "lock.shield.fill",
                    tint: permissions.allGranted ? .green : .orange
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Permissions"))
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(localized("Nothing is recorded to disk or sent over the network."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(
                    permissions.allGranted ? localized("Granted") : localized("Required"),
                    icon: permissions.allGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: permissions.allGranted ? .green : .orange
                )
            }

            Divider()

            WindowPermissionRow(
                title: localized("Accessibility"),
                detail: localized("Captures ⌥ Tab / ⌘ Tab and allows focusing, minimizing, and closing windows."),
                systemImage: "accessibility",
                tint: .blue,
                isGranted: permissions.hasAccessibility,
                missingLabel: localized("Required")
            ) {
                permissions.openSettings(for: .accessibility)
            }

            Divider()

            WindowPermissionRow(
                title: localized("Screen Recording"),
                detail: localized("Generates window thumbnails via ScreenCaptureKit."),
                systemImage: "rectangle.dashed.badge.record",
                tint: .red,
                isGranted: permissions.hasScreenRecording,
                missingLabel: localized("Optional")
            ) {
                permissions.openSettings(for: .screenRecording)
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
                            permissions.allGranted ? Color.primary.opacity(0.08) : Color.orange.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }

    private var activationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Shortcut"))
                        .font(.system(size: 12.5))
                    Text(prefs.shortcut.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $prefs.shortcut) {
                    ForEach(ShortcutPreference.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            HubToggleRow(
                title: localized("Menu bar icon"),
                subtitle: localized("Window Switcher (MonoTab) — click to switch"),
                isOn: $prefs.showMenuBarIcon
            )
        }
    }

    private var behaviorContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubToggleRow(
                title: localized("Order by recent usage"),
                subtitle: localized("The most recently used window appears first, like in macOS ⌘ Tab."),
                isOn: $prefs.useRecentOrdering
            )
            Divider()
            HubToggleRow(
                title: localized("Current space only"),
                subtitle: localized("Hides windows from other Mission Control spaces."),
                isOn: $prefs.currentSpaceOnly
            )
            Divider()
            HubToggleRow(
                title: localized("Include minimized windows"),
                subtitle: localized("Allows focusing and restoring windows in the Dock."),
                isOn: $prefs.showMinimizedWindows
            )
            Divider()
            HubToggleRow(
                title: localized("Group browser tabs"),
                subtitle: localized("Shows a single entry per window for Safari, Chrome, Arc, Firefox, Brave, and Edge."),
                isOn: $prefs.groupBrowserTabs
            )
            Divider()
            HubToggleRow(
                title: localized("Number shortcuts"),
                subtitle: localized("Displays 1 to 9 over top windows for direct selection."),
                isOn: $prefs.showQuickShortcuts
            )
            Divider()
            HubToggleRow(
                title: localized("Confirm before closing or quitting"),
                subtitle: localized("Asks for confirmation for W (close window) and ⌘ Q (quit app)."),
                isOn: $prefs.confirmDestructiveActions
            )
        }
    }

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Presentation"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.displayMode) {
                    ForEach(DisplayModePreference.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Divider()

            HStack {
                Text(localized("Thumbnail size"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.thumbnailSize) {
                    ForEach(ThumbnailSizePreference.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Divider()

            HStack {
                Text(localized("Display"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.screenTarget) {
                    ForEach(ScreenTargetPreference.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            HStack {
                Text(localized("Accent color"))
                    .font(.system(size: 12.5))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(AccentPreference.allCases) { accent in
                        let isSelected = prefs.accent == accent
                        Button {
                            prefs.accent = accent
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 12, height: 12)
                                if isSelected {
                                    Text(accent.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .padding(.horizontal, isSelected ? 8 : 5)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? accent.color.opacity(0.16) : Color.primary.opacity(0.05))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(isSelected ? accent.color.opacity(0.55) : Color.clear, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help(accent.displayName)
                    }
                }
            }
        }
    }

    private var shortcutsContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(ShortcutCatalog.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(group.items) { item in
                            HStack(spacing: 8) {
                                Text(item.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                SwitcherKeyCap(item.key)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private var resetFooter: some View {
        HStack {
            Text(localized("Thumbnails are captured only while the switcher is visible, kept in memory only, and discarded after brief disuse."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(localized("Restore Defaults…"), role: .destructive) {
                isConfirmingReset = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }
}

struct WindowPermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isGranted: Bool
    let missingLabel: String
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HubIcon(systemName: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isGranted {
                StatusBadge(localized("Granted"), icon: "checkmark.circle.fill", color: .green)
            } else {
                HStack(spacing: 8) {
                    StatusBadge(missingLabel, icon: "exclamationmark.triangle.fill", color: .orange)
                    Button(localized("Open System Settings"), action: openSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}
