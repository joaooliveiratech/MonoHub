import SwiftUI

private enum CleanupSectionID: String, CaseIterable, Identifiable {
    case removal, diskAnalysis, projectPurge, exclusionList
    var id: String { rawValue }
}

struct CleanupSettingsView: View {
    @Bindable private var prefs = CleanupPreferences.shared
    @Bindable private var appPrefs = PreferencesManager.shared
    @State private var whitelistEntries: [String] = WhitelistManager.shared.allEntries()
    @State private var expandedSections: Set<CleanupSectionID> = [.removal, .diskAnalysis]

    private static let thresholds: [(String, Double)] = [
        ("50 MB", 52_428_800),
        ("100 MB", 104_857_600),
        ("250 MB", 262_144_000),
        ("500 MB", 524_288_000),
        ("1 GB", 1_073_741_824)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HubAccordionSection(
                    title: localized("Removal"),
                    subtitle: localized("Moving to Trash allows recovering files. Even without confirmation, permanent deletion always asks for confirmation. History is stored only in ~/Library/Logs/MonoHub."),
                    badgeText: prefs.moveToTrashInsteadOfDelete ? localized("Enabled") : localized("Removal"),
                    badgeColor: .green,
                    systemImage: "trash.fill",
                    tint: .green,
                    isExpanded: $expandedSections.contains(.removal)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HubToggleRow(title: localized("Move to Trash instead of deleting"), isOn: $prefs.moveToTrashInsteadOfDelete)
                        Divider()
                        HubToggleRow(title: localized("Confirm before removing"), isOn: $prefs.confirmBeforeDeleting)
                        Divider()
                        HubToggleRow(title: localized("Sound on completion"), isOn: $appPrefs.soundOnCompletion)
                        Divider()
                        HubToggleRow(title: localized("Record local log"), isOn: $prefs.enableLocalLogging)
                    }
                }

                HubAccordionSection(
                    title: localized("Disk Analysis"),
                    subtitle: localized("Passwords, Keychain, and browsing history are never touched. Only disposable caches are cleaned."),
                    badgeText: Self.thresholds.first(where: { $0.1 == prefs.largeFileThresholdBytes })?.0 ?? "100 MB",
                    badgeColor: .blue,
                    systemImage: "internaldrive.fill",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.diskAnalysis)
                ) {
                    HStack {
                        Text(localized("Large files starting at"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Picker("", selection: $prefs.largeFileThresholdBytes) {
                            ForEach(Self.thresholds, id: \.1) { title, value in
                                Text(title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                }

                HubAccordionSection(
                    title: localized("Project Purge"),
                    subtitle: localized("Folders where MonoHub looks for node_modules, .build, target, and .venv. More levels find more projects but take longer."),
                    badgeText: "\(prefs.devScanPaths.count)",
                    badgeColor: .indigo,
                    systemImage: "hammer.fill",
                    tint: .indigo,
                    isExpanded: $expandedSections.contains(.projectPurge)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(prefs.devScanPaths, id: \.self) { path in
                            PathRow(path: path, systemImage: "folder") {
                                prefs.removeDevPath(path)
                            }
                        }
                        Button(localized("Add Folder…")) {
                            if let path = appPrefs.openFolderPicker(title: localized("Select Projects Folder")) {
                                prefs.addDevPath(path)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Divider()

                        HStack {
                            Text(localized("Remove artifacts unused for"))
                                .font(.system(size: 12.5))
                            Spacer()
                            Picker("", selection: $prefs.projectArtifactAgeDays) {
                                Text(localized("Any age")).tag(0)
                                Text(localized("7 days")).tag(7)
                                Text(localized("30 days")).tag(30)
                                Text(localized("90 days")).tag(90)
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Divider()

                        HStack {
                            Text(localized("Maximum depth"))
                                .font(.system(size: 12.5))
                            Spacer()
                            Stepper(value: $prefs.projectScanMaxDepth, in: 2...6) {
                                Text(localized("%d levels", prefs.projectScanMaxDepth))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                HubAccordionSection(
                    title: localized("Exclusion List"),
                    subtitle: localized("Folders and files in this list are never touched by any cleanup routine."),
                    badgeText: "\(whitelistEntries.count)",
                    badgeColor: .orange,
                    systemImage: "lock.shield.fill",
                    tint: .orange,
                    isExpanded: $expandedSections.contains(.exclusionList)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if whitelistEntries.isEmpty {
                            Text(localized("No folders added. /System, /usr, and /Library are already protected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(whitelistEntries, id: \.self) { path in
                                PathRow(path: path, systemImage: "lock.shield") {
                                    WhitelistManager.shared.remove(path: path)
                                    whitelistEntries = WhitelistManager.shared.allEntries()
                                }
                            }
                        }
                        Button(localized("Add Folder…")) {
                            if let path = appPrefs.openFolderPicker(title: localized("Choose Folder to Protect")) {
                                WhitelistManager.shared.add(path: path)
                                whitelistEntries = WhitelistManager.shared.allEntries()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct PathRow: View {
    let path: String
    let systemImage: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Label {
                Text(path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(localized("Remove"))
        }
    }
}
