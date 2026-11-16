import Testing
import AppKit
import Foundation
import CoreAudio
@testable import MonoHub

@Suite("Audio Device Manager & Route Selector Tests", .serialized)
@MainActor
struct AudioDeviceManagerTests {

    @Test("Audio transport type raw values map correctly")
    func transportTypeMapping() {
        #expect(AudioTransportType(rawValue: 1651274862) == .builtIn)
        #expect(AudioTransportType(rawValue: 1651275109) == .bluetooth)
        #expect(AudioTransportType(rawValue: 1651271009) == .bluetooth)
        #expect(AudioTransportType(rawValue: 1751412073) == .hdmi)
        #expect(AudioTransportType(rawValue: 1685090932) == .displayPort)
        #expect(AudioTransportType(rawValue: 1970496032) == .usb)
        #expect(AudioTransportType(rawValue: 1634230896) == .airPlay)
        #expect(AudioTransportType(rawValue: 1986622068) == .virtual)
        #expect(AudioTransportType(rawValue: 1667463012) == .continuity)
        #expect(AudioTransportType(rawValue: 99999) == .other(99999))
    }

    @Test("Audio device info provides accurate SF Symbols based on name and transport")
    func audioDeviceIcons() {
        let airPodsMax = AudioDeviceInfo(
            id: 1,
            uid: "ap-max",
            name: "João's AirPods Max",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )
        #expect(airPodsMax.iconName == "airpodsmax")

        let airPodsPro = AudioDeviceInfo(
            id: 2,
            uid: "ap-pro",
            name: "AirPods Pro",
            isInput: true,
            isOutput: false,
            transportType: .bluetooth
        )
        #expect(airPodsPro.iconName == "airpodspro")

        let airPodsGen = AudioDeviceInfo(
            id: 3,
            uid: "ap-gen",
            name: "AirPods",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )
        #expect(airPodsGen.iconName == "airpods")

        let builtInSpeakers = AudioDeviceInfo(
            id: 4,
            uid: "builtin-spk",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        #expect(builtInSpeakers.iconName == "laptopcomputer")

        let builtInMic = AudioDeviceInfo(
            id: 5,
            uid: "builtin-mic",
            name: "MacBook Pro Microphone",
            isInput: true,
            isOutput: false,
            transportType: .builtIn
        )
        #expect(builtInMic.iconName == "mic.fill")

        let hdmiDisplay = AudioDeviceInfo(
            id: 6,
            uid: "hdmi-mon",
            name: "LG UltraFine 4K",
            isInput: false,
            isOutput: true,
            transportType: .hdmi
        )
        #expect(hdmiDisplay.iconName == "display")

        let continuityMic = AudioDeviceInfo(
            id: 7,
            uid: "iphone-mic",
            name: "iPhone Microphone",
            isInput: true,
            isOutput: false,
            transportType: .continuity
        )
        #expect(continuityMic.iconName == "iphone")
    }

    @Test("Audio device manager handles output and input device selection")
    func audioDeviceSelection() {
        let manager = AudioDeviceManager.shared

        let output = AudioDeviceInfo(
            id: 101,
            uid: "test-out",
            name: "Studio Headphones",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        manager.selectOutputDevice(output)
        #expect(manager.currentOutputDevice?.id == 101)

        let input = AudioDeviceInfo(
            id: 202,
            uid: "test-in",
            name: "Podcast Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        manager.selectInputDevice(input)
        #expect(manager.currentInputDevice?.id == 202)
    }

    @Test("Audio device manager toggles input mute and sets levels appropriately")
    func inputMuteToggling() {
        let manager = AudioDeviceManager.shared

        manager.setInputMuted(true)
        #expect(manager.isInputMuted)
        #expect(manager.micLevel == 0.0)

        manager.toggleInputMute()
        #expect(!manager.isInputMuted)

        manager.toggleInputMute()
        #expect(manager.isInputMuted)
    }

    @Test("HUDEvent correctly formats microphone mute and active states")
    func hudEventMicrophoneFormatting() {
        let mutedHUD = HUDEvent(type: .micMute, value: 0.0, isMuted: true)
        #expect(mutedHUD.percentageString == localized("Muted"))

        let activeHUD = HUDEvent(type: .micMute, value: 0.85, isMuted: false)
        #expect(activeHUD.percentageString == localized("Microphone Active"))
    }

    @Test("Preferences toggle audio route selector and adapt expanded height")
    func preferencesAndHeight() {
        let prefs = NotchPreferences.shared
        let original = prefs.musicShowAudioRouteSelector
        let originalAuto = prefs.autoAdjustHeight
        prefs.autoAdjustHeight = true

        prefs.musicShowAudioRouteSelector = true
        let heightWith = prefs.effectiveExpandedHeight(for: .music)

        prefs.musicShowAudioRouteSelector = false
        let heightWithout = prefs.effectiveExpandedHeight(for: .music)

        #expect(heightWith > heightWithout)
        #expect(heightWith - heightWithout == 53)

        let origMicMeter = prefs.musicEnableMicLevelMeter
        prefs.musicEnableMicLevelMeter = true
        #expect(prefs.musicEnableMicLevelMeter == true)
        prefs.musicEnableMicLevelMeter = false
        #expect(prefs.musicEnableMicLevelMeter == false)
        prefs.musicEnableMicLevelMeter = origMicMeter

        prefs.musicShowAudioRouteSelector = original
        prefs.autoAdjustHeight = originalAuto
    }

    @Test("Portuguese localizations exist for audio route and microphone controls")
    func portugueseLocalizations() {
        #expect(PortugueseStrings.table["Audio Output"] == "Saída de Áudio")
        #expect(PortugueseStrings.table["Select Audio Output Device"] == "Selecionar Saída de Áudio")
        #expect(PortugueseStrings.table["Microphone"] == "Microfone")
        #expect(PortugueseStrings.table["Microphone Muted"] == "Microfone Silenciado")
        #expect(PortugueseStrings.table["Mute Microphone"] == "Silenciar Microfone")
        #expect(PortugueseStrings.table["Unmute Microphone"] == "Ativar Microfone")
        #expect(PortugueseStrings.table["Voice Isolation"] == "Isolamento de Voz")
        #expect(PortugueseStrings.table["Voice Isolation & Microphone Modes"] == "Isolamento de Voz e Modos do Microfone")
        #expect(PortugueseStrings.table["Microphone Mode"] == "Modo do Microfone")
        #expect(PortugueseStrings.table["System Sound Settings…"] == "Ajustes de Som do Sistema…")
        #expect(PortugueseStrings.table["Speakers"] == "Alto-falantes")
        #expect(PortugueseStrings.table["Bluetooth & Audio"] == "Bluetooth & Áudio")
        #expect(PortugueseStrings.table["Audio Routing & Fixed Microphone"] == "Roteamento de Áudio & Microfone Fixo")
        #expect(PortugueseStrings.table["Fixed Default Microphone"] == "Microfone Padrão Fixo")
        #expect(PortugueseStrings.table["Microphone Locked"] == "Microfone Travado")
        #expect(PortugueseStrings.table["Lock Current Mic"] == "Travar Microfone Atual")
        #expect(PortugueseStrings.table["Sound & Headphone Output"] == "Saída de Som & Fone")
        #expect(PortugueseStrings.table["Sound & Audio Control"] == "Controle de Som & Áudio")
        #expect(PortugueseStrings.table["Per-Application Volume Mixer"] == "Mixer de Volume por Aplicativo")
    }

    @Test("Microphone locking, unlocking and toggling works as expected")
    func microphoneLockingAndToggling() {
        let manager = AudioDeviceManager.shared
        let usbMic = AudioDeviceInfo(
            id: 301,
            uid: "usb-maono-pm421",
            name: "Maono AU-PM421 USB Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let builtInMic = AudioDeviceInfo(
            id: 302,
            uid: "builtin-internal-mic",
            name: "MacBook Pro Microphone",
            isInput: true,
            isOutput: false,
            transportType: .builtIn
        )

        manager.setTestState(
            availableInputs: [usbMic, builtInMic],
            availableOutputs: [],
            currentInput: builtInMic
        )

        // Lock to USB Maono
        manager.lockMicrophone(to: usbMic)
        #expect(manager.isMicrophoneLocked)
        #expect(manager.lockedMicrophoneUID == "usb-maono-pm421")
        #expect(manager.lockedMicrophoneName == "Maono AU-PM421 USB Microphone")
        #expect(manager.currentInputDevice?.id == 301)
        #expect(manager.isCurrentMicrophoneLocked)

        // Toggle unlocks
        manager.toggleMicrophoneLock()
        #expect(!manager.isMicrophoneLocked)
        #expect(!manager.isCurrentMicrophoneLocked)

        // Toggle locks again to current device
        manager.toggleMicrophoneLock()
        #expect(manager.isMicrophoneLocked)
        #expect(manager.lockedMicrophoneUID == "usb-maono-pm421")

        // Unlock
        manager.unlockMicrophone()
        #expect(!manager.isMicrophoneLocked)
    }

    @Test("Enforcing microphone lock restores Maono USB mic when macOS/AirPods hijack input")
    func enforceMicrophoneLockWhenAirPodsConnect() {
        let manager = AudioDeviceManager.shared
        let maonoMic = AudioDeviceInfo(
            id: 401,
            uid: "maono-usb-mic-uid",
            name: "Maono USB Audio",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let airPodsMic = AudioDeviceInfo(
            id: 402,
            uid: "airpods-pro-mic-uid",
            name: "AirPods Pro",
            isInput: true,
            isOutput: false,
            transportType: .bluetooth
        )

        // Lock microphone to Maono
        manager.setTestState(
            availableInputs: [maonoMic, airPodsMic],
            availableOutputs: [],
            currentInput: maonoMic
        )
        manager.lockMicrophone(to: maonoMic)
        #expect(manager.currentInputDevice?.name == "Maono USB Audio")

        // Simulate macOS changing input to AirPods Pro when connected
        manager.setTestState(
            availableInputs: [maonoMic, airPodsMic],
            availableOutputs: [],
            currentInput: airPodsMic
        )
        #expect(manager.currentInputDevice?.name == "AirPods Pro")

        // Enforce lock should instantly restore Maono as input
        manager.enforceMicrophoneLockIfNeeded()
        #expect(manager.currentInputDevice?.name == "Maono USB Audio")
        #expect(manager.currentInputDevice?.id == 401)
        #expect(manager.isCurrentMicrophoneLocked)

        manager.unlockMicrophone()
    }

    @Test("Preferred output routing selects preferred headphones when available")
    func preferredAudioOutputRouting() {
        let manager = AudioDeviceManager.shared
        let builtInSpk = AudioDeviceInfo(
            id: 501,
            uid: "spk-builtin",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let airPodsOut = AudioDeviceInfo(
            id: 502,
            uid: "airpods-pro-out",
            name: "AirPods Pro",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )

        manager.setTestState(
            availableInputs: [],
            availableOutputs: [builtInSpk, airPodsOut],
            currentOutput: builtInSpk
        )

        manager.setPreferredOutput(to: airPodsOut)
        #expect(manager.preferredOutputUID == "airpods-pro-out")
        #expect(manager.currentOutputDevice?.id == 502)

        // Switch to speakers, then check enforcement
        manager.selectOutputDevice(builtInSpk)
        #expect(manager.currentOutputDevice?.id == 501)

        manager.checkPreferredOutputIfNeeded()
        #expect(manager.currentOutputDevice?.id == 502)

        manager.setPreferredOutput(to: nil)
        #expect(manager.preferredOutputUID == nil)
    }

    @Test("Auto Bluetooth protection prevents AirPods from hijacking active USB microphone even without manual lock")
    func autoBluetoothProtectionRestoresUSBMic() {
        let manager = AudioDeviceManager.shared
        manager.unlockMicrophone()
        manager.autoProtectMicrophoneOnBluetooth = true

        let maonoMic = AudioDeviceInfo(
            id: 601,
            uid: "maono-caster-usb",
            name: "Maono USB Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let airPodsMic = AudioDeviceInfo(
            id: 602,
            uid: "airpods-pro-bt",
            name: "João's AirPods Pro",
            isInput: true,
            isOutput: false,
            transportType: .bluetooth
        )

        // Start with Maono active
        manager.setTestState(
            availableInputs: [maonoMic],
            availableOutputs: [],
            currentInput: maonoMic
        )
        #expect(manager.lastNonBluetoothInputDevice?.id == 601)

        // Simulate AirPods connecting and macOS switching default input to AirPods
        manager.setTestState(
            availableInputs: [maonoMic, airPodsMic],
            availableOutputs: [],
            currentInput: airPodsMic
        )
        #expect(manager.currentInputDevice?.id == 602)

        manager.enforceBluetoothMicProtectionIfNeeded()
        #expect(manager.currentInputDevice?.id == 601)
        #expect(manager.currentInputDevice?.name == "Maono USB Microphone")
    }

    @Test("Input volume adjustment updates gain and mute state")
    func inputVolumeAdjustment() {
        let manager = AudioDeviceManager.shared
        manager.setInputMuted(true)
        #expect(manager.isInputMuted)

        manager.setInputVolume(0.8)
        #expect(abs(manager.inputVolume - 0.8) < 0.001)
        #expect(!manager.isInputMuted)

        manager.setInputVolume(0.0)
        #expect(manager.inputVolume == 0.0)
        #expect(manager.isInputMuted)
    }

    @Test("Per-Application Volume Mixer updates and resets individual app volumes and mute states")
    func perAppVolumeMixerState() {
        let mixer = AudioProcessVolumeManager.shared
        let spotify = AudioAppSession(
            id: "com.spotify.client",
            pid: 1001,
            processObjectIDs: [9001],
            name: "Spotify",
            bundleID: "com.spotify.client",
            isRunningOutput: true,
            isRunningInput: false,
            volume: 1.0,
            isMuted: false
        )
        let discord = AudioAppSession(
            id: "com.hnc.Discord",
            pid: 1002,
            processObjectIDs: [9002],
            name: "Discord",
            bundleID: "com.hnc.Discord",
            isRunningOutput: true,
            isRunningInput: true,
            volume: 1.0,
            isMuted: false
        )

        mixer.setTestSessions([spotify, discord])
        #expect(mixer.activeSessions.count == 2)

        mixer.setVolume(0.45, for: "com.spotify.client")
        #expect(abs((mixer.activeSessions.first(where: { $0.id == "com.spotify.client" })?.volume ?? 0) - 0.45) < 0.001)

        mixer.toggleMute(for: "com.hnc.Discord")
        #expect(mixer.activeSessions.first(where: { $0.id == "com.hnc.Discord" })?.isMuted == true)

        mixer.resetAllToDefault()
        #expect(mixer.activeSessions.allSatisfy { !$0.isMuted && abs($0.volume - 1.0) < 0.001 })
        mixer.setTestSessions([])
    }

    @Test("Switching outputs freely works even when preferred output is connected")
    func freeOutputSwitchingWithPreferredOutputConnected() {
        let manager = AudioDeviceManager.shared
        manager.resetTestRoutingState()
        defer { manager.resetTestRoutingState() }

        let speakers = AudioDeviceInfo(
            id: 701,
            uid: "builtin-speakers",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let headphones = AudioDeviceInfo(
            id: 702,
            uid: "wired-headphones",
            name: "External Headphones",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let airPodsOut = AudioDeviceInfo(
            id: 703,
            uid: "airpods-pro-out",
            name: "AirPods Pro",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )

        manager.preferredOutputUID = headphones.uid
        manager.preferredOutputName = headphones.name
        manager.autoSwitchPreferredOutput = true

        // Initial scan selects preferred headphones
        manager.simulateHALRefresh(
            outputs: [speakers, headphones, airPodsOut],
            inputs: [],
            defaultOutputID: speakers.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == headphones.uid)

        // User selects AirPods while preferred headphones stay connected
        manager.selectOutputDevice(airPodsOut)
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)

        // Subsequent HAL refresh must NOT revert back to preferred headphones
        manager.simulateHALRefresh(
            outputs: [speakers, headphones, airPodsOut],
            inputs: [],
            defaultOutputID: airPodsOut.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)

        // Now pin AirPods as preferred, then switch to Speakers while AirPods stays connected
        manager.setPreferredOutput(to: airPodsOut)
        #expect(manager.preferredOutputUID == airPodsOut.uid)

        manager.selectOutputDevice(speakers)
        #expect(manager.currentOutputDevice?.uid == speakers.uid)

        manager.simulateHALRefresh(
            outputs: [speakers, headphones, airPodsOut],
            inputs: [],
            defaultOutputID: speakers.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == speakers.uid)
    }

    @Test("Auto-switch triggers when preferred output connects or active output unplugs")
    func autoSwitchOnPreferredConnectOrActiveDisconnect() {
        let manager = AudioDeviceManager.shared
        manager.resetTestRoutingState()
        defer { manager.resetTestRoutingState() }

        let speakers = AudioDeviceInfo(
            id: 711,
            uid: "builtin-speakers",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let headphones = AudioDeviceInfo(
            id: 712,
            uid: "wired-headphones",
            name: "External Headphones",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let airPodsOut = AudioDeviceInfo(
            id: 713,
            uid: "airpods-pro-out",
            name: "AirPods Pro",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )

        manager.preferredOutputUID = airPodsOut.uid
        manager.preferredOutputName = airPodsOut.name
        manager.autoSwitchPreferredOutput = true

        // Initial scan without AirPods leaves current output on headphones
        manager.simulateHALRefresh(
            outputs: [speakers, headphones],
            inputs: [],
            defaultOutputID: headphones.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == headphones.uid)

        // AirPods connects -> auto-switches to AirPods
        manager.simulateHALRefresh(
            outputs: [speakers, headphones, airPodsOut],
            inputs: [],
            defaultOutputID: headphones.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)

        // User switches to wired headphones while AirPods stays connected -> stays on headphones
        manager.selectOutputDevice(headphones)
        #expect(manager.currentOutputDevice?.uid == headphones.uid)

        // Wired headphones unplug -> falls back to preferred AirPods
        manager.simulateHALRefresh(
            outputs: [speakers, airPodsOut],
            inputs: [],
            defaultOutputID: speakers.id,
            defaultInputID: 0
        )
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)
    }

    @Test("AirPods output stays protected through HFP-to-A2DP bounce when mic protection fires")
    func airPodsOutputProtectedDuringMicProtection() {
        let manager = AudioDeviceManager.shared
        manager.resetTestRoutingState()
        defer { manager.resetTestRoutingState() }

        let headphones = AudioDeviceInfo(
            id: 721,
            uid: "wired-headphones",
            name: "External Headphones",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let airPodsOut = AudioDeviceInfo(
            id: 722,
            uid: "airpods-pro-out",
            name: "AirPods Pro",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )
        let usbMic = AudioDeviceInfo(
            id: 723,
            uid: "usb-maono-mic",
            name: "Maono USB Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let airPodsMic = AudioDeviceInfo(
            id: 724,
            uid: "airpods-pro-in",
            name: "AirPods Pro",
            isInput: true,
            isOutput: false,
            transportType: .bluetooth
        )

        manager.preferredOutputUID = headphones.uid
        manager.preferredOutputName = headphones.name
        manager.autoSwitchPreferredOutput = true
        manager.autoProtectMicrophoneOnBluetooth = true
        manager.lockMicrophone(to: usbMic)

        manager.simulateHALRefresh(
            outputs: [headphones],
            inputs: [usbMic],
            defaultOutputID: headphones.id,
            defaultInputID: usbMic.id
        )
        #expect(manager.currentOutputDevice?.uid == headphones.uid)
        #expect(manager.currentInputDevice?.uid == usbMic.uid)

        // User puts AirPods in ear: macOS switches both output and input to AirPods
        manager.simulateHALRefresh(
            outputs: [headphones, airPodsOut],
            inputs: [usbMic, airPodsMic],
            defaultOutputID: airPodsOut.id,
            defaultInputID: airPodsMic.id
        )
        // Output moves to AirPods (not stolen back by preferred headphones), input restored to USB mic
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)
        #expect(manager.currentInputDevice?.uid == usbMic.uid)

        // Simulate coreaudiod bouncing default output back to headphones during HFP->A2DP transition
        manager.simulateHALRefresh(
            outputs: [headphones, airPodsOut],
            inputs: [usbMic, airPodsMic],
            defaultOutputID: headphones.id,
            defaultInputID: usbMic.id
        )
        #expect(manager.currentOutputDevice?.uid == airPodsOut.uid)
    }

    @Test("Enabling isMicrophoneLocked populates lockedMicrophoneUID automatically when nil")
    func enablingMicrophoneLockPopulatesDefaultUID() {
        let manager = AudioDeviceManager.shared
        manager.resetTestRoutingState()
        defer { manager.resetTestRoutingState() }

        let usbMic = AudioDeviceInfo(
            id: 731,
            uid: "usb-maono-mic",
            name: "Maono USB Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let builtInMic = AudioDeviceInfo(
            id: 732,
            uid: "builtin-mic",
            name: "MacBook Pro Microphone",
            isInput: true,
            isOutput: false,
            transportType: .builtIn
        )

        manager.setTestState(
            availableInputs: [usbMic, builtInMic],
            availableOutputs: [],
            currentInput: usbMic
        )
        #expect(manager.lockedMicrophoneUID == nil)

        manager.isMicrophoneLocked = true
        #expect(manager.lockedMicrophoneUID == usbMic.uid)
        #expect(manager.lockedMicrophoneName == usbMic.name)
        #expect(manager.isCurrentMicrophoneLocked)
    }

    @Test("Manual Bluetooth mic selection is respected when unlocked and overridden when locked")
    func manualBluetoothMicSelectionRespectsLockState() {
        let manager = AudioDeviceManager.shared
        manager.resetTestRoutingState()
        defer { manager.resetTestRoutingState() }

        let usbMic = AudioDeviceInfo(
            id: 741,
            uid: "usb-maono-mic",
            name: "Maono USB Microphone",
            isInput: true,
            isOutput: false,
            transportType: .usb
        )
        let airPodsMic = AudioDeviceInfo(
            id: 742,
            uid: "airpods-pro-in",
            name: "AirPods Pro",
            isInput: true,
            isOutput: false,
            transportType: .bluetooth
        )

        manager.autoProtectMicrophoneOnBluetooth = true
        manager.isMicrophoneLocked = false
        manager.setTestState(
            availableInputs: [usbMic, airPodsMic],
            availableOutputs: [],
            currentInput: usbMic
        )

        // User manually selects AirPods mic while unlocked -> respected
        manager.selectInputDevice(airPodsMic)
        manager.enforceBluetoothMicProtectionIfNeeded()
        #expect(manager.currentInputDevice?.uid == airPodsMic.uid)

        manager.simulateHALRefresh(
            outputs: [],
            inputs: [usbMic, airPodsMic],
            defaultOutputID: 0,
            defaultInputID: airPodsMic.id
        )
        #expect(manager.currentInputDevice?.uid == airPodsMic.uid)

        // Lock mic to USB mic -> AirPods mic is overridden back to USB mic
        manager.lockMicrophone(to: usbMic)
        #expect(manager.currentInputDevice?.uid == usbMic.uid)

        manager.simulateHALRefresh(
            outputs: [],
            inputs: [usbMic, airPodsMic],
            defaultOutputID: 0,
            defaultInputID: airPodsMic.id
        )
        #expect(manager.currentInputDevice?.uid == usbMic.uid)
    }

    @Test("AudioProcessVolumeManager updates tap output device UID when output device changes")
    func processVolumeTapTracksOutputDeviceChanges() {
        let deviceManager = AudioDeviceManager.shared
        let mixer = AudioProcessVolumeManager.shared
        deviceManager.resetTestRoutingState()
        mixer.setTestSessions([])
        defer {
            mixer.setTestSessions([])
            deviceManager.resetTestRoutingState()
        }

        let headphones = AudioDeviceInfo(
            id: 751,
            uid: "wired-headphones",
            name: "External Headphones",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )
        let airPodsOut = AudioDeviceInfo(
            id: 752,
            uid: "airpods-pro-out",
            name: "AirPods Pro",
            isInput: false,
            isOutput: true,
            transportType: .bluetooth
        )
        let speakers = AudioDeviceInfo(
            id: 753,
            uid: "builtin-speakers",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: .builtIn
        )

        deviceManager.setTestState(
            availableInputs: [],
            availableOutputs: [headphones, airPodsOut, speakers],
            currentOutput: headphones
        )

        let spotify = AudioAppSession(
            id: "com.spotify.client",
            pid: 2001,
            processObjectIDs: [9101],
            name: "Spotify",
            bundleID: "com.spotify.client",
            isRunningOutput: true,
            isRunningInput: false,
            volume: 1.0,
            isMuted: false
        )
        mixer.setTestSessions([spotify])
        mixer.setVolume(0.55, for: "com.spotify.client")
        #expect(mixer.sessionTapOutputUIDs["com.spotify.client"] == headphones.uid)

        deviceManager.selectOutputDevice(airPodsOut)
        #expect(mixer.sessionTapOutputUIDs["com.spotify.client"] == airPodsOut.uid)

        deviceManager.selectOutputDevice(speakers)
        #expect(mixer.sessionTapOutputUIDs["com.spotify.client"] == speakers.uid)
    }

    @Test("Process PID indexing safely ignores invalid PIDs (-1/0) and deduplicates colliding PIDs")
    func processPIDIndexingHandlesNegativeAndDuplicatePIDs() {
        let entries: [(pid_t, String)] = [
            (-1, "launch-pending-a"),
            (-1, "launch-pending-b"),
            (0, "kernel"),
            (4242, "helper-process"),
            (4242, "regular-host"),
            (9001, "spotify")
        ]

        let pidMap = AudioProcessVolumeManager.buildPIDMap(entries) { first, second in
            second == "regular-host" ? second : first
        }

        #expect(pidMap[-1] == nil)
        #expect(pidMap[0] == nil)
        #expect(pidMap[4242] == "regular-host")
        #expect(pidMap[9001] == "spotify")
        #expect(pidMap.count == 2)

        let liveIndex = AudioProcessVolumeManager.indexRunningApplications(NSWorkspace.shared.runningApplications)
        #expect(liveIndex.byPID.keys.allSatisfy { $0 > 0 })
    }

    @Test("Bundle ID normalization strips nested helper suffixes and maps WebKit to Safari")
    func bundleIDNormalizationStripsNestedSuffixes() {
        #expect(
            AudioProcessVolumeManager.normalizeBundleID("com.google.Chrome.helper.renderer") == "com.google.Chrome"
        )
        #expect(
            AudioProcessVolumeManager.normalizeBundleID("com.apple.WebKit.GPU") == "com.apple.Safari"
        )
        #expect(
            AudioProcessVolumeManager.normalizeBundleID("com.apple.WebKit.WebContent") == "com.apple.Safari"
        )
        #expect(
            AudioProcessVolumeManager.normalizeBundleID("com.hnc.Discord.Helper.Plugin") == "com.hnc.Discord"
        )
        #expect(
            AudioProcessVolumeManager.normalizeBundleID("com.spotify.client") == "com.spotify.client"
        )
    }

    @Test("Process object ID normalization deduplicates and sorts deterministically")
    func processObjectIDsAreNormalizedDeterministically() {
        let normalized = AudioProcessVolumeManager.normalizedProcessObjectIDs([42, 12, 42, 7, 12, 99])
        #expect(normalized == [7, 12, 42, 99])
        #expect(AudioProcessVolumeManager.normalizedProcessObjectIDs([]) == [])
    }
}
