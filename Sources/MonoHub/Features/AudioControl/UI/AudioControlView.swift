import SwiftUI
import AppKit
import AVFoundation
import CoreAudio

struct AudioControlView: View {
    @Bindable private var audioManager = AudioDeviceManager.shared
    private let volumeManager = AudioVolumeManager.shared
    private let processMixer = AudioProcessVolumeManager.shared

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                masterOverviewCard
                perAppVolumeMixerCard
                outputDeviceControlCard
                microphoneControlCard
            }
            .padding(20)
        }
        .onAppear {
            audioManager.startMonitoring(client: "AudioControlView")
            audioManager.refreshDevices()
            audioManager.startMetering(consumer: "AudioControlView")
            volumeManager.fetchVolume()
            processMixer.startMonitoring(client: "AudioControlView")
        }
        .onDisappear {
            audioManager.stopMetering(consumer: "AudioControlView")
            processMixer.stopMonitoring(client: "AudioControlView")
            audioManager.stopMonitoring(client: "AudioControlView")
        }
    }

    private var masterOverviewCard: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: audioManager.currentOutputDevice?.iconName ?? "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(localized("Active Output"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if audioManager.isCurrentOutputPreferred {
                            Text(localized("Default"))
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.cyan.opacity(0.16)))
                                .foregroundStyle(Color.cyan)
                        }
                    }

                    Menu {
                        if audioManager.availableOutputDevices.isEmpty {
                            Text(localized("No output devices"))
                        } else {
                            ForEach(audioManager.availableOutputDevices) { device in
                                let isSelected = isCurrentOutput(device)
                                Button {
                                    audioManager.selectOutputDevice(device)
                                } label: {
                                    HStack {
                                        Image(systemName: device.iconName)
                                        Text(device.name)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(audioManager.currentOutputDevice?.name ?? localized("System Output"))
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            volumeManager.toggleMute()
                        } label: {
                            Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(volumeManager.isMuted ? Color.red : Color.primary)
                        }
                        .buttonStyle(.plain)

                        Slider(
                            value: Binding(
                                get: { Double(volumeManager.isMuted ? 0 : volumeManager.currentVolume) },
                                set: { volumeManager.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)

                        Text("\(Int(round((volumeManager.isMuted ? 0 : volumeManager.currentVolume) * 100)))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
            )

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((audioManager.isInputMuted ? Color.red : Color.green).opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: audioManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(audioManager.isInputMuted ? Color.red : Color.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(localized("Active Microphone"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if audioManager.isMicrophoneLocked {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8.5))
                                Text(localized("Locked Default"))
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.green.opacity(0.16)))
                            .foregroundStyle(Color.green)
                        }
                    }

                    Menu {
                        if audioManager.availableInputDevices.isEmpty {
                            Text(localized("No microphones detected"))
                        } else {
                            ForEach(audioManager.availableInputDevices) { device in
                                let isSelected = isCurrentInput(device)
                                Button {
                                    audioManager.selectInputDevice(device, updateLockIfLocked: true)
                                } label: {
                                    HStack {
                                        Image(systemName: device.iconName)
                                        Text(device.name)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(audioManager.currentInputDevice?.name ?? localized("No Microphone"))
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            audioManager.toggleInputMute()
                        } label: {
                            Image(systemName: audioManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(audioManager.isInputMuted ? Color.red : Color.green)
                        }
                        .buttonStyle(.plain)

                        Slider(
                            value: Binding(
                                get: { Double(audioManager.isInputMuted ? 0 : audioManager.inputVolume) },
                                set: { audioManager.setInputVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)

                        Text("\(Int(round((audioManager.isInputMuted ? 0 : audioManager.inputVolume) * 100)))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var perAppVolumeMixerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "slider.horizontal.below.square.and.square.filled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Per-Application Volume Mixer"))
                        .font(.headline)
                    Text(localized("Control individual volume (0% to 150%) and mute for each app playing or capturing audio."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if processMixer.activeSessions.contains(where: { $0.isMuted || abs($0.volume - 1.0) > 0.01 }) {
                    Button {
                        processMixer.resetAllToDefault()
                    } label: {
                        Label(localized("Reset All (100%)"), systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    processMixer.refreshProcesses()
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            if processMixer.activeSessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2.bubble")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("No applications actively using audio"))
                            .font(.system(size: 13, weight: .medium))
                        Text(localized("Play music, video, or start a call in any app (Spotify, Music, Chrome, Discord, Zoom) to control its individual volume here."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(processMixer.activeSessions) { session in
                        appMixerRow(session)
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

    private func appMixerRow(_ session: AudioAppSession) -> some View {
        let effectivePercent = Int(round((session.isMuted ? 0 : session.volume) * 100))

        return HStack(spacing: 12) {
            Image(nsImage: processMixer.icon(for: session))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if session.isRunningOutput {
                        HStack(spacing: 3) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 8))
                            Text(localized("Playing"))
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                        .foregroundStyle(Color.green)
                    }

                    if session.isRunningInput {
                        HStack(spacing: 3) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 8))
                            Text(localized("Mic Active"))
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                        .foregroundStyle(Color.orange)
                    }
                }

                Text(session.bundleID.isEmpty ? "PID \(session.pid)" : session.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)

            Button {
                processMixer.toggleMute(for: session.id)
            } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : (session.volume < 0.01 ? "speaker.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.isMuted ? Color.red : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(session.isMuted ? Color.red.opacity(0.14) : Color.secondary.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .help(session.isMuted ? localized("Unmute Application") : localized("Mute Application"))

            Slider(
                value: Binding(
                    get: { Double(session.isMuted ? 0 : session.volume) },
                    set: { processMixer.setVolume(Float($0), for: session.id) }
                ),
                in: 0...1.5
            )
            .controlSize(.small)

            Text(session.isMuted ? localized("Muted") : "\(effectivePercent)%")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(session.isMuted ? Color.red : (effectivePercent > 100 ? Color.orange : Color.secondary))
                .frame(width: 48, alignment: .trailing)

            Button {
                processMixer.setMuted(false, for: session.id)
                processMixer.setVolume(1.0, for: session.id)
            } label: {
                Text("100%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(!session.isMuted && abs(session.volume - 1.0) < 0.01)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
        )
    }

    private var outputDeviceControlCard: some View {
        let activeOutputUID = audioManager.currentOutputDevice?.uid ?? ""
        let preferredOutputTag = audioManager.preferredOutputUID ?? ""
        let preferredIsDisconnected = !preferredOutputTag.isEmpty
            && !audioManager.availableOutputDevices.contains(where: { $0.uid == preferredOutputTag })

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "headphones")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Headphones & Audio Output Control"))
                        .font(.headline)
                    Text(localized("Choose your active sound output and configure your preferred default headphones or speakers."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    audioManager.refreshDevices()
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if !audioManager.availableOutputDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Available Audio Outputs"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 5) {
                            ForEach(audioManager.availableOutputDevices) { device in
                                outputDeviceRow(device)
                            }
                        }
                    }

                    Divider()
                }

                HStack(spacing: 12) {
                    Text(localized("Active Output:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { activeOutputUID },
                        set: { newUID in
                            if let dev = audioManager.availableOutputDevices.first(where: { $0.uid == newUID }) {
                                audioManager.selectOutputDevice(dev)
                            }
                        }
                    )) {
                        if audioManager.availableOutputDevices.isEmpty {
                            Text(localized("No output devices")).tag("")
                        } else {
                            if activeOutputUID.isEmpty {
                                Text(localized("System Output")).tag("")
                            }
                            ForEach(audioManager.availableOutputDevices) { device in
                                HStack {
                                    Image(systemName: device.iconName)
                                    Text(device.name)
                                }
                                .tag(device.uid)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                HStack(spacing: 12) {
                    Text(localized("Default Headphones/Output:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { preferredOutputTag },
                        set: { newUID in
                            if newUID.isEmpty {
                                audioManager.setPreferredOutput(to: nil)
                            } else if let dev = audioManager.availableOutputDevices.first(where: { $0.uid == newUID }) {
                                audioManager.setPreferredOutput(to: dev)
                            }
                        }
                    )) {
                        Text(localized("System Default (No Preference)")).tag("")
                        if preferredIsDisconnected {
                            let label = audioManager.preferredOutputName ?? preferredOutputTag
                            Text("\(label) (\(localized("Disconnected")))").tag(preferredOutputTag)
                        }
                        ForEach(audioManager.availableOutputDevices) { device in
                            HStack {
                                Image(systemName: device.iconName)
                                Text(device.name)
                            }
                            .tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    if let currentOut = audioManager.currentOutputDevice {
                        Button {
                            audioManager.setPreferredOutput(to: currentOut)
                        } label: {
                            Label(localized("Set Current as Default"), systemImage: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(audioManager.isPreferredOutput(currentOut))
                    }
                }

                Toggle(isOn: $audioManager.autoSwitchPreferredOutput) {
                    Text(localized("Automatically switch to default output device when connected"))
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func outputDeviceRow(_ device: AudioDeviceInfo) -> some View {
        let isActive = isCurrentOutput(device)
        let isPreferred = audioManager.isPreferredOutput(device)

        return HStack(spacing: 10) {
            Button {
                audioManager.selectOutputDevice(device)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: device.iconName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isActive ? Color.cyan : Color.secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 6) {
                            Text(device.name)
                                .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isActive {
                                Text(localized("Active"))
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.cyan.opacity(0.16)))
                                    .foregroundStyle(Color.cyan)
                            }

                            if isPreferred {
                                Text(localized("Default"))
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.blue.opacity(0.16)))
                                    .foregroundStyle(Color.blue)
                            }
                        }

                        Text(transportLabel(device.transportType))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                audioManager.setPreferredOutput(to: isPreferred ? nil : device)
            } label: {
                Image(systemName: isPreferred ? "pin.fill" : "pin")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isPreferred ? Color.blue : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPreferred ? Color.blue.opacity(0.14) : Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(isPreferred ? localized("Remove Default") : localized("Pin as Default"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.cyan.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Color.cyan.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var microphoneControlCard: some View {
        let lockedUID = audioManager.lockedMicrophoneUID ?? ""
        let pickerTag = !lockedUID.isEmpty ? lockedUID : (audioManager.currentInputDevice?.uid ?? "")
        let lockedIsDisconnected = !lockedUID.isEmpty
            && !audioManager.availableInputDevices.contains(where: { $0.uid == lockedUID })

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(localized("Microphone Control & Persistent Default"))
                            .font(.headline)

                        if audioManager.isMicrophoneLocked {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                Text(localized("Microphone Locked"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundStyle(Color.green)
                        }
                    }

                    Text(localized("Set your preferred interface (e.g., Maono USB) as the permanent default microphone so AirPods never hijack your input."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    audioManager.refreshDevices()
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Always Enforce Default Microphone When Connected"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(localized("When enabled, the selected microphone immediately assumes default input whenever connected and never loses priority to Bluetooth headsets."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $audioManager.isMicrophoneLocked)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 12) {
                    Text(localized("Default Microphone:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { pickerTag },
                        set: { newUID in
                            if let device = audioManager.availableInputDevices.first(where: { $0.uid == newUID }) {
                                audioManager.lockMicrophone(to: device)
                            }
                        }
                    )) {
                        if audioManager.availableInputDevices.isEmpty && !lockedIsDisconnected {
                            Text(localized("No microphones detected")).tag("")
                        } else {
                            if pickerTag.isEmpty {
                                Text(localized("Select Microphone")).tag("")
                            }
                            if lockedIsDisconnected {
                                let label = audioManager.lockedMicrophoneName ?? lockedUID
                                Text("\(label) (\(localized("Disconnected")))").tag(lockedUID)
                            }
                            ForEach(audioManager.availableInputDevices) { device in
                                HStack {
                                    Image(systemName: device.iconName)
                                    Text(device.name)
                                }
                                .tag(device.uid)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    if let current = audioManager.currentInputDevice {
                        Button {
                            audioManager.lockMicrophone(to: current)
                        } label: {
                            Label(localized("Lock Current"), systemImage: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        .disabled(audioManager.isMicrophoneLocked && audioManager.isLockedMicrophone(current))
                    }

                    if audioManager.isMicrophoneLocked {
                        Button {
                            audioManager.unlockMicrophone()
                        } label: {
                            Label(localized("Unlock"), systemImage: "lock.open")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if audioManager.isMicrophoneLocked,
                   let lockedName = audioManager.lockedMicrophoneName,
                   !audioManager.availableInputDevices.contains(where: { audioManager.isLockedMicrophone($0) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text(String(format: localized("Fixed microphone “%@” is currently unplugged. As soon as it is connected, MonoHub will automatically make it the default input."), lockedName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !audioManager.availableInputDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Available Microphones"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 5) {
                            ForEach(audioManager.availableInputDevices) { device in
                                inputDeviceRow(device)
                            }
                        }
                    }
                }

                Toggle(isOn: $audioManager.autoProtectMicrophoneOnBluetooth) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Prevent AirPods / Bluetooth from Hijacking Microphone"))
                            .font(.system(size: 12, weight: .medium))
                        Text(localized("Even if no specific microphone is locked, MonoHub prevents Bluetooth headphones from stealing the active microphone from your USB or Mac microphone."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Divider()

                HStack(spacing: 16) {
                    Text(localized("Input Gain & Level:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                    Button {
                        audioManager.toggleInputMute()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: audioManager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                            Text(audioManager.isInputMuted ? localized("Muted") : localized("Active"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(audioManager.isInputMuted ? Color.red : Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((audioManager.isInputMuted ? Color.red : Color.green).opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { Double(audioManager.isInputMuted ? 0 : audioManager.inputVolume) },
                            set: { audioManager.setInputVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .frame(maxWidth: 220)

                    Text("\(Int(round((audioManager.isInputMuted ? 0 : audioManager.inputVolume) * 100)))%")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(width: 42, alignment: .trailing)

                    HStack(spacing: 4) {
                        Text(localized("Signal:"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.18))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .yellow, .orange],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(3, geo.size.width * CGFloat(min(1.0, max(0.0, audioManager.micLevel)))))
                                    .animation(.linear(duration: 0.08), value: audioManager.micLevel)
                            }
                        }
                        .frame(width: 80, height: 7)
                    }
                }

                HStack(spacing: 12) {
                    Text(localized("Microphone Mode:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                    Text(microphoneModeLabel(audioManager.preferredMicrophoneMode))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                        .foregroundStyle(Color.purple)

                    Button {
                        audioManager.showVoiceIsolationPicker()
                    } label: {
                        Label(localized("Change Voice Isolation Mode…"), systemImage: "waveform.badge.mic")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func inputDeviceRow(_ device: AudioDeviceInfo) -> some View {
        let isActive = isCurrentInput(device)
        let isLocked = audioManager.isLockedMicrophone(device)

        return HStack(spacing: 10) {
            Button {
                audioManager.selectInputDevice(device, updateLockIfLocked: true)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: device.iconName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isActive ? Color.green : Color.secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 6) {
                            Text(device.name)
                                .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isActive {
                                Text(localized("Active"))
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.green.opacity(0.16)))
                                    .foregroundStyle(Color.green)
                            }

                            if isLocked {
                                HStack(spacing: 3) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                    Text(localized("Locked Default"))
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.green.opacity(0.14)))
                                .foregroundStyle(Color.green)
                            }
                        }

                        Text(transportLabel(device.transportType))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                audioManager.toggleMicrophoneLock(for: device)
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isLocked ? Color.green : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isLocked ? Color.green.opacity(0.14) : Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(isLocked ? localized("Unlock Microphone") : localized("Lock This Microphone"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.green.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Color.green.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func isCurrentOutput(_ device: AudioDeviceInfo) -> Bool {
        guard let current = audioManager.currentOutputDevice else { return false }
        return device.id == current.id || device.uid == current.uid
    }

    private func isCurrentInput(_ device: AudioDeviceInfo) -> Bool {
        guard let current = audioManager.currentInputDevice else { return false }
        return device.id == current.id || device.uid == current.uid
    }

    private func transportLabel(_ transport: AudioTransportType) -> String {
        switch transport {
        case .builtIn: return localized("Built-in")
        case .bluetooth: return localized("Bluetooth")
        case .hdmi: return localized("HDMI")
        case .displayPort: return localized("DisplayPort")
        case .usb: return localized("USB")
        case .airPlay: return localized("AirPlay")
        case .virtual: return localized("Virtual")
        case .continuity: return localized("Continuity")
        case .other: return localized("External")
        }
    }

    private func microphoneModeLabel(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .standard:
            return localized("Standard")
        case .voiceIsolation:
            return localized("Voice Isolation")
        case .wideSpectrum:
            return localized("Wide Spectrum")
        @unknown default:
            return localized("Standard")
        }
    }
}
