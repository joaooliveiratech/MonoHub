import AppKit
import CoreAudio
import AVFoundation
import Foundation
import IOBluetooth
import Observation
import Synchronization

nonisolated func audioHALDeviceListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    let selectors = (0..<Int(inNumberAddresses)).map { inAddresses[$0].mSelector }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            AudioDeviceManager.shared.handleHALPropertyChanged(objectID: inObjectID, selectors: selectors)
        }
    }
    return noErr
}

@Observable
@MainActor
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    private(set) var availableOutputDevices: [AudioDeviceInfo] = []
    private(set) var availableInputDevices: [AudioDeviceInfo] = []
    private(set) var currentOutputDevice: AudioDeviceInfo?
    private(set) var currentInputDevice: AudioDeviceInfo?
    private(set) var lastNonBluetoothInputDevice: AudioDeviceInfo?
    private(set) var isInputMuted: Bool = false
    private(set) var inputVolume: Float = 1.0
    private(set) var micLevel: Float = 0.0
    private(set) var preferredMicrophoneMode: AVCaptureDevice.MicrophoneMode = .standard

    var isMicrophoneLocked: Bool = false {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(isMicrophoneLocked, forKey: Self.microphoneLockedDefaultsKey)
            }
            if isMicrophoneLocked {
                if (lockedMicrophoneUID ?? "").isEmpty && (lockedMicrophoneName ?? "").isEmpty {
                    let fallback = lastNonBluetoothInputDevice
                        ?? currentInputDevice
                        ?? Self.preferredNonBluetoothMicrophone(from: availableInputDevices)
                        ?? availableInputDevices.first
                    if let fallback {
                        lockedMicrophoneUID = fallback.uid
                        lockedMicrophoneName = fallback.name
                    }
                }
                enforceMicrophoneLockIfNeeded()
            } else {
                micGuardTask?.cancel()
                micGuardTask = nil
            }
        }
    }

    var lockedMicrophoneUID: String? {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(lockedMicrophoneUID, forKey: Self.lockedMicrophoneUIDDefaultsKey)
            }
        }
    }

    var lockedMicrophoneName: String? {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(lockedMicrophoneName, forKey: Self.lockedMicrophoneNameDefaultsKey)
            }
        }
    }

    var autoProtectMicrophoneOnBluetooth: Bool = true {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(autoProtectMicrophoneOnBluetooth, forKey: Self.autoProtectMicOnBluetoothDefaultsKey)
            }
            if autoProtectMicrophoneOnBluetooth {
                enforceBluetoothMicProtectionIfNeeded()
            }
        }
    }

    var preferredOutputUID: String? {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(preferredOutputUID, forKey: Self.preferredOutputUIDDefaultsKey)
            }
        }
    }

    var preferredOutputName: String? {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(preferredOutputName, forKey: Self.preferredOutputNameDefaultsKey)
            }
        }
    }

    var autoSwitchPreferredOutput: Bool = true {
        didSet {
            if !AppInfo.isRunningTests {
                UserDefaults.standard.set(autoSwitchPreferredOutput, forKey: Self.autoSwitchPreferredOutputDefaultsKey)
            }
        }
    }

    var isCurrentMicrophoneLocked: Bool {
        guard isMicrophoneLocked, let current = currentInputDevice else { return false }
        return Self.device(current, matchesUID: lockedMicrophoneUID, name: lockedMicrophoneName)
    }

    var isCurrentOutputPreferred: Bool {
        guard let current = currentOutputDevice else { return false }
        return isPreferredOutput(current)
    }

    var isVoiceIsolationActive: Bool {
        preferredMicrophoneMode == .voiceIsolation
    }

    func isPreferredOutput(_ device: AudioDeviceInfo) -> Bool {
        Self.device(device, matchesUID: preferredOutputUID, name: preferredOutputName)
    }

    func isLockedMicrophone(_ device: AudioDeviceInfo) -> Bool {
        guard isMicrophoneLocked else { return false }
        return Self.device(device, matchesUID: lockedMicrophoneUID, name: lockedMicrophoneName)
    }

    private static let microphoneLockedDefaultsKey = "MonoHub_IsMicrophoneLocked"
    private static let lockedMicrophoneUIDDefaultsKey = "MonoHub_LockedMicrophoneUID"
    private static let lockedMicrophoneNameDefaultsKey = "MonoHub_LockedMicrophoneName"
    private static let autoProtectMicOnBluetoothDefaultsKey = "MonoHub_AutoProtectMicOnBluetooth"
    private static let preferredOutputUIDDefaultsKey = "MonoHub_PreferredOutputUID"
    private static let preferredOutputNameDefaultsKey = "MonoHub_PreferredOutputName"
    private static let autoSwitchPreferredOutputDefaultsKey = "MonoHub_AutoSwitchPreferredOutput"

    @ObservationIgnored private(set) var isMonitoring = false
    @ObservationIgnored private var monitoringClients: Set<String> = []
    @ObservationIgnored private var currentInputDeviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var savedNonZeroInputVolume: Float = 1.0
    @ObservationIgnored private var activeConsumers: Set<String> = []
    @ObservationIgnored private let meterEngine = AudioLevelMeterEngine()
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var smoothingLevel: Float = 0.0

    @ObservationIgnored private var knownOutputDeviceUIDs: Set<String> = []
    @ObservationIgnored private var knownInputDeviceUIDs: Set<String> = []
    @ObservationIgnored private var previousActiveOutputUID: String?
    @ObservationIgnored private var hasCompletedInitialDeviceScan = false
    @ObservationIgnored private var targetOutputUID: String?
    @ObservationIgnored private var targetOutputName: String?
    @ObservationIgnored private var outputGuardUntil: Date = .distantPast
    @ObservationIgnored private var lastManualOutputSelectionAt: Date = .distantPast
    @ObservationIgnored private var outputGuardTask: Task<Void, Never>?
    @ObservationIgnored private var micGuardTask: Task<Void, Never>?
    @ObservationIgnored private var userSelectedBluetoothInputUID: String?
    @ObservationIgnored private var lastLocalInputWriteAt: Date = .distantPast
    @ObservationIgnored private var isSettingInputState = false
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isMeterEngineStarted = false
    @ObservationIgnored private var meterEngineDeviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var lastNotifiedOutputUID: String?
    @ObservationIgnored private var lastNotifiedOutputID = AudioObjectID(kAudioObjectUnknown)

    private init() {
        let defaults = UserDefaults.standard
        self.isMicrophoneLocked = defaults.bool(forKey: Self.microphoneLockedDefaultsKey)
        self.lockedMicrophoneUID = defaults.string(forKey: Self.lockedMicrophoneUIDDefaultsKey)
        self.lockedMicrophoneName = defaults.string(forKey: Self.lockedMicrophoneNameDefaultsKey)
        if defaults.object(forKey: Self.autoProtectMicOnBluetoothDefaultsKey) != nil {
            self.autoProtectMicrophoneOnBluetooth = defaults.bool(forKey: Self.autoProtectMicOnBluetoothDefaultsKey)
        } else {
            self.autoProtectMicrophoneOnBluetooth = true
        }
        self.preferredOutputUID = defaults.string(forKey: Self.preferredOutputUIDDefaultsKey)
        self.preferredOutputName = defaults.string(forKey: Self.preferredOutputNameDefaultsKey)
        if defaults.object(forKey: Self.autoSwitchPreferredOutputDefaultsKey) != nil {
            self.autoSwitchPreferredOutput = defaults.bool(forKey: Self.autoSwitchPreferredOutputDefaultsKey)
        } else {
            self.autoSwitchPreferredOutput = true
        }
    }

    func startMonitoring(client: String = "general") {
        monitoringClients.insert(client)
        guard !isMonitoring else { return }
        guard !AppInfo.isRunningTests else {
            isMonitoring = true
            return
        }

        var devicesAddr = Self.devicesAddress
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, audioHALDeviceListenerProc, nil)

        var defaultOutAddr = Self.defaultOutputDeviceAddress
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutAddr, audioHALDeviceListenerProc, nil)

        var defaultInAddr = Self.defaultInputDeviceAddress
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultInAddr, audioHALDeviceListenerProc, nil)

        isMonitoring = true
        refreshDevices()
    }

    func stopMonitoring(client: String = "general") {
        monitoringClients.remove(client)
        guard monitoringClients.isEmpty else { return }
        guard isMonitoring else { return }
        guard !AppInfo.isRunningTests else {
            isMonitoring = false
            return
        }

        var devicesAddr = Self.devicesAddress
        _ = AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, audioHALDeviceListenerProc, nil)

        var defaultOutAddr = Self.defaultOutputDeviceAddress
        _ = AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutAddr, audioHALDeviceListenerProc, nil)

        var defaultInAddr = Self.defaultInputDeviceAddress
        _ = AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultInAddr, audioHALDeviceListenerProc, nil)

        detachInputDeviceListeners(from: currentInputDeviceID)
        currentInputDeviceID = AudioObjectID(kAudioObjectUnknown)

        outputGuardTask?.cancel()
        outputGuardTask = nil
        micGuardTask?.cancel()
        micGuardTask = nil

        stopMeterEngineIfRunning()
        isMonitoring = false
    }

    func refreshDevices() {
        guard !AppInfo.isRunningTests else { return }
        guard !isRefreshing else { return }

        let scanned = Self.scanHALDevices()
        let defOutID = Self.defaultOutputDeviceID()
        let defInID = Self.defaultInputDeviceID()
        processDeviceRefresh(
            outputs: scanned.outputs,
            inputs: scanned.inputs,
            halDefaultOutputID: defOutID,
            halDefaultInputID: defInID
        )
    }

    func handleHALPropertyChanged() {
        guard isMonitoring else { return }
        refreshDevices()
    }

    func handleHALPropertyChanged(objectID: AudioObjectID, selectors: [AudioObjectPropertySelector]) {
        guard isMonitoring else { return }
        if objectID == AudioObjectID(kAudioObjectSystemObject) {
            refreshDevices()
            return
        }
        if objectID == currentInputDeviceID && currentInputDeviceID != kAudioObjectUnknown {
            if !isSettingInputState && Date().timeIntervalSince(lastLocalInputWriteAt) >= 0.15 {
                readInputState()
            }
            return
        }
        if selectors.contains(kAudioHardwarePropertyDevices) ||
           selectors.contains(kAudioHardwarePropertyDefaultOutputDevice) ||
           selectors.contains(kAudioHardwarePropertyDefaultInputDevice) {
            refreshDevices()
        }
    }

    func selectOutputDevice(_ device: AudioDeviceInfo) {
        applyOutputDeviceSelection(device, isManualSelection: true)
    }

    private func applyOutputDeviceSelection(_ device: AudioDeviceInfo, isManualSelection: Bool) {
        if isManualSelection {
            lastManualOutputSelectionAt = Date()
        }

        guard !AppInfo.isRunningTests else {
            let resolved = availableOutputDevices.first(where: { $0.uid == device.uid || $0.id == device.id }) ?? device
            if currentOutputDevice != resolved {
                currentOutputDevice = resolved
            }
            previousActiveOutputUID = resolved.uid
            if isManualSelection || Self.isBluetoothAudioDevice(resolved) {
                armOutputGuard(for: resolved)
            }
            notifyOutputDeviceChangedIfNeeded(to: resolved)
            return
        }

        NotchWindowController.shared.navigationGraceUntil = Date().addingTimeInterval(2.5)

        var resolved = Self.resolveLiveDevice(device, in: availableOutputDevices)
        if !Self.isDeviceAlive(id: resolved.id) {
            let scanned = Self.scanHALDevices()
            updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)
            resolved = Self.resolveLiveDevice(device, in: scanned.outputs)
        }

        if isManualSelection || targetOutputUID != resolved.uid {
            armOutputGuard(for: resolved)
        }

        var didSet = Self.setSystemDefaultOutputDevice(id: resolved.id)

        if !didSet {
            let scanned = Self.scanHALDevices()
            updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)
            let fresh = Self.resolveLiveDevice(resolved, in: scanned.outputs)
            resolved = fresh
            if isManualSelection || targetOutputUID != resolved.uid {
                armOutputGuard(for: resolved)
            }
            didSet = Self.setSystemDefaultOutputDevice(id: resolved.id)
        }

        let actualDefaultID = Self.defaultOutputDeviceID()

        if Self.isBluetoothAudioDevice(resolved) && !didSet {
            Self.ensureBluetoothAudioConnected(for: resolved)
        }

        if didSet || actualDefaultID == resolved.id {
            if currentOutputDevice != resolved {
                currentOutputDevice = resolved
            }
            previousActiveOutputUID = resolved.uid
            notifyOutputDeviceChangedIfNeeded(to: resolved)
        } else if let actual = availableOutputDevices.first(where: { $0.id == actualDefaultID }) {
            if currentOutputDevice != actual {
                currentOutputDevice = actual
            }
            previousActiveOutputUID = actual.uid
        }

        if isManualSelection || outputGuardTask == nil {
            scheduleOutputGuardRechecks(targetUID: resolved.uid, targetName: resolved.name)
        }
    }

    func selectInputDevice(_ device: AudioDeviceInfo, updateLockIfLocked: Bool = false) {
        if Self.isBluetoothAudioDevice(device) {
            if !isMicrophoneLocked || updateLockIfLocked {
                userSelectedBluetoothInputUID = device.uid
            }
        } else {
            userSelectedBluetoothInputUID = nil
            if lastNonBluetoothInputDevice != device {
                lastNonBluetoothInputDevice = device
            }
        }

        if updateLockIfLocked && isMicrophoneLocked {
            self.lockedMicrophoneUID = device.uid
            self.lockedMicrophoneName = device.name
        }

        guard !AppInfo.isRunningTests else {
            let resolved = availableInputDevices.first(where: { $0.uid == device.uid || $0.id == device.id }) ?? device
            if currentInputDevice != resolved {
                currentInputDevice = resolved
            }
            return
        }

        NotchWindowController.shared.navigationGraceUntil = Date().addingTimeInterval(2.5)

        var resolved = Self.resolveLiveDevice(device, in: availableInputDevices)
        if !Self.isDeviceAlive(id: resolved.id) {
            let scanned = Self.scanHALDevices()
            updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)
            resolved = Self.resolveLiveDevice(device, in: scanned.inputs)
        }

        var status = Self.setSystemDefaultInputDevice(id: resolved.id)
        if status != noErr {
            let scanned = Self.scanHALDevices()
            updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)
            resolved = Self.resolveLiveDevice(resolved, in: scanned.inputs)
            status = Self.setSystemDefaultInputDevice(id: resolved.id)
        }

        if status == noErr {
            if currentInputDevice != resolved {
                currentInputDevice = resolved
            }
            syncInputDeviceListenersIfNeeded(to: resolved.id)
        }
    }

    func lockMicrophone(to device: AudioDeviceInfo) {
        self.lockedMicrophoneUID = device.uid
        self.lockedMicrophoneName = device.name
        self.isMicrophoneLocked = true
        if !Self.isBluetoothAudioDevice(device) {
            self.lastNonBluetoothInputDevice = device
            self.userSelectedBluetoothInputUID = nil
        }
        if currentInputDevice?.id != device.id || currentInputDevice?.uid != device.uid {
            selectInputDevice(device)
        } else {
            scheduleMicrophoneGuardRechecks(targetUID: device.uid, targetName: device.name)
        }
    }

    func unlockMicrophone() {
        micGuardTask?.cancel()
        micGuardTask = nil
        self.isMicrophoneLocked = false
    }

    func toggleMicrophoneLock(for device: AudioDeviceInfo? = nil) {
        if isMicrophoneLocked {
            if let device, !Self.device(device, matchesUID: lockedMicrophoneUID, name: lockedMicrophoneName) {
                lockMicrophone(to: device)
            } else {
                unlockMicrophone()
            }
        } else {
            if let target = device ?? currentInputDevice ?? availableInputDevices.first {
                lockMicrophone(to: target)
            }
        }
    }

    func setPreferredOutput(to device: AudioDeviceInfo?) {
        self.preferredOutputUID = device?.uid
        self.preferredOutputName = device?.name
        if let device {
            applyOutputDeviceSelection(device, isManualSelection: true)
        }
    }

    func enforceMicrophoneLockIfNeeded() {
        guard isMicrophoneLocked else { return }
        let targetUID = lockedMicrophoneUID ?? ""
        let targetName = lockedMicrophoneName ?? ""
        guard !targetUID.isEmpty || !targetName.isEmpty else { return }

        guard let matched = availableInputDevices.first(where: {
            Self.device($0, matchesUID: targetUID, name: targetName)
        }) else {
            return
        }

        let halDefaultID = AppInfo.isRunningTests ? (currentInputDevice?.id ?? matched.id) : Self.defaultInputDeviceID()
        let alreadyMatches = (currentInputDevice?.uid == matched.uid) && (halDefaultID == matched.id)

        if !alreadyMatches {
            if let currentOut = currentOutputDevice, Self.isBluetoothAudioDevice(currentOut) {
                armOutputGuard(for: currentOut)
                if !AppInfo.isRunningTests {
                    scheduleOutputGuardRechecks(targetUID: currentOut.uid, targetName: currentOut.name)
                }
            }
            selectInputDevice(matched)
            scheduleMicrophoneGuardRechecks(targetUID: matched.uid, targetName: matched.name)
        }
    }

    func enforceBluetoothMicProtectionIfNeeded() {
        guard autoProtectMicrophoneOnBluetooth else { return }

        if isMicrophoneLocked,
           availableInputDevices.contains(where: { Self.device($0, matchesUID: lockedMicrophoneUID, name: lockedMicrophoneName) }) {
            return
        }

        guard let current = currentInputDevice, Self.isBluetoothAudioDevice(current) else {
            return
        }

        if !isMicrophoneLocked, userSelectedBluetoothInputUID == current.uid {
            return
        }

        let fallback: AudioDeviceInfo? = {
            if let last = lastNonBluetoothInputDevice,
               let stillConnected = availableInputDevices.first(where: { $0.uid == last.uid || $0.id == last.id }),
               !Self.isBluetoothAudioDevice(stillConnected) {
                return stillConnected
            }
            return Self.preferredNonBluetoothMicrophone(from: availableInputDevices)
        }()

        if let fallback, fallback.id != current.id || fallback.uid != current.uid {
            if let currentOut = currentOutputDevice, Self.isBluetoothAudioDevice(currentOut) {
                armOutputGuard(for: currentOut)
                if !AppInfo.isRunningTests {
                    scheduleOutputGuardRechecks(targetUID: currentOut.uid, targetName: currentOut.name)
                }
            }
            selectInputDevice(fallback)
            scheduleMicrophoneGuardRechecks(targetUID: fallback.uid, targetName: fallback.name)
        }
    }

    func checkPreferredOutputIfNeeded() {
        guard autoSwitchPreferredOutput else { return }
        let targetUID = preferredOutputUID ?? ""
        let targetName = preferredOutputName ?? ""
        guard !targetUID.isEmpty || !targetName.isEmpty else { return }

        if let current = currentOutputDevice, Self.device(current, matchesUID: targetUID, name: targetName) {
            return
        }

        if let matched = availableOutputDevices.first(where: {
            Self.device($0, matchesUID: targetUID, name: targetName)
        }) {
            applyOutputDeviceSelection(matched, isManualSelection: false)
        }
    }

    private func updateDeviceLists(outputs: [AudioDeviceInfo], inputs: [AudioDeviceInfo]) {
        if availableOutputDevices != outputs {
            availableOutputDevices = outputs
        }
        if availableInputDevices != inputs {
            availableInputDevices = inputs
        }
    }

    private func notifyOutputDeviceChangedIfNeeded(to device: AudioDeviceInfo) {
        guard device.uid != lastNotifiedOutputUID || device.id != lastNotifiedOutputID else { return }
        lastNotifiedOutputUID = device.uid
        lastNotifiedOutputID = device.id
        if !AppInfo.isRunningTests {
            AudioVolumeManager.shared.handleOutputDeviceChanged(to: device.id)
        }
        AudioProcessVolumeManager.shared.handleOutputDeviceChanged(to: device.uid)
    }

    private func processDeviceRefresh(
        outputs: [AudioDeviceInfo],
        inputs: [AudioDeviceInfo],
        halDefaultOutputID: AudioDeviceID,
        halDefaultInputID: AudioDeviceID
    ) {
        isRefreshing = true
        defer { isRefreshing = false }

        let isInitialScan = !hasCompletedInitialDeviceScan
        let previousOutputUIDs = knownOutputDeviceUIDs
        let initialPrevOutputUID = previousActiveOutputUID ?? currentOutputDevice?.uid
        let initialPrevOutputID = currentOutputDevice?.id ?? AudioObjectID(kAudioObjectUnknown)

        updateDeviceLists(outputs: outputs, inputs: inputs)
        knownOutputDeviceUIDs = Set(outputs.map(\.uid))
        knownInputDeviceUIDs = Set(inputs.map(\.uid))
        hasCompletedInitialDeviceScan = true

        let newlyConnectedOutputs = isInitialScan ? [] : outputs.filter { !previousOutputUIDs.contains($0.uid) }
        let previousOutputStillAvailable = initialPrevOutputUID.map { uid in
            outputs.contains(where: { $0.uid == uid })
        } ?? false
        let previousOutputDisconnected = !isInitialScan && initialPrevOutputUID != nil && !previousOutputStillAvailable

        if let selectedBT = userSelectedBluetoothInputUID,
           !inputs.contains(where: { $0.uid == selectedBT }) {
            userSelectedBluetoothInputUID = nil
        }

        let halOutDevice = outputs.first(where: { $0.id == halDefaultOutputID })
        let halInDevice = inputs.first(where: { $0.id == halDefaultInputID })

        if currentOutputDevice != halOutDevice {
            currentOutputDevice = halOutDevice
        }
        if currentInputDevice != halInDevice {
            currentInputDevice = halInDevice
        }

        if let halInDevice, !Self.isBluetoothAudioDevice(halInDevice) {
            if lastNonBluetoothInputDevice != halInDevice {
                lastNonBluetoothInputDevice = halInDevice
            }
        } else if lastNonBluetoothInputDevice == nil || !inputs.contains(where: { $0.uid == lastNonBluetoothInputDevice?.uid }) {
            let fallbackMic = Self.preferredNonBluetoothMicrophone(from: inputs)
            if lastNonBluetoothInputDevice != fallbackMic {
                lastNonBluetoothInputDevice = fallbackMic
            }
        }

        let now = Date()
        if now < outputGuardUntil, let targetUID = targetOutputUID {
            if let guarded = outputs.first(where: { Self.device($0, matchesUID: targetUID, name: targetOutputName) }) {
                if halOutDevice?.uid != guarded.uid || halOutDevice?.id != guarded.id {
                    applyOutputDeviceSelection(guarded, isManualSelection: false)
                }
            } else {
                clearOutputGuard()
            }
        } else if let halOutDevice,
                  Self.isBluetoothAudioDevice(halOutDevice),
                  (halOutDevice.uid != initialPrevOutputUID || newlyConnectedOutputs.contains(where: { $0.uid == halOutDevice.uid })) {
            armOutputGuard(for: halOutDevice)
            if !AppInfo.isRunningTests && outputGuardTask == nil {
                scheduleOutputGuardRechecks(targetUID: halOutDevice.uid, targetName: halOutDevice.name)
            }
        }

        let preferredJustConnected = autoSwitchPreferredOutput && newlyConnectedOutputs.contains(where: {
            Self.device($0, matchesUID: preferredOutputUID, name: preferredOutputName)
        })
        let withinManualCooldown = now.timeIntervalSince(lastManualOutputSelectionAt) < 2.0

        if isInitialScan || previousOutputDisconnected || (!withinManualCooldown && preferredJustConnected) {
            checkPreferredOutputIfNeeded()
        }

        if let activeOut = currentOutputDevice {
            previousActiveOutputUID = activeOut.uid
            if (activeOut.uid != initialPrevOutputUID || activeOut.id != initialPrevOutputID)
                && (activeOut.uid != lastNotifiedOutputUID || activeOut.id != lastNotifiedOutputID) {
                notifyOutputDeviceChangedIfNeeded(to: activeOut)
            }
        } else if initialPrevOutputUID != nil {
            previousActiveOutputUID = nil
            if lastNotifiedOutputUID != nil {
                lastNotifiedOutputUID = nil
                lastNotifiedOutputID = AudioObjectID(kAudioObjectUnknown)
                AudioProcessVolumeManager.shared.handleOutputDeviceChanged(to: nil)
            }
        }

        enforceMicrophoneLockIfNeeded()
        enforceBluetoothMicProtectionIfNeeded()

        if !AppInfo.isRunningTests {
            let finalInID = currentInputDevice?.id ?? AudioObjectID(kAudioObjectUnknown)
            syncInputDeviceListenersIfNeeded(to: finalInID)
            readInputState()
            refreshMicrophoneMode()
        }
    }

    private func armOutputGuard(for device: AudioDeviceInfo) {
        targetOutputUID = device.uid
        targetOutputName = device.name
        outputGuardUntil = Date().addingTimeInterval(3.5)
    }

    private func clearOutputGuard() {
        targetOutputUID = nil
        targetOutputName = nil
        outputGuardUntil = .distantPast
        outputGuardTask?.cancel()
        outputGuardTask = nil
    }

    private func scheduleOutputGuardRechecks(targetUID: String, targetName: String) {
        guard !AppInfo.isRunningTests else { return }
        outputGuardTask?.cancel()
        outputGuardTask = Task { @MainActor [weak self] in
            let intervalsMs: [UInt64] = [150, 300, 550, 800, 1200]
            for ms in intervalsMs {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled, let self else { return }
                guard Date() < self.outputGuardUntil, self.targetOutputUID == targetUID else { return }
                self.recheckGuardedOutput(targetUID: targetUID, targetName: targetName)
            }
        }
    }

    private func recheckGuardedOutput(targetUID: String, targetName: String) {
        guard Date() < outputGuardUntil, targetOutputUID == targetUID else { return }
        let scanned = Self.scanHALDevices()
        updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)

        guard let target = scanned.outputs.first(where: { Self.device($0, matchesUID: targetUID, name: targetName) }) else {
            return
        }

        let actualHALDefault = Self.defaultOutputDeviceID()
        if actualHALDefault != target.id {
            _ = Self.setSystemDefaultOutputDevice(id: target.id)
            let updatedHALDefault = Self.defaultOutputDeviceID()
            if updatedHALDefault == target.id {
                if currentOutputDevice != target {
                    currentOutputDevice = target
                }
                previousActiveOutputUID = target.uid
                notifyOutputDeviceChangedIfNeeded(to: target)
            } else if Self.isBluetoothAudioDevice(target) {
                Self.ensureBluetoothAudioConnected(for: target)
            }
        } else if currentOutputDevice?.uid != target.uid || currentOutputDevice?.id != target.id {
            currentOutputDevice = target
            previousActiveOutputUID = target.uid
        }
    }

    private func scheduleMicrophoneGuardRechecks(targetUID: String, targetName: String) {
        guard !AppInfo.isRunningTests else { return }
        micGuardTask?.cancel()
        micGuardTask = Task { @MainActor [weak self] in
            let intervalsMs: [UInt64] = [150, 300, 550, 1000, 1500, 1500]
            for ms in intervalsMs {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled, let self else { return }
                guard self.isMicrophoneLocked || self.autoProtectMicrophoneOnBluetooth else { return }
                self.recheckLockedMicrophone(targetUID: targetUID, targetName: targetName)
            }
        }
    }

    private func recheckLockedMicrophone(targetUID: String, targetName: String) {
        guard isMicrophoneLocked || autoProtectMicrophoneOnBluetooth else { return }
        if !isMicrophoneLocked,
           let selectedBT = userSelectedBluetoothInputUID,
           currentInputDevice?.uid == selectedBT {
            return
        }

        let scanned = Self.scanHALDevices()
        updateDeviceLists(outputs: scanned.outputs, inputs: scanned.inputs)

        guard let matched = scanned.inputs.first(where: { Self.device($0, matchesUID: targetUID, name: targetName) }) else {
            return
        }

        let actualHALDefault = Self.defaultInputDeviceID()
        if actualHALDefault != matched.id || currentInputDevice?.uid != matched.uid {
            if let currentOut = currentOutputDevice, Self.isBluetoothAudioDevice(currentOut) {
                armOutputGuard(for: currentOut)
                scheduleOutputGuardRechecks(targetUID: currentOut.uid, targetName: currentOut.name)
            }
            selectInputDevice(matched)
        }
    }

    private func syncInputDeviceListenersIfNeeded(to deviceID: AudioObjectID) {
        if deviceID != currentInputDeviceID {
            detachInputDeviceListeners(from: currentInputDeviceID)
            currentInputDeviceID = deviceID
            attachInputDeviceListeners(to: deviceID)
            readInputState()
        }
        if !isMeteringEnabledForActiveConsumers || shouldAvoidStartingMeterOnProtectedBluetoothMic {
            stopMeterEngineIfRunning()
        } else {
            startMeterEngineIfNeeded(for: deviceID)
        }
    }

    private var isMeteringEnabledForActiveConsumers: Bool {
        !activeConsumers.isEmpty && NotchPreferences.shared.musicEnableMicLevelMeter && !NotchWindowController.shared.isDisplayAsleep
    }

    private var shouldAvoidStartingMeterOnProtectedBluetoothMic: Bool {
        guard let currentIn = currentInputDevice, Self.isBluetoothAudioDevice(currentIn) else {
            return false
        }
        if isMicrophoneLocked {
            return !Self.device(currentIn, matchesUID: lockedMicrophoneUID, name: lockedMicrophoneName)
        }
        if autoProtectMicrophoneOnBluetooth && userSelectedBluetoothInputUID != currentIn.uid {
            return Self.preferredNonBluetoothMicrophone(from: availableInputDevices) != nil
        }
        return false
    }

    private func startMeterEngineIfNeeded(for deviceID: AudioObjectID) {
        guard !AppInfo.isRunningTests else { return }
        guard isMeteringEnabledForActiveConsumers else { return }
        guard !shouldAvoidStartingMeterOnProtectedBluetoothMic else {
            stopMeterEngineIfRunning()
            return
        }

        let targetDeviceID = deviceID != kAudioObjectUnknown ? deviceID : Self.defaultInputDeviceID()
        guard targetDeviceID != kAudioObjectUnknown else { return }
        if isMeterEngineStarted && meterEngineDeviceID == targetDeviceID {
            ensureMeterTimerRunning()
            return
        }

        isMeterEngineStarted = true
        meterEngineDeviceID = targetDeviceID
        let engine = meterEngine
        DispatchQueue.global(qos: .userInitiated).async { [weak self, engine] in
            let started = engine.start(deviceID: targetDeviceID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard started else {
                    if self.meterEngineDeviceID == targetDeviceID {
                        self.isMeterEngineStarted = false
                        self.meterEngineDeviceID = AudioObjectID(kAudioObjectUnknown)
                    }
                    return
                }
                guard self.isMeteringEnabledForActiveConsumers, !self.shouldAvoidStartingMeterOnProtectedBluetoothMic else {
                    self.stopMeterEngineIfRunning()
                    return
                }
                self.ensureMeterTimerRunning()
            }
        }
    }

    private func stopMeterEngineIfRunning() {
        meterTimer?.invalidate()
        meterTimer = nil
        if smoothingLevel != 0.0 {
            smoothingLevel = 0.0
        }
        if micLevel != 0.0 {
            micLevel = 0.0
        }
        guard isMeterEngineStarted || meterEngineDeviceID != kAudioObjectUnknown else { return }
        isMeterEngineStarted = false
        meterEngineDeviceID = AudioObjectID(kAudioObjectUnknown)
        let engine = meterEngine
        DispatchQueue.global(qos: .utility).async {
            engine.stop()
        }
    }

    private func ensureMeterTimerRunning() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                AudioDeviceManager.shared.updateMeterSmoothed()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.meterTimer = timer
    }

    private static func isBluetoothAudioDevice(_ device: AudioDeviceInfo) -> Bool {
        if device.transportType == .bluetooth { return true }
        let lower = device.name.lowercased()
        return lower.contains("airpods") || lower.contains("beats") || lower.contains("bluetooth")
    }

    private static func preferredNonBluetoothMicrophone(from inputs: [AudioDeviceInfo]) -> AudioDeviceInfo? {
        let nonBT = inputs.filter { !isBluetoothAudioDevice($0) && $0.transportType != .virtual }

        if let usbOrExternal = nonBT.first(where: { $0.transportType == .usb }) {
            return usbOrExternal
        }
        if let builtIn = nonBT.first(where: { $0.transportType == .builtIn }) {
            return builtIn
        }
        return nonBT.first
    }

    private static func device(_ device: AudioDeviceInfo, matchesUID targetUID: String?, name targetName: String?) -> Bool {
        let uid = targetUID ?? ""
        let name = targetName ?? ""
        if !uid.isEmpty && (device.uid == uid || device.uid.contains(uid) || uid.contains(device.uid)) {
            return true
        }
        if !name.isEmpty && device.name.localizedCaseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        return false
    }

    private static func resolveLiveDevice(_ device: AudioDeviceInfo, in list: [AudioDeviceInfo]) -> AudioDeviceInfo {
        if let exactUID = list.first(where: { $0.uid == device.uid }) {
            return exactUID
        }
        if let byID = list.first(where: { $0.id == device.id }) {
            return byID
        }
        if let byName = list.first(where: { $0.name.localizedCaseInsensitiveCompare(device.name) == .orderedSame }) {
            return byName
        }
        return device
    }

    private static func ensureBluetoothAudioConnected(for device: AudioDeviceInfo) {
        let targetUIDNorm = device.uid.lowercased().replacingOccurrences(of: ":", with: "-")
        let targetName = device.name
        DispatchQueue.global(qos: .utility).async {
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let matched = paired.first { bt in
                if let addr = bt.addressString?.lowercased().replacingOccurrences(of: ":", with: "-"),
                   !addr.isEmpty, targetUIDNorm.contains(addr) {
                    return true
                }
                if let btName = bt.name, btName.localizedCaseInsensitiveCompare(targetName) == .orderedSame {
                    return true
                }
                return false
            }
            if let matched, !matched.isConnected() {
                _ = matched.openConnection()
            }
        }
    }

