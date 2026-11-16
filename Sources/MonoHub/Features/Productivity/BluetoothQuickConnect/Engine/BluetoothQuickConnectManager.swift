import Foundation
import AppKit
import IOBluetooth
import Carbon.HIToolbox
import Observation

@Observable
@MainActor
final class BluetoothQuickConnectManager {
    static let shared = BluetoothQuickConnectManager()

    var favoriteDeviceAddress: String? {
        didSet {
            UserDefaults.standard.set(favoriteDeviceAddress, forKey: Self.addressDefaultsKey)
        }
    }

    var favoriteDeviceName: String? {
        didSet {
            UserDefaults.standard.set(favoriteDeviceName, forKey: Self.nameDefaultsKey)
        }
    }

    var isHotkeyEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isHotkeyEnabled, forKey: Self.hotkeyEnabledDefaultsKey)
            updateHotkeyRegistration()
        }
    }

    private(set) var isConnecting: Bool = false
    private(set) var lastStatusMessage: String?

    @ObservationIgnored private(set) var isFeatureActive = false
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var eventHandlerRef: EventHandlerRef?

    nonisolated static let hotKeySignature: OSType = 0x4D425443
    nonisolated static let hotKeyID: UInt32 = 1

    private static let addressDefaultsKey = "MonoHub_BTQuick_Address"
    private static let nameDefaultsKey = "MonoHub_BTQuick_Name"
    private static let hotkeyEnabledDefaultsKey = "MonoHub_BTQuick_HotkeyEnabled"

    private static func normalizeAddress(_ addr: String) -> String {
        addr.replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init() {
        self.favoriteDeviceAddress = UserDefaults.standard.string(forKey: Self.addressDefaultsKey)
        self.favoriteDeviceName = UserDefaults.standard.string(forKey: Self.nameDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.hotkeyEnabledDefaultsKey) != nil {
            self.isHotkeyEnabled = UserDefaults.standard.bool(forKey: Self.hotkeyEnabledDefaultsKey)
        }
    }

    func start() {
        isFeatureActive = true
        updateHotkeyRegistration()
        if favoriteDeviceAddress == nil {
            autoPickDefaultAudioDevice()
        }
    }

    func stop() {
        isFeatureActive = false
        unregisterHotKey()
    }

    func setFavoriteDevice(_ device: BluetoothDeviceInfo) {
        self.favoriteDeviceAddress = device.address
        self.favoriteDeviceName = device.name
        self.lastStatusMessage = String(format: localized("Favorite device: %@"), device.name)
    }

    func clearFavoriteDevice() {
        self.favoriteDeviceAddress = nil
        self.favoriteDeviceName = nil
    }

    private func autoPickDefaultAudioDevice() {
        guard !AppInfo.isRunningTests else { return }
        let devices = BluetoothManager.shared.allDevices
        if let audioDev = devices.first(where: { dev in
            if dev.category == .headphones || dev.category == .airpods { return true }
            let lower = dev.name.lowercased()
            return lower.contains("airpods") || lower.contains("beats") || lower.contains("sony")
        }) {
            self.favoriteDeviceAddress = audioDev.address
            self.favoriteDeviceName = audioDev.name
        }
    }

    func toggleQuickConnection() {
        guard let address = favoriteDeviceAddress ?? BluetoothManager.shared.allDevices.first?.address else {
            lastStatusMessage = localized("No Bluetooth device configured")
            return
        }

        let name = favoriteDeviceName ?? localized("Bluetooth Device")
        let normAddr = Self.normalizeAddress(address)

        guard !AppInfo.isRunningTests else {
            isConnecting = false
            lastStatusMessage = "Toggled \(name)"
            return
        }

        guard let device = IOBluetoothDevice(addressString: normAddr) else {
            lastStatusMessage = localized("Device not found")
            return
        }

        let currentlyConnected = device.isConnected()

        if currentlyConnected {
            lastStatusMessage = String(format: localized("Disconnecting %@…"), name)
            _ = device.closeConnection()
            NotchHaptics.tap()
            lastStatusMessage = String(format: localized("%@ Disconnected"), name)
            BluetoothManager.shared.refreshDevices(force: true)
        } else {
            isConnecting = true
            lastStatusMessage = String(format: localized("Connecting to %@…"), name)
            NotchHaptics.tap()

            Task { [weak self] in
                _ = device.openConnection()

                for _ in 0..<8 {
                    try? await Task.sleep(for: .milliseconds(400))
                    if device.isConnected() {
                        break
                    }
                }

                var matchedOutput: AudioDeviceInfo?
                for _ in 0..<10 {
                    AudioDeviceManager.shared.refreshDevices()
                    let availableOutputs = AudioDeviceManager.shared.availableOutputDevices
                    if let matched = availableOutputs.first(where: {
                        $0.uid.lowercased().replacingOccurrences(of: ":", with: "-").contains(normAddr) ||
                        $0.name.localizedCaseInsensitiveContains(name)
                    }) {
                        matchedOutput = matched
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }

                if let matchedOutput {
                    AudioDeviceManager.shared.selectOutputDevice(matchedOutput)
                }

                if AudioDeviceManager.shared.isMicrophoneLocked {
                    AudioDeviceManager.shared.enforceMicrophoneLockIfNeeded()
                }
                if AudioDeviceManager.shared.autoProtectMicrophoneOnBluetooth {
                    AudioDeviceManager.shared.enforceBluetoothMicProtectionIfNeeded()
                }

                self?.isConnecting = false
                self?.lastStatusMessage = device.isConnected() ?
                    String(format: localized("%@ Connected"), name) :
                    String(format: localized("Failed to connect %@"), name)

                BluetoothManager.shared.refreshDevices(force: true)
            }
        }
    }

    private func updateHotkeyRegistration() {
        guard !AppInfo.isRunningTests else { return }
        if isFeatureActive && isHotkeyEnabled {
            registerHotKey()
        } else {
            unregisterHotKey()
        }
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )

            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                btQuickHotKeyHandler,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
            guard status == noErr else { return }
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}

nonisolated private func btQuickHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamType(typeEventHotKeyID),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr,
          hotKeyID.signature == BluetoothQuickConnectManager.hotKeySignature,
          hotKeyID.id == BluetoothQuickConnectManager.hotKeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<BluetoothQuickConnectManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        guard manager.isFeatureActive else { return }
        manager.toggleQuickConnection()
    }

    return noErr
}
