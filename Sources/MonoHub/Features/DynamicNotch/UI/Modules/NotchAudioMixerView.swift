import SwiftUI
import AppKit
import AVFoundation

struct NotchAudioMixerView: View {
    @Bindable private var deviceManager = AudioDeviceManager.shared
    private let volumeManager = AudioVolumeManager.shared
    private let processMixer = AudioProcessVolumeManager.shared

    enum SubTab: String, CaseIterable {
        case apps
        case devices
    }

    @State private var selectedSubTab: SubTab = .apps

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topToolbar

            if selectedSubTab == .apps {
                perAppMixerContent
            } else {
                devicesAndDefaultsContent
            }
        }
        .notchModule()
        .onAppear {
            deviceManager.startMonitoring(client: "NotchAudioMixerView")
            deviceManager.refreshDevices()
            volumeManager.fetchVolume()
            processMixer.startMonitoring(client: "NotchAudioMixerView")
        }
        .onDisappear {
            processMixer.stopMonitoring(client: "NotchAudioMixerView")
            deviceManager.stopMonitoring(client: "NotchAudioMixerView")
        }
    }

    private var topToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                subTabButton(
                    tab: .apps,
                    title: localized("Per-Application Volume Mixer"),
                    icon: "slider.horizontal.below.square.and.square.filled",
                    badgeCount: processMixer.activeSessions.count
                )
                subTabButton(
                    tab: .devices,
                    title: localized("Default Microphone:"),
                    icon: deviceManager.isMicrophoneLocked ? "lock.fill" : "mic.fill",
                    badgeCount: nil
                )
            }
            .padding(2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
            )

            Spacer()

            HStack(spacing: 6) {
                Button {
                    NotchHaptics.tap()
                    deviceManager.toggleInputMute()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: deviceManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(deviceManager.isInputMuted ? Color.red : Color.green)
                        Text(deviceManager.currentInputDevice?.name ?? localized("Microphone"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                        if deviceManager.isMicrophoneLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(deviceManager.isInputMuted ? Color.red.opacity(0.16) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    NotchHaptics.tap()
                    MainWindowController.shared.show(item: .audioControl)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help(localized("Sound & Audio Control"))
            }
        }
    }

    private func subTabButton(tab: SubTab, title: String, icon: String, badgeCount: Int?) -> some View {
        let isSelected = selectedSubTab == tab
        return Button {
            NotchHaptics.tap()
            withAnimation(NotchTheme.content) {
                selectedSubTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.orange : Color.white.opacity(0.65))
                Text(title.replacingOccurrences(of: ":", with: ""))
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                    .lineLimit(1)
                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var perAppMixerContent: some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    volumeManager.toggleMute()
                } label: {
                    Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(volumeManager.isMuted ? Color.red : Color.cyan)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Text(deviceManager.currentOutputDevice?.name ?? localized("System Output"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .frame(width: 145, alignment: .leading)

                NotchCapsuleSlider(
                    value: Binding(
                        get: { Double(volumeManager.isMuted ? 0 : volumeManager.currentVolume) },
                        set: { volumeManager.setVolume(Float($0)) }
                    ),
                    range: 0...1,
                    tint: volumeManager.isMuted ? .red : .cyan,
                    trackHeight: 5,
                    expandedHeight: 8
                )

                Text("\(Int(round((volumeManager.isMuted ? 0 : volumeManager.currentVolume) * 100)))%")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if processMixer.activeSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.bubble")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(localized("No applications actively using audio"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(localized("Play music, video, or start a call in any app (Spotify, Music, Chrome, Discord, Zoom) to control its individual volume here."))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 5) {
                        ForEach(processMixer.activeSessions) { session in
                            notchAppMixerRow(session)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func notchAppMixerRow(_ session: AudioAppSession) -> some View {
        let effectivePercent = Int(round((session.isMuted ? 0 : session.volume) * 100))

        return HStack(spacing: 9) {
            Image(nsImage: processMixer.icon(for: session))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            HStack(spacing: 4) {
                Text(session.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                if session.isRunningInput {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
            }
            .frame(width: 132, alignment: .leading)

            Button {
                NotchHaptics.tap()
                processMixer.toggleMute(for: session.id)
            } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(session.isMuted ? Color.red : Color.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(session.isMuted ? Color.red.opacity(0.18) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            NotchCapsuleSlider(
                value: Binding(
                    get: { Double(session.isMuted ? 0 : session.volume) },
                    set: { processMixer.setVolume(Float($0), for: session.id) }
                ),
                range: 0...1.5,
                tint: session.isMuted ? .red : (effectivePercent > 100 ? .orange : .green),
                trackHeight: 5,
                expandedHeight: 8
            )

            Text(session.isMuted ? localized("Muted") : "\(effectivePercent)%")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(session.isMuted ? Color.red : (effectivePercent > 100 ? Color.orange : .white.opacity(0.75)))
                .frame(width: 44, alignment: .trailing)

            Button {
                NotchHaptics.tap()
                processMixer.setMuted(false, for: session.id)
                processMixer.setVolume(1.0, for: session.id)
            } label: {
                Text("100%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.09))
                    )
            }
            .buttonStyle(.plain)
            .opacity((!session.isMuted && abs(session.volume - 1.0) < 0.01) ? 0.35 : 1.0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var devicesAndDefaultsContent: some View {
        HStack(alignment: .top, spacing: 10) {

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: deviceManager.isMicrophoneLocked ? "lock.fill" : "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text(localized("Select Microphone").uppercased())
                        .font(NotchTheme.eyebrow)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Button {
                        NotchHaptics.tap()
                        deviceManager.toggleMicrophoneLock()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: deviceManager.isMicrophoneLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(deviceManager.isMicrophoneLocked ? localized("Microphone Locked") : localized("Lock Current"))
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(deviceManager.isMicrophoneLocked ? Color.green : .white.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(deviceManager.isMicrophoneLocked ? Color.green.opacity(0.18) : Color.white.opacity(0.09))
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Button {
                        NotchHaptics.tap()
                        deviceManager.toggleInputMute()
                    } label: {
                        Image(systemName: deviceManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(deviceManager.isInputMuted ? Color.red : Color.green)
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

                    Text("\(Int(round((deviceManager.isInputMuted ? 0 : deviceManager.inputVolume) * 100)))%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 32, alignment: .trailing)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
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
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "headphones")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text(localized("Audio Output").uppercased())
                        .font(NotchTheme.eyebrow)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    if let currentOut = deviceManager.currentOutputDevice {
                        let isPreferred = deviceManager.isPreferredOutput(currentOut)
                        Button {
                            NotchHaptics.tap()
                            deviceManager.setPreferredOutput(to: isPreferred ? nil : currentOut)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isPreferred ? "pin.fill" : "pin")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(isPreferred ? localized("Default") : localized("Set as Default Output"))
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(isPreferred ? Color.cyan : .white.opacity(0.8))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(isPreferred ? Color.cyan.opacity(0.18) : Color.white.opacity(0.09))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
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
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
