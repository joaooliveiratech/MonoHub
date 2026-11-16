import AppKit
import SwiftUI

enum ScreenshotSettingsSectionID: String, CaseIterable, Identifiable {
    case shortcuts
    case capture
    case saving
    case privacy

    var id: String { rawValue }
}

struct ScreenshotView: View {
    private let permissions = SwitcherPermissionsManager.shared
    private let session = ScreenshotShortcutRecordingSession.shared
    @Bindable private var prefs = ScreenshotPreferences.shared
    @State private var expandedSections: Set<ScreenshotSettingsSectionID> = []
    @State private var filterText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                overviewBanner
                ScreenshotPermissionSection()

                HubAccordionSection(
                    title: ShotText.sectionGlobalShortcuts,
                    subtitle: localized(
                        en: "Click a shortcut and press the new combination. Esc cancels.",
                        pt: "Clique em um atalho e pressione a nova combinação. Esc cancela."
                    ),
                    badgeText: "\(CaptureRequest.allCases.count)",
                    badgeColor: .pink,
                    systemImage: "keyboard.fill",
                    tint: .pink,
                    isExpanded: $expandedSections.contains(.shortcuts)
                ) {
                    ScreenshotShortcutsSection()
                }

                HubAccordionSection(
                    title: ShotText.sectionCaptureActions,
                    subtitle: prefs.showMenuBarIcon ? ShotText.showMenuBarIconSubtitleVisible : ShotText.showMenuBarIconSubtitleHidden,
                    badgeText: prefs.openEditorAfterCapture ? ShotText.openEditorTitle : ShotText.copyToClipboardTitle,
                    badgeColor: .blue,
                    systemImage: "camera.viewfinder",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.capture)
                ) {
                    ScreenshotCaptureSection()
                }

                HubAccordionSection(
                    title: localized(en: "Saving", pt: "Salvamento"),
                    subtitle: prefs.defaultExportFormat.isLossy
                        ? ShotText.qualityDescription(percent: Int((prefs.jpegQuality * 100).rounded()))
                        : ShotText.losslessFormatNote,
                    badgeText: prefs.defaultExportFormat.displayName,
                    badgeColor: .teal,
                    systemImage: "square.and.arrow.down.fill",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.saving)
                ) {
                    ScreenshotSaveSection()
                }

                HubAccordionSection(
                    title: ShotText.sectionTextRecognition,
                    subtitle: ShotText.privacySummary,
                    badgeText: prefs.concealRecognizedText ? localized("Enabled") : localized("Disabled"),
                    badgeColor: prefs.concealRecognizedText ? .green : .secondary,
                    systemImage: "text.viewfinder",
                    tint: .purple,
                    isExpanded: $expandedSections.contains(.privacy)
                ) {
                    ScreenshotPrivacySection()
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(CaptureRequest.allCases, id: \.self) { request in
                        Button {
                            ScreenshotController.shared.handleCaptureRequest(request)
                        } label: {
                            Label(request.menuTitle, systemImage: request.iconName)
                        }
                    }
                } label: {
                    Label(ShotText.menuCapture, systemImage: "play.fill")
                }
                .disabled(!FeatureManager.shared.isEnabled(.screenshot))
                .help(ShotText.shortcutAreaSubtitle)

                AccordionExpandToolbarButton(expandedSections: $expandedSections)
            }
        }
        .accordionFilter($filterText)
        .task {
            permissions.refresh(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            session.cancel()
        }
        .onDisappear {
            session.cancel()
            session.clearNotice()
        }
    }

    private var overviewBanner: some View {
        AccordionOverviewBanner(title: localized("Screenshots"), systemImage: CaptureRequest.area.iconName, tint: ScreenshotStyle.tint)
    }
}

private func localized(en english: String, pt portuguese: String) -> String {
    ShotText.pick(english, portuguese)
}

private struct ScreenshotPermissionSection: View {
    private let permissions = SwitcherPermissionsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowPermissionRow(
                title: localized(en: "Screen Recording", pt: "Gravação de Tela"),
                detail: permissions.hasScreenRecording ? ShotText.permissionActiveDesc : ShotText.permissionMissingDesc,
                systemImage: "record.circle",
                tint: .red,
                isGranted: permissions.hasScreenRecording,
                missingLabel: localized(en: "Required", pt: "Necessária")
            ) {
                permissions.openSettings(for: .screenRecording)
            }

            if !permissions.hasScreenRecording {
                Text(localized(
                    en: "Shortcuts stay registered, but captures only work once access is granted.",
                    pt: "Os atalhos continuam registrados, mas só capturam depois que o acesso for concedido."
                ))
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
                            permissions.hasScreenRecording ? Color.primary.opacity(0.08) : Color.orange.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }
}

