import SwiftUI
import AppKit
import AVFoundation

enum ActiveAudioMenu: Equatable {
    case none
    case output
    case input
    case voiceIsolation
}

struct AudioRouteBar: View {
    private let deviceManager = AudioDeviceManager.shared
    private let preferences = NotchPreferences.shared

    @State private var activeMenu: ActiveAudioMenu = .none
    @State private var isHoveringOutput = false
    @State private var isHoveringInput = false
    @State private var isHoveringVoice = false
    @State private var isHoveringMixer = false

    var body: some View {
        HStack(spacing: 6) {
            outputDevicePill
            inputDevicePill
            voiceIsolationPill
            soundMixerPill
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if activeMenu != .none {
                dropdownOverlay
                    .offset(x: dropdownOffsetX, y: 28)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity),
                            removal: .scale(scale: 0.95, anchor: .topLeading).combined(with: .opacity)
                        )
                    )
                    .zIndex(100)
            }
        }
        .onChange(of: activeMenu) { _, newValue in
            withAnimation(NotchTheme.content) {
                preferences.isMusicAudioMenuOpen = (newValue != .none)
            }
        }
        .onDisappear {
            if preferences.isMusicAudioMenuOpen {
                preferences.isMusicAudioMenuOpen = false
            }
        }
        .onExitCommand {
            withAnimation(NotchTheme.content) {
                activeMenu = .none
            }
        }
    }

    private var dropdownOffsetX: CGFloat {
        switch activeMenu {
        case .none, .output:
            return 0
        case .input:
            return 32
        case .voiceIsolation:
            return 60
        }
    }

    private var isOutputOpen: Bool { activeMenu == .output }

    private var outputDevicePill: some View {
        Button {
            NotchHaptics.tap()
            withAnimation(NotchTheme.content) {
                activeMenu = (activeMenu == .output) ? .none : .output
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: deviceManager.currentOutputDevice?.iconName ?? "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(deviceManager.currentOutputDevice?.name ?? localized("Speakers"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 40, maxWidth: 125, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(isOutputOpen ? 0.9 : 0.45))
                    .rotationEffect(.degrees(isOutputOpen ? 180 : 0))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isOutputOpen ? Color.white.opacity(0.20) : Color.white.opacity(isHoveringOutput ? 0.14 : 0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isOutputOpen ? Color.white.opacity(0.35) : Color.white.opacity(isHoveringOutput ? 0.22 : 0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringOutput = $0 }
        .help(localized("Select Audio Output Device"))
    }

    private var isInputOpen: Bool { activeMenu == .input }

    private var inputDevicePill: some View {
        HStack(spacing: 4) {
            Button {
                NotchHaptics.tap()
                deviceManager.toggleInputMute()
            } label: {
                Image(systemName: deviceManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(deviceManager.isInputMuted ? Color.red : Color.green.opacity(0.95))
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(deviceManager.isInputMuted ? localized("Unmute Microphone") : localized("Mute Microphone"))

            if preferences.musicEnableMicLevelMeter {
                if deviceManager.isInputMuted {
                    Capsule()
                        .fill(Color.red.opacity(0.65))
                        .frame(width: 9, height: 2.5)
                } else {
                    MicLevelIndicator(level: deviceManager.micLevel)
                        .frame(width: 9, height: 9)
                }
            }

            Button {
                NotchHaptics.tap()
                withAnimation(NotchTheme.content) {
                    activeMenu = (activeMenu == .input) ? .none : .input
                }
            } label: {
                HStack(spacing: 3) {
                    Text(deviceManager.currentInputDevice?.name ?? localized("Microphone"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(deviceManager.isInputMuted ? Color.red.opacity(0.9) : .white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 40, maxWidth: 115, alignment: .leading)

                    if deviceManager.isMicrophoneLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.green.opacity(0.95))
                            .help(localized("Microphone Locked"))
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(isInputOpen ? 0.9 : 0.45))
                        .rotationEffect(.degrees(isInputOpen ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(
            Capsule()
                .fill(deviceManager.isInputMuted ? Color.red.opacity(0.14) : (isInputOpen ? Color.white.opacity(0.20) : Color.white.opacity(isHoveringInput ? 0.14 : 0.08)))
        )
        .overlay(
            Capsule()
                .strokeBorder(deviceManager.isInputMuted ? Color.red.opacity(0.35) : (isInputOpen ? Color.white.opacity(0.35) : Color.white.opacity(isHoveringInput ? 0.22 : 0.12)), lineWidth: 0.5)
        )
        .onHover { isHoveringInput = $0 }
        .help(localized("Select Microphone & Toggle Mute"))
    }

    private var isVoiceOpen: Bool { activeMenu == .voiceIsolation }

    private var voiceIsolationPill: some View {
        Button {
            NotchHaptics.tap()
            withAnimation(NotchTheme.content) {
                activeMenu = (activeMenu == .voiceIsolation) ? .none : .voiceIsolation
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: deviceManager.isVoiceIsolationActive ? "waveform.badge.mic" : "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(deviceManager.isVoiceIsolationActive ? Color.purple : .white.opacity(0.85))

                if deviceManager.isVoiceIsolationActive {
                    Text(localized("Voice Isolation"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.purple.opacity(0.95))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, deviceManager.isVoiceIsolationActive ? 7 : 6)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(deviceManager.isVoiceIsolationActive ? Color.purple.opacity(0.18) : (isVoiceOpen ? Color.white.opacity(0.20) : Color.white.opacity(isHoveringVoice ? 0.14 : 0.08)))
            )
            .overlay(
                Capsule()
                    .strokeBorder(deviceManager.isVoiceIsolationActive ? Color.purple.opacity(0.4) : (isVoiceOpen ? Color.white.opacity(0.35) : Color.white.opacity(isHoveringVoice ? 0.22 : 0.12)), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringVoice = $0 }
        .help(localized("Voice Isolation & Microphone Modes"))
    }

    private var soundMixerPill: some View {
        Button {
            NotchHaptics.tap()
            withAnimation(NotchTheme.content) {
                activeMenu = .none
                if preferences.enableAudioModule {
                    preferences.selectTab(.audio)
                } else {
                    MainWindowController.shared.show(item: .audioControl)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.95))

                Text(localized("Sound"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isHoveringMixer ? 0.16 : 0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.orange.opacity(isHoveringMixer ? 0.45 : 0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringMixer = $0 }
        .help(localized("Sound & Audio Control"))
    }

    @ViewBuilder
    private var dropdownOverlay: some View {
        switch activeMenu {
        case .none:
            EmptyView()

        case .output:
            AudioDropdownCard(title: localized("Audio Output"), iconName: "speaker.wave.2.fill") {
                if let currentOut = deviceManager.currentOutputDevice {
                    let isPreferredOut = deviceManager.isPreferredOutput(currentOut)
                    HStack {
                        Button {
                            NotchHaptics.tap()
                            if isPreferredOut {
                                deviceManager.setPreferredOutput(to: nil)
                            } else {
                                deviceManager.setPreferredOutput(to: currentOut)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isPreferredOut ? "pin.fill" : "pin")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(isPreferredOut ? Color.cyan : Color.white.opacity(0.7))

                                Text(isPreferredOut ? localized("Default Output Fixed") : localized("Set as Default Output"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(isPreferredOut ? Color.cyan : Color.white.opacity(0.85))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isPreferredOut ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isPreferredOut ? Color.cyan.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }

                if deviceManager.availableOutputDevices.isEmpty {
                    Text(localized("No devices"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(deviceManager.availableOutputDevices) { device in
                        let isSelected = device.id == deviceManager.currentOutputDevice?.id || device.uid == deviceManager.currentOutputDevice?.uid
                        let isPreferred = deviceManager.isPreferredOutput(device)
                        AudioDropdownRow(
                            title: device.name,
                            iconName: device.iconName,
                            isSelected: isSelected,
                            trailingIconName: isPreferred ? "pin.fill" : nil,
                            trailingIconColor: .cyan
                        ) {
                            NotchHaptics.tap()
                            deviceManager.selectOutputDevice(device)
                            withAnimation(NotchTheme.content) {
                                activeMenu = .none
                            }
                        }
                    }
                }
            }

        case .input:
            AudioDropdownCard(title: localized("Select Microphone"), iconName: "mic.fill") {
                HStack(spacing: 6) {
                    Button {
                        NotchHaptics.tap()
                        deviceManager.toggleMicrophoneLock()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: deviceManager.isMicrophoneLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(deviceManager.isMicrophoneLocked ? Color.green : Color.white.opacity(0.7))

                            Text(deviceManager.isMicrophoneLocked ? localized("Microphone Locked") : localized("Lock Current Mic"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(deviceManager.isMicrophoneLocked ? Color.green : Color.white.opacity(0.85))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(deviceManager.isMicrophoneLocked ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(deviceManager.isMicrophoneLocked ? Color.green.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(localized("Keep this microphone fixed even when connecting AirPods"))

                    Spacer()

                    Text("\(Int(round((deviceManager.isInputMuted ? 0 : deviceManager.inputVolume) * 100)))%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)

                HStack(spacing: 7) {
                    Button {
                        NotchHaptics.tap()
                        deviceManager.toggleInputMute()
                    } label: {
                        Image(systemName: deviceManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(deviceManager.isInputMuted ? Color.red : Color.green)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)

                    NotchCapsuleSlider(
                        value: Binding(
                            get: { Double(deviceManager.isInputMuted ? 0 : deviceManager.inputVolume) },
                            set: { deviceManager.setInputVolume(Float($0)) }
                        ),
                        range: 0...1,
                        tint: deviceManager.isInputMuted ? .red : .green,
                        trackHeight: 4.5,
                        expandedHeight: 7
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

                if deviceManager.availableInputDevices.isEmpty {
                    Text(localized("No devices"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(deviceManager.availableInputDevices) { device in
                        let isSelected = device.id == deviceManager.currentInputDevice?.id || device.uid == deviceManager.currentInputDevice?.uid
                        let isLockedThis = deviceManager.isLockedMicrophone(device)
                        AudioDropdownRow(
                            title: device.name,
                            iconName: isLockedThis ? "lock.fill" : device.iconName,
                            isSelected: isSelected,
                            trailingIconName: isLockedThis ? "lock.fill" : nil,
                            trailingIconColor: .green
                        ) {
                            NotchHaptics.tap()
                            deviceManager.selectInputDevice(device, updateLockIfLocked: true)
                            withAnimation(NotchTheme.content) {
                                activeMenu = .none
                            }
                        }
                    }
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                HStack(spacing: 5) {
                    Text(localized("Microphone Mode").uppercased())
                        .font(NotchTheme.eyebrow)
                        .tracking(0.3)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)

                AudioDropdownRow(
                    title: localized("Standard"),
                    iconName: "waveform",
                    isSelected: deviceManager.preferredMicrophoneMode == .standard
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }

                AudioDropdownRow(
                    title: localized("Voice Isolation"),
                    iconName: "waveform.badge.mic",
                    isSelected: deviceManager.preferredMicrophoneMode == .voiceIsolation
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }

                AudioDropdownRow(
                    title: localized("Wide Spectrum"),
                    iconName: "waveform.badge.plus",
                    isSelected: deviceManager.preferredMicrophoneMode == .wideSpectrum
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }
            }

        case .voiceIsolation:
            AudioDropdownCard(title: localized("Voice Isolation & Microphone Modes"), iconName: "waveform.badge.mic") {
                AudioDropdownRow(
                    title: localized("Standard"),
                    iconName: "waveform",
                    isSelected: deviceManager.preferredMicrophoneMode == .standard
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }

                AudioDropdownRow(
                    title: localized("Voice Isolation"),
                    iconName: "waveform.badge.mic",
                    isSelected: deviceManager.preferredMicrophoneMode == .voiceIsolation
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }

                AudioDropdownRow(
                    title: localized("Wide Spectrum"),
                    iconName: "waveform.badge.plus",
                    isSelected: deviceManager.preferredMicrophoneMode == .wideSpectrum
                ) {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                Button {
                    NotchHaptics.tap()
                    deviceManager.showVoiceIsolationPicker()
                    withAnimation(NotchTheme.content) { activeMenu = .none }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(localized("System Sound Settings…"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AudioDropdownCard<Content: View>: View {
    let title: String
    let iconName: String
    var maxCardHeight: CGFloat = 170
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))

                Text(title.uppercased())
                    .font(NotchTheme.eyebrow)
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 2)

            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.horizontal, 6)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: max(90, maxCardHeight - 30))
        }
        .frame(width: 278)
        .frame(maxHeight: maxCardHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.62), radius: 14, x: 0, y: 6)
    }
}

struct AudioDropdownRow: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    var trailingIconName: String? = nil
    var trailingIconColor: Color = .green
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.green : .white.opacity(0.85))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let trailingIconName {
                    Image(systemName: trailingIconName)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(trailingIconColor)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(isHovered ? 0.16 : 0.09) : (isHovered ? Color.white.opacity(0.10) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct MicLevelIndicator: View {
    let level: Float

    var body: some View {
        HStack(spacing: 1.5) {
            let clamped = CGFloat(max(0.0, min(1.0, level)))
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.green.opacity(0.85))
                .frame(width: 2, height: max(2.5, 9.0 * (0.25 + 0.75 * clamped)))
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.green.opacity(0.95))
                .frame(width: 2, height: max(2.5, 9.0 * (0.35 + 0.65 * clamped)))
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.green.opacity(0.85))
                .frame(width: 2, height: max(2.5, 9.0 * (0.20 + 0.80 * clamped)))
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
