import SwiftUI
import AppKit
import CoreAudio

struct BluetoothQuickConnectView: View {
    @Bindable private var quickManager = BluetoothQuickConnectManager.shared
    @Bindable private var audioManager = AudioDeviceManager.shared
    private let btManager = BluetoothManager.shared

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                quickConnectCard
                audioRoutingCard
                hotkeySettingsCard
                pairedDevicesListCard
            }
            .padding(20)
        }
        .onAppear {
            btManager.refreshDevices(includeProfiler: true)
            audioManager.refreshDevices()
        }
    }

    private var quickConnectCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 52, height: 52)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(localized("1-Touch Fast Connection"))
                        .font(.headline)

                    if let favName = quickManager.favoriteDeviceName {
                        Text(favName)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundStyle(Color.blue)
                    }
                }

                Text(quickManager.lastStatusMessage ?? localized("Press ⌥ B or click the button beside to connect/disconnect instantly."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                quickManager.toggleQuickConnection()
            } label: {
                HStack(spacing: 6) {
                    if quickManager.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(localized("Toggle Connection (⌥ B)"))
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(quickManager.isConnecting)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var audioRoutingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(localized("Audio Routing & Fixed Microphone"))
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

                    Text(localized("Keep your USB microphone permanently fixed when connecting AirPods or Bluetooth headphones."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    HubNavigation.shared.selectedItem = .audioControl
                } label: {
                    Label(localized("Open Per-App Volume Mixer"), systemImage: "slider.horizontal.below.square.and.square.filled")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

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

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(Color.blue)
                            Text(localized("Fixed Default Microphone"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(localized("Whenever audio devices change, MonoHub automatically restores this microphone as active input."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $audioManager.isMicrophoneLocked)
                        .toggleStyle(.switch)
                }

                let lockedUID = audioManager.lockedMicrophoneUID ?? ""
                let micPickerTag = !lockedUID.isEmpty ? lockedUID : (audioManager.currentInputDevice?.uid ?? "")
                let lockedMicDisconnected = !lockedUID.isEmpty
                    && !audioManager.availableInputDevices.contains(where: { $0.uid == lockedUID })

                HStack(spacing: 12) {
                    Text(localized("Microphone:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { micPickerTag },
                        set: { newUID in
                            if let device = audioManager.availableInputDevices.first(where: { $0.uid == newUID }) {
                                audioManager.lockMicrophone(to: device)
                            }
                        }
                    )) {
                        if audioManager.availableInputDevices.isEmpty && !lockedMicDisconnected {
                            Text(localized("No microphones detected")).tag("")
                        } else {
                            if micPickerTag.isEmpty {
                                Text(localized("Select Microphone")).tag("")
                            }
                            if lockedMicDisconnected {
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
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(current.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if audioManager.isMicrophoneLocked,
                   let lockedName = audioManager.lockedMicrophoneName,
                   !audioManager.availableInputDevices.contains(where: { audioManager.isLockedMicrophone($0) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text(String(format: localized("Fixed microphone “%@” is disconnected. MonoHub will restore it as soon as it reconnects."), lockedName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                Toggle(isOn: $audioManager.autoProtectMicrophoneOnBluetooth) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Protect microphone when connecting Bluetooth headphones"))
                            .font(.system(size: 12))
                        Text(localized("Prevents macOS from switching your input to AirPods when connecting them."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 2)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .foregroundStyle(Color.purple)
                    Text(localized("Sound & Headphone Output"))
                        .font(.system(size: 13, weight: .semibold))
                }

                let activeOutputUID = audioManager.currentOutputDevice?.uid ?? ""
                let preferredOutputTag = audioManager.preferredOutputUID ?? ""
                let preferredOutputDisconnected = !preferredOutputTag.isEmpty
                    && !audioManager.availableOutputDevices.contains(where: { $0.uid == preferredOutputTag })

                HStack(spacing: 12) {
                    Text(localized("Current Output:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

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
                    Text(localized("Preferred Output:"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

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
                        if preferredOutputDisconnected {
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
                }

                Toggle(isOn: $audioManager.autoSwitchPreferredOutput) {
                    Text(localized("Automatically switch to preferred output when connected"))
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .padding(.top, 2)
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

    private var hotkeySettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("Global Connection Shortcut"), systemImage: "command")
                    .font(.headline)

                Spacer()

                Toggle("", isOn: $quickManager.isHotkeyEnabled)
                    .toggleStyle(.switch)
            }

            Text(localized("Press ⌥ B (Option + B) anywhere in macOS to connect or disconnect your favorite headphones/device without opening Settings."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(localized("Current shortcut:"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("⌥")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))

                    Text("B")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var pairedDevicesListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Paired Devices"))
                        .font(.headline)
                    Text(localized("Click the star to set as the quick shortcut device."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    btManager.refreshDevices(includeProfiler: true, force: true)
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            if btManager.allDevices.isEmpty {
                Text(localized("No paired Bluetooth devices found."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(btManager.allDevices) { device in
                        deviceRow(device)
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

    private func deviceRow(_ device: BluetoothDeviceInfo) -> some View {
        let isFavorite = (quickManager.favoriteDeviceAddress == device.address)

        return HStack(spacing: 12) {

            Button {
                if isFavorite {
                    quickManager.clearFavoriteDevice()
                } else {
                    quickManager.setFavoriteDevice(device)
                }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            Image(systemName: device.category.iconName)
                .font(.system(size: 14))
                .foregroundStyle(device.isConnected ? Color.green : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium))

                    if device.isConnected {
                        Text(localized("Connected"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
                }

                if let battery = device.primaryBattery {
                    HStack(spacing: 4) {
                        Image(systemName: device.isCharging ? "bolt.fill" : "battery.75percent")
                            .font(.system(size: 9))
                        Text("\(battery)%")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if device.isConnected {
                Button {
                    btManager.toggleConnection(for: device)
                } label: {
                    Text(localized("Disconnect"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    btManager.toggleConnection(for: device)
                } label: {
                    Text(localized("Connect"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
        )
    }
}