#if DEBUG
    func setTestState(
        availableInputs: [AudioDeviceInfo],
        availableOutputs: [AudioDeviceInfo],
        currentInput: AudioDeviceInfo? = nil,
        currentOutput: AudioDeviceInfo? = nil
    ) {
        self.availableInputDevices = availableInputs
        self.availableOutputDevices = availableOutputs
        self.knownOutputDeviceUIDs = Set(availableOutputs.map(\.uid))
        self.knownInputDeviceUIDs = Set(availableInputs.map(\.uid))
        self.hasCompletedInitialDeviceScan = true
        self.clearOutputGuard()
        self.userSelectedBluetoothInputUID = nil
        if let currentInput {
            self.currentInputDevice = currentInput
            if !Self.isBluetoothAudioDevice(currentInput) {
                self.lastNonBluetoothInputDevice = currentInput
            }
        }
        if let currentOutput {
            self.currentOutputDevice = currentOutput
            self.previousActiveOutputUID = currentOutput.uid
            self.lastNotifiedOutputUID = currentOutput.uid
            self.lastNotifiedOutputID = currentOutput.id
        } else {
            self.lastNotifiedOutputUID = nil
            self.lastNotifiedOutputID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    func resetTestRoutingState() {
        knownOutputDeviceUIDs = []
        knownInputDeviceUIDs = []
        previousActiveOutputUID = nil
        lastNotifiedOutputUID = nil
        lastNotifiedOutputID = AudioObjectID(kAudioObjectUnknown)
        hasCompletedInitialDeviceScan = false
        clearOutputGuard()
        micGuardTask?.cancel()
        micGuardTask = nil
        userSelectedBluetoothInputUID = nil
        lastManualOutputSelectionAt = .distantPast
        availableOutputDevices = []
        availableInputDevices = []
        currentOutputDevice = nil
        currentInputDevice = nil
        lastNonBluetoothInputDevice = nil
        isMicrophoneLocked = false
        lockedMicrophoneUID = nil
        lockedMicrophoneName = nil
        preferredOutputUID = nil
        preferredOutputName = nil
        autoSwitchPreferredOutput = true
        autoProtectMicrophoneOnBluetooth = true
    }

    func simulateHALRefresh(
        outputs: [AudioDeviceInfo],
        inputs: [AudioDeviceInfo],
        defaultOutputID: AudioDeviceID,
        defaultInputID: AudioDeviceID
    ) {
        processDeviceRefresh(
            outputs: outputs,
            inputs: inputs,
            halDefaultOutputID: defaultOutputID,
            halDefaultInputID: defaultInputID
        )
    }
#endif

    func setInputVolume(_ volume: Float) {
        isSettingInputState = true
        lastLocalInputWriteAt = Date()
        defer { isSettingInputState = false }

        let clamped = max(0.0, min(1.0, volume))
        inputVolume = clamped
        if clamped > 0 {
            savedNonZeroInputVolume = clamped
        }

        guard !AppInfo.isRunningTests else {
            if clamped == 0 {
                isInputMuted = true
                micLevel = 0.0
            } else if isInputMuted {
                isInputMuted = false
            }
            return
        }

        let devID = currentInputDeviceID != kAudioObjectUnknown ? currentInputDeviceID : Self.defaultInputDeviceID()
        guard devID != kAudioObjectUnknown else { return }

        Self.setInputVolume(clamped, on: devID)
        if clamped > 0 && isInputMuted {
            setInputMuted(false)
        } else if clamped == 0 && !isInputMuted {
            isInputMuted = true
            micLevel = 0.0
            meterEngine.resetLevel()
        }
    }

    func toggleInputMute() {
        setInputMuted(!isInputMuted)
    }

    func setInputMuted(_ muted: Bool) {
        isSettingInputState = true
        lastLocalInputWriteAt = Date()
        defer { isSettingInputState = false }

        guard !AppInfo.isRunningTests else {
            isInputMuted = muted
            if muted {
                if inputVolume > 0.01 {
                    savedNonZeroInputVolume = inputVolume
                }
                micLevel = 0.0
            } else {
                if inputVolume <= 0.01 {
                    inputVolume = savedNonZeroInputVolume > 0.01 ? savedNonZeroInputVolume : 0.75
                }
                micLevel = 0.5
            }
            return
        }

        let devID = currentInputDeviceID != kAudioObjectUnknown ? currentInputDeviceID : Self.defaultInputDeviceID()
        guard devID != kAudioObjectUnknown else { return }

        if muted && inputVolume > 0.01 {
            savedNonZeroInputVolume = inputVolume
        }

        var handled = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var muteAddr = Self.inputMuteAddress(element: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(devID, &muteAddr),
               AudioObjectIsPropertySettable(devID, &muteAddr, &settable) == noErr,
               settable.boolValue {
                var val: UInt32 = muted ? 1 : 0
                let size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectSetPropertyData(devID, &muteAddr, 0, nil, size, &val) == noErr {
                    handled = true
                    if element == kAudioObjectPropertyElementMain {
                        break
                    }
                }
            }
        }

        if !handled {
            if muted {
                if let vol = Self.getInputVolume(devID: devID), vol > 0.01 {
                    savedNonZeroInputVolume = vol
                }
                Self.setInputVolume(0.0, on: devID)
            } else {
                let restore = savedNonZeroInputVolume > 0.01 ? savedNonZeroInputVolume : 0.75
                Self.setInputVolume(restore, on: devID)
                inputVolume = restore
            }
        } else if !muted {
            let currentVol = Self.getInputVolume(devID: devID) ?? inputVolume
            if currentVol <= 0.01 {
                let restore = savedNonZeroInputVolume > 0.01 ? savedNonZeroInputVolume : 0.75
                Self.setInputVolume(restore, on: devID)
                inputVolume = restore
            }
        }

        isInputMuted = muted
        if muted {
            micLevel = 0.0
            meterEngine.resetLevel()
        }

        HUDManager.shared.showHUD(type: .micMute, value: muted ? 0.0 : inputVolume, isMuted: muted)
    }

    private func readInputState() {
        let devID = currentInputDeviceID != kAudioObjectUnknown ? currentInputDeviceID : Self.defaultInputDeviceID()
        guard devID != kAudioObjectUnknown else { return }

        var muteVal: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var hasMuteProperty = false

        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var muteAddr = Self.inputMuteAddress(element: element)
            if AudioObjectHasProperty(devID, &muteAddr),
               AudioObjectGetPropertyData(devID, &muteAddr, 0, nil, &muteSize, &muteVal) == noErr {
                hasMuteProperty = true
                break
            }
        }

        if let vol = Self.getInputVolume(devID: devID) {
            let clampedVol = max(0.0, min(1.0, vol))
            if abs(inputVolume - clampedVol) >= 0.005 {
                inputVolume = clampedVol
            }
            if clampedVol > 0.01 {
                savedNonZeroInputVolume = clampedVol
            }
            let newMuted: Bool
            if !hasMuteProperty {
                newMuted = (clampedVol <= 0.001 && savedNonZeroInputVolume > 0)
            } else {
                newMuted = (muteVal == 1)
            }
            if isInputMuted != newMuted {
                isInputMuted = newMuted
            }
        } else if hasMuteProperty {
            let newMuted = (muteVal == 1)
            if isInputMuted != newMuted {
                isInputMuted = newMuted
            }
        }
    }

    func refreshMicrophoneMode() {
        let mode = AVCaptureDevice.preferredMicrophoneMode
        if preferredMicrophoneMode != mode {
            preferredMicrophoneMode = mode
        }
    }

    func showVoiceIsolationPicker() {
        NotchWindowController.shared.navigationGraceUntil = Date().addingTimeInterval(4.0)
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshMicrophoneMode()
        }
    }

    func startMetering(consumer: String) {
        activeConsumers.insert(consumer)
        guard !AppInfo.isRunningTests else { return }
        let devID = currentInputDeviceID != kAudioObjectUnknown ? currentInputDeviceID : Self.defaultInputDeviceID()
        startMeterEngineIfNeeded(for: devID)
    }

    func stopMetering(consumer: String) {
        activeConsumers.remove(consumer)
        if !isMeteringEnabledForActiveConsumers {
            stopMeterEngineIfRunning()
        }
    }

    func syncMeteringState() {
        guard !AppInfo.isRunningTests else { return }
        if !isMeteringEnabledForActiveConsumers || shouldAvoidStartingMeterOnProtectedBluetoothMic {
            stopMeterEngineIfRunning()
        } else {
            let devID = currentInputDeviceID != kAudioObjectUnknown ? currentInputDeviceID : Self.defaultInputDeviceID()
            startMeterEngineIfNeeded(for: devID)
        }
    }

    private func updateMeterSmoothed() {
        guard !isInputMuted else {
            if smoothingLevel != 0.0 {
                smoothingLevel = 0.0
            }
            if micLevel != 0.0 {
                micLevel = 0.0
            }
            return
        }

        let raw = meterEngine.currentRawLevel
        if raw > smoothingLevel {
            smoothingLevel = smoothingLevel * 0.35 + raw * 0.65
        } else {
            smoothingLevel = smoothingLevel * 0.72 + raw * 0.28
        }

        if smoothingLevel < 0.02 {
            smoothingLevel = 0.0
        }

        if abs(micLevel - smoothingLevel) >= 0.005 || (smoothingLevel == 0.0 && micLevel != 0.0) {
            micLevel = smoothingLevel
        }
    }

    private func attachInputDeviceListeners(to deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }
        for var addr in Self.listenedInputAddresses {
            if AudioObjectHasProperty(deviceID, &addr) {
                AudioObjectAddPropertyListener(deviceID, &addr, audioHALDeviceListenerProc, nil)
            }
        }
    }

    private func detachInputDeviceListeners(from deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }
        for var addr in Self.listenedInputAddresses {
            _ = AudioObjectRemovePropertyListener(deviceID, &addr, audioHALDeviceListenerProc, nil)
        }
    }

    private static var listenedInputAddresses: [AudioObjectPropertyAddress] {
        [
            inputMuteAddress(element: kAudioObjectPropertyElementMain),
            inputMuteAddress(element: 1),
            inputVirtualMainVolumeAddress,
            inputVolumeAddress(element: kAudioObjectPropertyElementMain),
            inputVolumeAddress(element: 1)
        ]
    }

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var defaultSystemOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var defaultInputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func inputMuteAddress(element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private static var inputVirtualMainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x766D7663),
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func inputVolumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private static func scanHALDevices() -> (outputs: [AudioDeviceInfo], inputs: [AudioDeviceInfo]) {
        let allIDs = allDeviceIDs()
        var outputs: [AudioDeviceInfo] = []
        var inputs: [AudioDeviceInfo] = []

        for id in allIDs {
            guard isDeviceAlive(id: id), !isDeviceHidden(id: id) else { continue }
            let hasOut = hasStreams(id: id, isInput: false)
            let hasIn = hasStreams(id: id, isInput: true)
            guard hasOut || hasIn else { continue }

            let name = getStringProperty(id: id, selector: kAudioObjectPropertyName)
            guard !name.isEmpty else { continue }
            if name.hasPrefix("MonoHub ") || name.hasPrefix("CADefaultDeviceAggregate") {
                continue
            }

            let uid = getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID)
            if uid.hasPrefix("com.monohub.") {
                continue
            }

            let transport = getTransportType(id: id)
            let info = AudioDeviceInfo(
                id: id,
                uid: uid.isEmpty ? "\(id)" : uid,
                name: name,
                isInput: hasIn,
                isOutput: hasOut,
                transportType: transport
            )

            if hasOut {
                outputs.append(info)
            }
            if hasIn {
                inputs.append(info)
            }
        }

        return (sortDevices(outputs), sortDevices(inputs))
    }

    private static func sortDevices(_ devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        devices.sorted { lhs, rhs in
            let lRank = transportSortRank(lhs.transportType)
            let rRank = transportSortRank(rhs.transportType)
            if lRank != rRank {
                return lRank < rRank
            }
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.uid < rhs.uid
        }
    }

    private static func transportSortRank(_ transport: AudioTransportType) -> Int {
        switch transport {
        case .bluetooth: return 0
        case .usb: return 1
        case .builtIn: return 2
        case .hdmi, .displayPort: return 3
        case .airPlay: return 4
        case .continuity: return 5
        case .virtual: return 6
        case .other: return 7
        }
    }

    @discardableResult
    private static func setSystemDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultOutputDeviceAddress
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID)

        var sysAddr = defaultSystemOutputDeviceAddress
        if AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &sysAddr) {
            var settable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject), &sysAddr, &settable) == noErr,
               settable.boolValue {
                _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &sysAddr, 0, nil, size, &devID)
            }
        }

        return status == noErr
    }

    private static func setSystemDefaultInputDevice(id: AudioDeviceID) -> OSStatus {
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultInputDeviceAddress
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultOutputDeviceAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        return status == noErr ? devID : AudioDeviceID(kAudioObjectUnknown)
    }

    private static func defaultInputDeviceID() -> AudioDeviceID {
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultInputDeviceAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        return status == noErr ? devID : AudioDeviceID(kAudioObjectUnknown)
    }

    private static func isDeviceAlive(id: AudioDeviceID) -> Bool {
        guard id != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &addr) else { return true }
        var alive: UInt32 = 1
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &alive)
        return status != noErr || alive != 0
    }

    private static func isDeviceHidden(id: AudioDeviceID) -> Bool {
        guard id != kAudioObjectUnknown else { return true }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &hidden)
        return status == noErr && hidden != 0
    }

    private static func hasStreams(id: AudioObjectID, isInput: Bool) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func getTransportType(id: AudioObjectID) -> AudioTransportType {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return status == noErr ? AudioTransportType(rawValue: transport) : .other(0)
    }

    private static func getStringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rawCF: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &rawCF) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        if status == noErr, let cfStr = rawCF?.takeRetainedValue() {
            return cfStr as String
        }
        return ""
    }

    private static func getInputVolume(devID: AudioObjectID) -> Float? {
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        for var addr in [
            inputVirtualMainVolumeAddress,
            inputVolumeAddress(element: kAudioObjectPropertyElementMain),
            inputVolumeAddress(element: 1),
            inputVolumeAddress(element: 2)
        ] {
            if AudioObjectHasProperty(devID, &addr) &&
               AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return nil
    }

    private static func setInputVolume(_ volume: Float, on devID: AudioObjectID) {
        var vol = Float32(volume)
        let size = UInt32(MemoryLayout<Float32>.size)

        var virtualAddr = inputVirtualMainVolumeAddress
        var virtualSettable: DarwinBoolean = false
        if AudioObjectHasProperty(devID, &virtualAddr),
           AudioObjectIsPropertySettable(devID, &virtualAddr, &virtualSettable) == noErr,
           virtualSettable.boolValue,
           AudioObjectSetPropertyData(devID, &virtualAddr, 0, nil, size, &vol) == noErr {
            return
        }

        var mainAddr = inputVolumeAddress(element: kAudioObjectPropertyElementMain)
        var mainSettable: DarwinBoolean = false
        if AudioObjectHasProperty(devID, &mainAddr),
           AudioObjectIsPropertySettable(devID, &mainAddr, &mainSettable) == noErr,
           mainSettable.boolValue,
           AudioObjectSetPropertyData(devID, &mainAddr, 0, nil, size, &vol) == noErr {
            return
        }

        for ch: UInt32 in [1, 2] {
            var chAddr = inputVolumeAddress(element: ch)
            var chSettable: DarwinBoolean = false
            if AudioObjectHasProperty(devID, &chAddr),
               AudioObjectIsPropertySettable(devID, &chAddr, &chSettable) == noErr,
               chSettable.boolValue {
                AudioObjectSetPropertyData(devID, &chAddr, 0, nil, size, &vol)
            }
        }
    }
}

