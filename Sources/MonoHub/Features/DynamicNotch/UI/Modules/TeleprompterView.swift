import SwiftUI
import AVFoundation
import AppKit

struct TeleprompterView: View {
    @Bindable private var manager = TeleprompterManager.shared
    @Bindable private var preferences = NotchPreferences.shared
    @Bindable private var cameraManager = CameraMirrorManager.shared

    @State private var copiedToClipboard: Bool = false
    @State private var consumerID = "teleprompter-\(UUID().uuidString)"

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch manager.mode {
            case .reading:
                teleprompterReadingView
            case .editing:
                headerBar
                scratchpadEditingView
            }
        }
        .notchModule()
        .onAppear {
            if manager.isCameraEnabled {
                cameraManager.startSession(consumer: consumerID)
            }
            if manager.scrollOffset > 0 && manager.scrollOffset >= manager.maxScrollOffset {
                manager.rewind()
            }
        }
        .onDisappear {
            cameraManager.stopSession(consumer: consumerID)
        }
        .onChange(of: manager.isCameraEnabled) { _, isEnabled in
            if isEnabled {
                cameraManager.startSession(consumer: consumerID)
            } else {
                cameraManager.stopSession(consumer: consumerID)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            NotchSectionLabel(localized("Teleprompter"), systemImage: "text.viewfinder", tint: .mint)

            scriptSelectorMenu

            Spacer(minLength: 4)

            cameraToggleButton

            modePicker

            Button {
                NotchHaptics.tap()
                withAnimation(NotchTheme.content) {
                    manager.isPinned.toggle()
                }
            } label: {
                Image(systemName: manager.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(manager.isPinned ? Color.mint : NotchTheme.tertiaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(manager.isPinned ? Color.mint.opacity(0.18) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(manager.isPinned ? localized("Notch pinned open (does not collapse on mouse exit)") : localized("Pin Notch open during meeting"))

            optionsMenu
        }
    }

    private var cameraToggleButton: some View {
        Button {
            NotchHaptics.tap()
            withAnimation(NotchTheme.content) {
                manager.isCameraEnabled.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: manager.isCameraEnabled ? "video.fill" : "video.slash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(manager.isCameraEnabled ? Color.mint : NotchTheme.tertiaryText)

                Text(manager.isCameraEnabled ? localized("Camera On") : localized("Camera Off"))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .foregroundStyle(manager.isCameraEnabled ? Color.white : NotchTheme.secondaryText)
            .background(
                Capsule(style: .continuous)
                    .fill(manager.isCameraEnabled ? Color.mint.opacity(0.20) : Color.white.opacity(0.07))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(manager.isCameraEnabled ? Color.mint.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(manager.isCameraEnabled ? localized("Disable background camera preview") : localized("Enable live FaceTime camera behind teleprompter"))
    }

    private var scriptSelectorMenu: some View {
        Menu {
            Section(localized("Saved Scripts")) {
                ForEach(manager.scripts) { script in
                    Button {
                        NotchHaptics.tap()
                        manager.selectScript(id: script.id)
                    } label: {
                        HStack {
                            Text(script.title)
                            if script.id == manager.activeScriptID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                NotchHaptics.tap()
                manager.createNewScript(title: localized("New Script"), content: "")
            } label: {
                Label(localized("New Note / Script"), systemImage: "plus")
            }

            Button {
                NotchHaptics.tap()
                manager.duplicateActiveScript()
            } label: {
                Label(localized("Duplicate Current"), systemImage: "doc.on.doc")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.mint)

                Text(manager.activeScript.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 118, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(TeleprompterMode.allCases) { m in
                let isSelected = manager.mode == m
                Button {
                    NotchHaptics.tap()
                    withAnimation(NotchTheme.content) {
                        manager.mode = m
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.iconName)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                        Text(m.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .foregroundStyle(isSelected ? Color.white : NotchTheme.secondaryText)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.mint.opacity(0.24) : Color.clear)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isSelected ? Color.mint.opacity(0.35) : Color.clear, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .fixedSize()
    }

    private var optionsMenu: some View {
        Menu {
            Menu(localized("Insert Template")) {
                ForEach(TeleprompterTemplate.allCases) { template in
                    Button {
                        NotchHaptics.tap()
                        manager.applyTemplate(template)
                    } label: {
                        Label(template.title, systemImage: template.iconName)
                    }
                }
            }

            Divider()

            Toggle(localized("Live FaceTime Camera"), isOn: $manager.isCameraEnabled)
            Toggle(localized("Eye-Contact Focus Guide (Camera)"), isOn: $manager.showFocusGuide)
            Toggle(localized("Optical Mirroring (Flip Text)"), isOn: $manager.isMirrored)
            Toggle(localized("Keep Notch Open When Playing"), isOn: $preferences.teleprompterKeepOpenWhilePlaying)

            if manager.isCameraEnabled {
                Divider()
                Toggle(localized("Horizontal Camera Mirror"), isOn: $cameraManager.isMirrored)
                Toggle(localized("Studio Light (Contrast)"), isOn: $cameraManager.isStudioLightEnabled)
                Toggle(localized("Portrait Effect (Vignette)"), isOn: $cameraManager.isPortraitEnabled)
                Toggle(localized("Notch Ring Light Illumination"), isOn: $cameraManager.isRingLightEnabled)
            }

            Divider()

            Button {
                copyAllToClipboard()
            } label: {
                Label(localized("Copy All"), systemImage: "doc.on.clipboard")
            }

            if manager.scripts.count > 1 {
                Divider()
                Button(role: .destructive) {
                    NotchHaptics.tap()
                    manager.deleteScript(id: manager.activeScriptID)
                } label: {
                    Label(localized("Delete Script"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var teleprompterReadingView: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .top) {

                backgroundCameraLayer

                TeleprompterScrollingViewport(
                    content: manager.activeScript.content,
                    fontSize: manager.fontSize,
                    isMirrored: manager.isMirrored,
                    onEditRequested: {
                        manager.mode = .editing
                    }
                )

                if manager.showFocusGuide {
                    focalSightlineGuide
                        .allowsHitTesting(false)
                }

                vignetteGradients
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    TeleprompterProgressScrubber()
                }
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.75)
            )

            readingControlsToolbar
        }
    }

    private var backgroundCameraLayer: some View {
        ZStack {
            if manager.isCameraEnabled {
                if cameraManager.isAccessDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                        Text(localized("Camera access unauthorized"))
                            .font(NotchTheme.title)
                            .foregroundStyle(.white)
                        Text(localized("Allow camera access in System Settings to see mirror in teleprompter."))
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                        Button(localized("Open Settings")) {
                            cameraManager.openPrivacySettings()
                        }
                        .buttonStyle(NotchSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.85))
                } else if cameraManager.isRunning {
                    CameraPreviewNSView(
                        session: cameraManager.captureSession,
                        isMirrored: cameraManager.isMirrored,
                        isStudioLight: cameraManager.isStudioLightEnabled,
                        isPortrait: cameraManager.isPortraitEnabled,
                        exposureBias: cameraManager.exposureBias,
                        zoomScale: CGFloat(cameraManager.zoomFactor),
                        cornerRadius: NotchTheme.cardRadius
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    CameraVignetteOverlay(
                        isStudioLight: cameraManager.isStudioLightEnabled,
                        isPortrait: cameraManager.isPortraitEnabled
                    )

                    Color.black.opacity(manager.cameraDimming)

                    if cameraManager.isRingLightEnabled {
                        RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                            .strokeBorder(Color(red: 1.0, green: 0.96, blue: 0.88), lineWidth: 4)
                            .shadow(color: Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.8), radius: 8)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(localized("Starting FaceTime camera…"))
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.75))
                }
            } else {
                RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.11).opacity(0.85),
                                Color(white: 0.05).opacity(0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var focalSightlineGuide: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 15)

            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Circle().fill(Color.mint).frame(width: 3.5, height: 3.5)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.mint.opacity(0.45), Color.mint.opacity(0.15)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.mint)

                    Text(localized("LOOK HERE"))
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(Color.mint)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.78))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.mint.opacity(0.55), lineWidth: 0.75)
                        )
                )

                HStack(spacing: 2) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.mint.opacity(0.15), Color.mint.opacity(0.45)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                    Circle().fill(Color.mint).frame(width: 3.5, height: 3.5)
                }
            }
            .padding(.horizontal, 14)

            Spacer()
        }
    }

    private var vignetteGradients: some View {
        VStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            Spacer()

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.80)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
        }
    }

    private var readingControlsToolbar: some View {
        HStack(spacing: 6) {

            Button {
                NotchHaptics.tap()
                manager.rewind()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.09))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Reiniciar roteiro do início")

            Button {
                NotchHaptics.tap()
                manager.togglePlayPause()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))

                    Text(manager.formattedElapsedTime)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
                .foregroundStyle(manager.isPlaying ? Color.black : Color.black)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(manager.isPlaying ? Color.mint : Color.white)
                        .shadow(color: (manager.isPlaying ? Color.mint : Color.white).opacity(0.25), radius: 5, y: 1)
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(manager.isPlaying ? "Pausar rolagem (Espaço)" : "Iniciar rolagem automática (Espaço)")

            scriptSelectorMenu

            Spacer(minLength: 4)

            HStack(spacing: 6) {

                HStack(spacing: 3) {
                    Button {
                        NotchHaptics.tap()
                        manager.adjustSpeed(by: -5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(manager.speed))pt/s")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NotchTheme.primaryText.opacity(0.88))
                        .frame(width: 38, alignment: .center)

                    Button {
                        NotchHaptics.tap()
                        manager.adjustSpeed(by: 5)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                .help(localized("Auto-scroll speed"))

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 12)

                HStack(spacing: 3) {
                    Button {
                        NotchHaptics.tap()
                        manager.adjustFontSize(by: -2)
                    } label: {
                        Text("A-")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 18)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(manager.fontSize))")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 16, alignment: .center)

                    Button {
                        NotchHaptics.tap()
                        manager.adjustFontSize(by: 2)
                    } label: {
                        Text("A+")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 18)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                .help(localized("Script font size"))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .fixedSize()

            Button {
                NotchHaptics.tap()
                withAnimation(NotchTheme.content) {
                    manager.isCameraEnabled.toggle()
                }
            } label: {
                Image(systemName: manager.isCameraEnabled ? "video.fill" : "video.slash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(manager.isCameraEnabled ? Color.mint : NotchTheme.tertiaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(manager.isCameraEnabled ? Color.mint.opacity(0.20) : Color.white.opacity(0.08))
                            .overlay(
                                Circle()
                                    .strokeBorder(manager.isCameraEnabled ? Color.mint.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(manager.isCameraEnabled ? localized("Disable background camera") : localized("Enable background FaceTime camera"))

            Button {
                NotchHaptics.tap()
                withAnimation(NotchTheme.content) {
                    manager.mode = .editing
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10, weight: .semibold))
                    Text(localized("Edit"))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(localized("Edit script text"))

            optionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    private var scratchpadEditingView: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mint)

                    TextField(
                        localized("Script Title"),
                        text: Binding(
                            get: { manager.activeScript.title },
                            set: { manager.updateActiveTitle($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )

                    TextEditor(
                        text: Binding(
                            get: { manager.activeScript.content },
                            set: { manager.updateActiveContent($0) }
                        )
                    )
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)

                    if manager.activeScript.content.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localized("Type your talking points, meeting notes, or script here…"))
                            Text(localized("You can also use the “Insert Template” menu to load ready-made outlines."))
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .padding(12)
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(String(format: localized("%d words"), manager.activeScript.wordCount))
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.secondaryText)

                    Text("•")
                        .foregroundStyle(NotchTheme.tertiaryText)

                    Text(manager.activeScript.formattedReadingTime)
                        .font(NotchTheme.caption)
                        .foregroundStyle(Color.mint.opacity(0.9))
                }

                Spacer()

                Button {
                    copyAllToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.clipboard")
                        Text(copiedToClipboard ? localized("Copied!") : localized("Copy"))
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())
                .fixedSize()
                .help(localized("Copy all text to clipboard"))

                Button {
                    NotchHaptics.tap()
                    manager.rewind()
                    withAnimation(NotchTheme.content) {
                        manager.mode = .reading
                    }
                    manager.play()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(localized("Start Reading"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.mint)
                    )
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(localized("Switch to teleprompter mode and begin scrolling"))
            }
        }
    }

    private func copyAllToClipboard() {
        NotchHaptics.tap()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manager.activeScript.content, forType: .string)

        withAnimation {
            copiedToClipboard = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            copiedToClipboard = false
        }
    }
}

private struct TeleprompterScrollingViewport: View {
    let content: String
    let fontSize: Double
    let isMirrored: Bool
    let onEditRequested: () -> Void

    private let manager = TeleprompterManager.shared
    @State private var isDragging = false
    @State private var dragInitialOffset: CGFloat = 0

    private var hasContent: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            if hasContent {
                TeleprompterStaticScriptBody(
                    content: content,
                    fontSize: fontSize,
                    isMirrored: isMirrored,
                    bottomSpacerHeight: max(110, geo.size.height - 24)
                )
                .equatable()
                .background(
                    GeometryReader { contentGeo in
                        Color.clear
                            .onAppear {
                                updateMaxScroll(contentHeight: contentGeo.size.height, viewportHeight: geo.size.height)
                            }
                            .onChange(of: contentGeo.size.height) { _, newH in
                                updateMaxScroll(contentHeight: newH, viewportHeight: geo.size.height)
                            }
                            .onChange(of: geo.size.height) { _, newV in
                                updateMaxScroll(contentHeight: contentGeo.size.height, viewportHeight: newV)
                            }
                    }
                )
                .offset(y: -manager.scrollOffset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { val in
                            if !isDragging {
                                isDragging = true
                                dragInitialOffset = manager.scrollOffset
                            }
                            let newOffset = dragInitialOffset - val.translation.height
                            manager.scrubTo(offset: newOffset)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onTapGesture {
                    NotchHaptics.tap()
                    manager.togglePlayPause()
                }

                if manager.maxScrollOffset > 0 && manager.scrollOffset >= manager.maxScrollOffset - 4 {
                    endOfScriptOverlay
                }
            } else {
                emptyScriptPlaceholder
            }
        }
        .clipped()
    }

    private func updateMaxScroll(contentHeight: CGFloat, viewportHeight: CGFloat) {
        let scrollable = max(0, contentHeight - viewportHeight)
        if abs(manager.maxScrollOffset - scrollable) > 0.5 {
            manager.maxScrollOffset = scrollable
        }
    }

    private var endOfScriptOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.mint)

            Text(localized("End of Script"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Button {
                NotchHaptics.tap()
                manager.rewind()
            } label: {
                Label(localized("Restart from Beginning"), systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(NotchSecondaryButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.mint.opacity(0.4), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .transition(.opacity)
    }

    private var emptyScriptPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 24))
                .foregroundStyle(NotchTheme.tertiaryText)

            Text(localized("Empty script"))
                .font(NotchTheme.title)
                .foregroundStyle(NotchTheme.secondaryText)

            Text(localized("Click Edit to compose or insert a template."))
                .font(NotchTheme.caption)
                .foregroundStyle(NotchTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                NotchHaptics.tap()
                onEditRequested()
            } label: {
                Text(localized("Write Notes"))
            }
            .buttonStyle(NotchSecondaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TeleprompterStaticScriptBody: View, Equatable {
    let content: String
    let fontSize: Double
    let isMirrored: Bool
    let bottomSpacerHeight: CGFloat

    var body: some View {
        let paragraphs = content.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 9) {

            Color.clear.frame(height: 24)

            ForEach(paragraphs.indices, id: \.self) { idx in
                let line = paragraphs[idx]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Color.clear.frame(height: 6)
                } else {
                    Text(line)
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.85), radius: 2.5, x: 0, y: 1)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                }
            }

            Color.clear.frame(height: bottomSpacerHeight)
        }
        .padding(.horizontal, 22)
        .fixedSize(horizontal: false, vertical: true)
        .drawingGroup()
    }
}

private struct TeleprompterProgressScrubber: View {
    private let manager = TeleprompterManager.shared

    var body: some View {
        GeometryReader { geo in
            let progress = manager.scrollProgress
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.mint.opacity(0.80), .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * progress), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(1.0, max(0.0, value.location.x / max(1, geo.size.width)))
                        manager.scrubTo(offset: manager.maxScrollOffset * fraction)
                    }
            )
        }
        .frame(height: 8)
    }
}