private struct ScreenshotShortcutsSection: View {
    @Bindable private var prefs = ScreenshotPreferences.shared
    private let session = ScreenshotShortcutRecordingSession.shared

    private var usesDefaultShortcuts: Bool {
        CaptureRequest.allCases.allSatisfy { prefs.shortcut(for: $0) == $0.defaultShortcut }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(CaptureRequest.allCases, id: \.self) { request in
                HStack(spacing: 10) {
                    HubIcon(systemName: request.iconName, tint: ScreenshotStyle.tint)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(request.settingsTitle)
                            .font(.system(size: 12.5, weight: .medium))
                        Text(request.settingsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ScreenshotShortcutField(request: request)
                }
                .contextMenu {
                    Button(ShotText.menuCaptureNow) {
                        ScreenshotController.shared.handleCaptureRequest(request)
                    }
                    Divider()
                    Button(ShotText.restoreDefaultButton) {
                        prefs.setShortcut(request.defaultShortcut, for: request)
                    }
                    .disabled(prefs.shortcut(for: request) == request.defaultShortcut)
                }
            }

            Divider()

            HStack(alignment: .top) {
                if let notice = session.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(ShotText.duringSelectionLabel): \(ShotText.duringSelectionKeys)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(ShotText.inEditorLabel): \(ShotText.inEditorKeys)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(ShotText.restoreDefaultsButton) {
                    session.cancel()
                    session.clearNotice()
                    prefs.resetShortcutsToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(usesDefaultShortcuts)
            }
        }
    }
}

private struct ScreenshotCaptureSection: View {
    @Bindable private var prefs = ScreenshotPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(title: ShotText.copyToClipboardTitle, isOn: $prefs.copyToClipboardAfterCapture)
            Divider()
            HubToggleRow(title: ShotText.openEditorTitle, isOn: $prefs.openEditorAfterCapture)
            Divider()
            HubToggleRow(title: ShotText.playShutterSoundTitle, isOn: $prefs.playShutterSound)
            Divider()
            HubToggleRow(
                title: ShotText.showMenuBarIconTitle,
                subtitle: prefs.showMenuBarIcon ? ShotText.showMenuBarIconSubtitleVisible : ShotText.showMenuBarIconSubtitleHidden,
                isOn: $prefs.showMenuBarIcon
            )
        }
    }
}

private struct ScreenshotSaveSection: View {
    @Bindable private var prefs = ScreenshotPreferences.shared

    private var qualityPercent: Int {
        Int((prefs.jpegQuality * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ShotText.defaultExportFormatLabel)
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.defaultExportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(ShotText.compressionQualityLabel)
                        .font(.system(size: 12.5))
                    Text(prefs.defaultExportFormat.isLossy
                         ? ShotText.qualityDescription(percent: qualityPercent)
                         : ShotText.losslessFormatNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Slider(value: $prefs.jpegQuality, in: ScreenshotPreferences.jpegQualityRange, step: 0.05)
                        .frame(width: 150)
                    Text("\(qualityPercent)%")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .disabled(!prefs.defaultExportFormat.isLossy)
            }

            Divider()

            HubToggleRow(
                title: ShotText.downscaleRetinaTitle,
                subtitle: ShotText.downscaleRetinaSubtitle,
                isOn: $prefs.downscaleRetina
            )

            Divider()

            HStack {
                Text(ShotText.saveLocationModePicker)
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $prefs.saveLocationMode) {
                    ForEach(SaveLocationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            if prefs.saveLocationMode == .custom {
                HStack {
                    Text(ShotText.customFolderLabel)
                        .font(.system(size: 12.5))
                    Spacer()
                    FolderPathLabel(path: prefs.customSaveDirectory)
                    Button(ShotText.chooseButton, action: chooseCustomDirectory)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                HStack {
                    Text(ShotText.lastUsedFolderLabel)
                        .font(.system(size: 12.5))
                    Spacer()
                    FolderPathLabel(path: prefs.lastUsedSaveDirectory)
                }
            }
        }
    }

    private func chooseCustomDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = ShotText.chooseFolderPrompt
        panel.directoryURL = URL(fileURLWithPath: prefs.customSaveDirectory, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.customSaveDirectory = url.path
    }
}

private struct FolderPathLabel: View {
    let path: String

    var body: some View {
        Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .help(path)
    }
}

private struct ScreenshotPrivacySection: View {
    @Bindable private var prefs = ScreenshotPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubToggleRow(
                title: ShotText.concealRecognizedTextTitle,
                subtitle: ShotText.concealRecognizedTextSubtitle,
                isOn: $prefs.concealRecognizedText
            )
            Text(ShotText.privacySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
