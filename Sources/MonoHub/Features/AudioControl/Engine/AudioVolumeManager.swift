import AppKit
import CoreAudio
import Foundation
import Observation

nonisolated func audioHALVolumeListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            AudioVolumeManager.shared.handleVolumeChangedFromHAL()
        }
    }
    return noErr
}

@Observable
@MainActor
final class AudioVolumeManager {
    static let shared = AudioVolumeManager()

    private(set) var currentVolume: Float = 0.5
    private(set) var isMuted: Bool = false

    @ObservationIgnored private(set) var isMonitoring = false
    @ObservationIgnored private var isSettingVolume = false
    @ObservationIgnored private var lastLocalVolumeWriteAt: Date = .distantPast
    @ObservationIgnored private var currentDeviceID = AudioObjectID(kAudioObjectUnknown)

    private init() {}

    nonisolated static func clamped(_ value: Float) -> Float {
        value.clamped(to: 0...1)
    }

    func startMonitoring() {
        guard !AppInfo.isRunningTests else { return }
        guard !isMonitoring else { return }
        var defaultDevAddr = Self.defaultDeviceAddress
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, audioHALVolumeListenerProc, nil)
        currentDeviceID = Self.defaultOutputDeviceID()
        attachDeviceListeners(to: currentDeviceID)
        isMonitoring = true
        readVolume(showHUDOnChange: false)
    }

    func stopMonitoring() {
        guard !AppInfo.isRunningTests else { return }
        guard isMonitoring else { return }
        var defaultDevAddr = Self.defaultDeviceAddress
        _ = AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, audioHALVolumeListenerProc, nil)
        detachDeviceListeners(from: currentDeviceID)
        currentDeviceID = AudioObjectID(kAudioObjectUnknown)
        isMonitoring = false
    }

    func setVolume(_ volume: Float) {
        guard !isSettingVolume else { return }
        isSettingVolume = true
        lastLocalVolumeWriteAt = Date()
        defer { isSettingVolume = false }

        let clamped = Self.clamped(volume)
        if currentVolume != clamped {
            currentVolume = clamped
        }

        let devID = Self.defaultOutputDeviceID()
        guard devID != kAudioObjectUnknown else { return }

        setHardwareVolume(clamped, on: devID)

        if isMuted && clamped > 0 {
            setMuted(false, on: devID)
        }

        let ctx = currentOutputDeviceContext()
        HUDManager.shared.showHUD(
            type: .volume,
            value: clamped,
            isMuted: isMuted,
            displayTitle: ctx.title,
            customIconName: ctx.iconName
        )
    }

    func increaseVolume(step: Float = 0.0625) {
        syncIfNeeded()
        setVolume(currentVolume + step)
    }

    func decreaseVolume(step: Float = 0.0625) {
        syncIfNeeded()
        setVolume(currentVolume - step)
    }

    func toggleMute() {
        syncIfNeeded()
        let devID = Self.defaultOutputDeviceID()
        guard devID != kAudioObjectUnknown else { return }
        setMuted(!isMuted, on: devID)
        let ctx = currentOutputDeviceContext()
        HUDManager.shared.showHUD(
            type: .volume,
            value: currentVolume,
            isMuted: isMuted,
            displayTitle: ctx.title,
            customIconName: ctx.iconName
        )
    }

    func fetchVolume() {
        readVolume(showHUDOnChange: false)
    }

    func handleOutputDeviceChanged(to newDeviceID: AudioObjectID) {
        guard !AppInfo.isRunningTests else { return }
        guard newDeviceID != kAudioObjectUnknown else { return }
        if isMonitoring && newDeviceID != currentDeviceID {
            detachDeviceListeners(from: currentDeviceID)
            currentDeviceID = newDeviceID
            attachDeviceListeners(to: newDeviceID)
        }
        readVolume(showHUDOnChange: false)
    }

    func handleVolumeChangedFromHAL() {
        guard isMonitoring, !isSettingVolume else { return }
        let newDeviceID = Self.defaultOutputDeviceID()
        if newDeviceID != currentDeviceID {
            detachDeviceListeners(from: currentDeviceID)
            currentDeviceID = newDeviceID
            attachDeviceListeners(to: newDeviceID)
        }
        if Date().timeIntervalSince(lastLocalVolumeWriteAt) < 0.20 {
            return
        }
        readVolume(showHUDOnChange: true)
    }

    private func syncIfNeeded() {
        if !isMonitoring {
            readVolume(showHUDOnChange: false)
        }
    }

    private func setHardwareVolume(_ volume: Float, on devID: AudioObjectID) {
        var vol = Float32(volume)
        let size = UInt32(MemoryLayout<Float32>.size)

        var virtualAddr = Self.virtualMainVolumeAddress
        if Self.isPropertySettable(devID: devID, address: &virtualAddr),
           AudioObjectSetPropertyData(devID, &virtualAddr, 0, nil, size, &vol) == noErr {
            return
        }

        var masterAddr = Self.volumeAddress(element: kAudioObjectPropertyElementMain)
        if Self.isPropertySettable(devID: devID, address: &masterAddr),
           AudioObjectSetPropertyData(devID, &masterAddr, 0, nil, size, &vol) == noErr {
            return
        }

        for channel: UInt32 in [1, 2] {
            var chAddr = Self.volumeAddress(element: channel)
            if Self.isPropertySettable(devID: devID, address: &chAddr) {
                AudioObjectSetPropertyData(devID, &chAddr, 0, nil, size, &vol)
            }
        }
    }

    private func setMuted(_ muted: Bool, on devID: AudioObjectID) {
        lastLocalVolumeWriteAt = Date()
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var handled = false

        var masterMute = Self.muteAddress(element: kAudioObjectPropertyElementMain)
        if Self.isPropertySettable(devID: devID, address: &masterMute),
           AudioObjectSetPropertyData(devID, &masterMute, 0, nil, size, &value) == noErr {
            handled = true
        }

        if !handled {
            for channel: UInt32 in [1, 2] {
                var chMute = Self.muteAddress(element: channel)
                if Self.isPropertySettable(devID: devID, address: &chMute),
                   AudioObjectSetPropertyData(devID, &chMute, 0, nil, size, &value) == noErr {
                    handled = true
                }
            }
        }

        if isMuted != muted {
            isMuted = muted
        }
    }

    private func readVolume(showHUDOnChange: Bool) {
        let devID = Self.defaultOutputDeviceID()
        guard devID != kAudioObjectUnknown else { return }

        var vol: Float32 = currentVolume
        var size = UInt32(MemoryLayout<Float32>.size)
        var found = false

        for var addr in [
            Self.virtualMainVolumeAddress,
            Self.volumeAddress(element: kAudioObjectPropertyElementMain),
            Self.volumeAddress(element: 1),
            Self.volumeAddress(element: 2)
        ] {
            if AudioObjectHasProperty(devID, &addr),
               AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &vol) == noErr {
                found = true
                break
            }
        }

        var mutedVal: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        for var muteAddr in [
            Self.muteAddress(element: kAudioObjectPropertyElementMain),
            Self.muteAddress(element: 1),
            Self.muteAddress(element: 2)
        ] {
            if AudioObjectHasProperty(devID, &muteAddr),
               AudioObjectGetPropertyData(devID, &muteAddr, 0, nil, &muteSize, &mutedVal) == noErr {
                break
            }
        }

        let newMuted = mutedVal == 1
        let newVolume = found ? Self.clamped(vol) : currentVolume
        let volumeChanged = abs(currentVolume - newVolume) >= 0.005
        let muteChanged = isMuted != newMuted
        if volumeChanged {
            currentVolume = newVolume
        }
        if muteChanged {
            isMuted = newMuted
        }
        if showHUDOnChange && (volumeChanged || muteChanged) {
            let ctx = currentOutputDeviceContext()
            HUDManager.shared.showHUD(
                type: .volume,
                value: newVolume,
                isMuted: newMuted,
                displayTitle: ctx.title,
                customIconName: ctx.iconName
            )
        }
    }

    private func currentOutputDeviceContext() -> (title: String?, iconName: String?) {
        if AudioDeviceManager.shared.currentOutputDevice == nil {
            AudioDeviceManager.shared.refreshDevices()
        }
        guard let dev = AudioDeviceManager.shared.currentOutputDevice else {
            return (nil, nil)
        }
        return (dev.name, dev.iconName)
    }

    private func attachDeviceListeners(to deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }
        for var addr in Self.listenedOutputAddresses {
            if AudioObjectHasProperty(deviceID, &addr) {
                AudioObjectAddPropertyListener(deviceID, &addr, audioHALVolumeListenerProc, nil)
            }
        }
    }

    private func detachDeviceListeners(from deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }
        for var addr in Self.listenedOutputAddresses {
            _ = AudioObjectRemovePropertyListener(deviceID, &addr, audioHALVolumeListenerProc, nil)
        }
    }

    private static var listenedOutputAddresses: [AudioObjectPropertyAddress] {
        [
            virtualMainVolumeAddress,
            volumeAddress(element: kAudioObjectPropertyElementMain),
            volumeAddress(element: 1),
            muteAddress(element: kAudioObjectPropertyElementMain),
            muteAddress(element: 1)
        ]
    }

    private static func isPropertySettable(devID: AudioObjectID, address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(devID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(devID, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var virtualMainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x766D7663),
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func defaultOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = defaultDeviceAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : kAudioObjectUnknown
    }
}