nonisolated final class AudioMeterStorage: @unchecked Sendable {
    private var storage: Float = 0.0
    private var lock = os_unfair_lock()

    func get() -> Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage
    }

    func set(_ value: Float) {
        os_unfair_lock_lock(&lock)
        storage = value
        os_unfair_lock_unlock(&lock)
    }

    func reset() {
        set(0.0)
    }
}

nonisolated final class AudioLevelMeterEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.monohub.audiometer.engine", qos: .utility)
    private var engine: AVAudioEngine?
    private var isEngineRunning = false
    private var activeDeviceID = AudioObjectID(kAudioObjectUnknown)
    private let meterStorage = AudioMeterStorage()

    nonisolated var currentRawLevel: Float {
        meterStorage.get()
    }

    nonisolated func resetLevel() {
        meterStorage.reset()
    }

    nonisolated func start(deviceID: AudioObjectID) -> Bool {
        queue.sync {
            if isEngineRunning, activeDeviceID == deviceID, let eng = engine, eng.isRunning {
                return true
            }
            stopLocked()

            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                return false
            }
            guard authStatus == .authorized else { return false }

            let eng = AVAudioEngine()
            let input = eng.inputNode
            let bus = AVAudioNodeBus(0)
            let format = input.outputFormat(forBus: bus)

            guard format.sampleRate > 0 && format.channelCount > 0 else { return false }

            let storage = self.meterStorage
            let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }

                var sum: Float = 0
                var count = 0
                let strideStep = 4
                for i in stride(from: 0, to: frameLength, by: strideStep) {
                    let s = channelData[i]
                    sum += s * s
                    count += 1
                }

                let rms = sqrt(sum / max(1.0, Float(count)))
                let db = 20 * log10(max(rms, 0.0001))
                let normalized = max(0.0, min(1.0, (db + 45.0) / 40.0))
                storage.set(normalized)
            }

            let bufferSize: AVAudioFrameCount = 512
            do {
                try input.__installTap(onBus: bus, bufferSize: bufferSize, format: nil, error: (), block: block)
            } catch {
                stopLocked()
                return false
            }

            do {
                try eng.start()
                self.engine = eng
                self.isEngineRunning = true
                self.activeDeviceID = deviceID
                return true
            } catch {
                input.removeTap(onBus: bus)
                eng.stop()
                stopLocked()
                return false
            }
        }
    }

    nonisolated func stop() {
        queue.sync {
            stopLocked()
        }
    }

    nonisolated private func stopLocked() {
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
            self.engine = nil
        }
        isEngineRunning = false
        activeDeviceID = AudioObjectID(kAudioObjectUnknown)
        meterStorage.reset()
    }
}
