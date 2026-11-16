import AppKit
import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class ExternalDisplayManager {
    static let shared = ExternalDisplayManager()

    private(set) var displays: [ExternalDisplayDevice] = []
    private(set) var availableModesByDisplay: [CGDirectDisplayID: [DisplayModeItem]] = [:]
    private(set) var edidByDisplay: [CGDirectDisplayID: EDIDDiagnosticInfo] = [:]

    var isRunning: Bool { isStarted }

    var activeExternalDisplays: [ExternalDisplayDevice] {
        guard isStarted else { return [] }
        return displays.filter { !$0.isBuiltIn }
    }

    var hasActiveExternalDisplays: Bool {
        guard isStarted else { return false }
        return !activeExternalDisplays.isEmpty
    }

    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var pendingScreenChange: Task<Void, Never>?
    @ObservationIgnored private var lastTopologySignature: String?

    static let screenChangeDebounce: Duration = .milliseconds(1200)

    private init() {}

    func start() {
        guard !isStarted, DisplayControlGate.isOpen else { return }
        isStarted = true

        for idx in DisplayControlPreferences.shared.virtualScreens.indices {
            if DisplayControlPreferences.shared.virtualScreens[idx].autoConnectOnStartup {
                let cfg = DisplayControlPreferences.shared.virtualScreens[idx]
                if let assignedID = VirtualScreenEngine.shared.connectVirtualScreen(cfg) {
                    DisplayControlPreferences.shared.virtualScreens[idx].isConnected = true
                    DisplayControlPreferences.shared.virtualScreens[idx].activeDisplayID = assignedID
                }
            }
        }

        lastTopologySignature = Self.currentTopologySignature()
        refreshDisplays(readDDCValues: true)

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { manager in
            manager.scheduleScreenParametersChanged()
        }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { _ in
            SoftwareDimmer.shared.restoreAll()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { _ in
            SoftwareDimmer.shared.restoreAll()
        }
    }

    func stop() {
        for entry in observers {
            entry.center.removeObserver(entry.token)
        }
        observers.removeAll()
        pendingScreenChange?.cancel()
        pendingScreenChange = nil
        lastTopologySignature = nil

        if isStarted {
            XDRAndOverlayEngine.shared.restoreAllBlackouts()
            XDRAndOverlayEngine.shared.closeAllOverlays()
            SoftwareDimmer.shared.restoreAll()
            DisplayPiPStreamEngine.shared.stopAllStreams()
            VirtualScreenEngine.shared.disconnectAll()
            DDCCommunicationService.shared.releaseServices()
        }
        isStarted = false
        displays.removeAll()
        availableModesByDisplay.removeAll()
        edidByDisplay.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor (ExternalDisplayManager) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, DisplayControlGate.isOpen else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func scheduleScreenParametersChanged() {
        pendingScreenChange?.cancel()
        pendingScreenChange = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.screenChangeDebounce)
            guard !Task.isCancelled else { return }
            self?.handleScreenParametersChanged()
        }
    }

    static func currentTopologySignature() -> String {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return "" }
        return (0..<Int(count)).map { i -> String in
            let id = ids[i]
            let b = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            return [
                "\(id)",
                "\(Int(b.origin.x)),\(Int(b.origin.y)),\(Int(b.width)),\(Int(b.height))",
                "\(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0)@\(Int(mode?.refreshRate ?? 0))",
                "r\(Int(CGDisplayRotation(id)))",
                "m\(CGDisplayMirrorsDisplay(id))"
            ].joined(separator: "|")
        }.sorted().joined(separator: ";")
    }

    private func handleScreenParametersChanged() {
        guard isStarted, DisplayControlGate.isOpen else { return }

        let signature = Self.currentTopologySignature()
        guard signature != lastTopologySignature else { return }
        lastTopologySignature = signature

        refreshDisplays()
        XDRAndOverlayEngine.shared.repositionOverlays()

        let prefs = DisplayControlPreferences.shared
        if prefs.isLayoutProtectionEnabled, let lockedAnchor = prefs.savedLayoutAnchors.first {
            if ResolutionAndLayoutEngine.shared.doesLayoutDiverge(from: lockedAnchor, currentDisplays: displays) {
                _ = ResolutionAndLayoutEngine.shared.restoreLayout(lockedAnchor, currentDisplays: displays)
            }
        }

        if prefs.autoBlackoutBuiltInOnExternal, let builtIn = displays.first(where: { $0.isBuiltIn }) {
            let shouldBlackout = !activeExternalDisplays.isEmpty
            XDRAndOverlayEngine.shared.setBlackout(displayID: builtIn.id, enabled: shouldBlackout)
        }
    }

    func refreshDisplays(readDDCValues: Bool = false) {
        guard isStarted, DisplayControlGate.isOpen else { return }
        let ddcEnabled = DisplayControlPreferences.shared.isDDCEnabled
        if ddcEnabled {
            DDCCommunicationService.shared.refreshServices()
        } else {
            DDCCommunicationService.shared.releaseServices()
        }

        var activeIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &activeIDs, &count) == .success else { return }

        let activeScreens = NSScreen.screens
        let mainDisplayID = CGMainDisplayID()
        var newDisplays: [ExternalDisplayDevice] = []

        for i in 0..<Int(count) {
            let displayID = activeIDs[i]
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let isVirtual = VirtualScreenEngine.shared.isVirtualDisplayID(displayID)

            let matchedScreen = activeScreens.first { screen in
                let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                return num == displayID
            }

            let name: String
            if let matchedScreen {
                name = matchedScreen.localizedName
            } else if isBuiltIn {
                name = localized("Built-in Display")
            } else if isVirtual {
                name = localized("Virtual Screen")
            } else {
                name = "\(localized("External Display")) #\(i)"
            }

            let cfuuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
            let uuid = cfuuid.flatMap { CFUUIDCreateString(nil, $0) as String? } ?? String(displayID)
            let vendor = CGDisplayVendorNumber(displayID)
            let model = CGDisplayModelNumber(displayID)
            let serial = CGDisplaySerialNumber(displayID)

            let connectionType = detectConnectionType(displayID: displayID, name: name, isBuiltIn: isBuiltIn, isVirtual: isVirtual)
            let supportsDDC = ddcEnabled && !isBuiltIn && !isVirtual && DDCCommunicationService.shared.hasDDCService(for: displayID)

            let maxPotentialEDR = Double(matchedScreen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0)
            let currentEDR = Double(matchedScreen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0)
            let supportsXDRBoost = maxPotentialEDR > 1.05 || isBuiltIn

            let bounds = CGDisplayBounds(displayID)
            let cgMode = CGDisplayCopyDisplayMode(displayID)
            let logicalW = cgMode?.width ?? Int(bounds.width)
            let logicalH = cgMode?.height ?? Int(bounds.height)
            let pixelW = cgMode?.pixelWidth ?? logicalW
            let pixelH = cgMode?.pixelHeight ?? logicalH
            let rate = (cgMode?.refreshRate ?? 60.0) > 0 ? (cgMode?.refreshRate ?? 60.0) : 60.0
            let isHiDPI = pixelW > logicalW

            let rotation = ResolutionAndLayoutEngine.shared.currentRotation(for: displayID)
            let isMain = (displayID == mainDisplayID)
            let mirrorMasterRaw = CGDisplayMirrorsDisplay(displayID)
            let mirrorMasterID: CGDirectDisplayID? = (mirrorMasterRaw != kCGNullDirectDisplay && mirrorMasterRaw != 0) ? mirrorMasterRaw : nil
            let isBlackedOut = XDRAndOverlayEngine.shared.isBlackedOut(displayID: displayID)

            let existing = displays.first { $0.id == displayID }
            let initialBrightness = existing?.brightness ?? (isBuiltIn ? DisplayBrightnessManager.shared.currentBrightness : 0.7)
            let initialVolume = existing?.volume ?? 0.5
            let initialContrast = existing?.contrast ?? 0.5
            let initialSharpness = existing?.sharpness ?? 0.5

            let device = ExternalDisplayDevice(
                id: displayID,
                uuid: uuid,
                name: name,
                vendorNumber: vendor,
                modelNumber: model,
                serialNumber: serial,
                connectionType: connectionType,
                isBuiltIn: isBuiltIn,
                isVirtual: isVirtual,
                brightness: initialBrightness,
                volume: initialVolume,
                contrast: initialContrast,
                sharpness: initialSharpness,
                redGainDDC: existing?.redGainDDC ?? 0.5,
                greenGainDDC: existing?.greenGainDDC ?? 0.5,
                blueGainDDC: existing?.blueGainDDC ?? 0.5,
                isMuted: existing?.isMuted ?? false,
                inputSource: existing?.inputSource,
                colorPreset: existing?.colorPreset,
                powerState: existing?.powerState ?? .on,
                rotation: rotation,
                isMainDisplay: isMain,
                mirrorMasterDisplayID: mirrorMasterID,
                isBlackedOut: isBlackedOut,
                supportsDDC: supportsDDC,
                supportsVolume: supportsDDC,
                supportsPower: supportsDDC,
                supportsInputSwitch: supportsDDC,
                supportsXDRBoost: supportsXDRBoost,
                maxPotentialEDR: maxPotentialEDR,
                currentEDR: currentEDR,
                origin: bounds.origin,
                logicalSize: CGSize(width: logicalW, height: logicalH),
                pixelSize: CGSize(width: pixelW, height: pixelH),
                refreshRate: rate,
                isHiDPI: isHiDPI
            )

            newDisplays.append(device)

            let includeDupes = DisplayControlPreferences.shared.showLowResolutionDuplicateModes
            availableModesByDisplay[displayID] = ResolutionAndLayoutEngine.shared.availableModes(for: displayID, includeLowResDuplicates: includeDupes)
            if let edid = EDIDInspectorService.shared.inspectEDID(for: device) {
                edidByDisplay[displayID] = edid
            }

            let cfg = DisplayControlPreferences.shared.config(for: uuid)
            if !cfg.colorAdjustment.isIdentity {
                SoftwareDimmer.shared.applyColorAdjustment(displayID: displayID, adjustment: cfg.colorAdjustment)
            }
            if cfg.xdrConfig.isEnabled && cfg.xdrConfig.boostFactor > 1.01 {
                XDRAndOverlayEngine.shared.setXDRBoost(displayID: displayID, factor: cfg.xdrConfig.boostFactor, enabled: true)
            }
        }

        self.displays = newDisplays

        guard ddcEnabled else { return }
        let shouldRead = readDDCValues && DisplayControlPreferences.shared.readOnStartup
        Task {

            try? await Task.sleep(for: .milliseconds(500))
            guard self.isStarted, DisplayControlGate.isOpen else { return }
            for idx in displays.indices where !displays[idx].isBuiltIn && !displays[idx].isVirtual {
                let hasService = DDCCommunicationService.shared.hasDDCService(for: displays[idx].id)
                if displays[idx].supportsDDC != hasService {
                    displays[idx].supportsDDC = hasService
                    displays[idx].supportsVolume = hasService
                    displays[idx].supportsPower = hasService
                    displays[idx].supportsInputSwitch = hasService
                }
            }
            guard shouldRead else { return }
            for display in activeExternalDisplays where display.supportsDDC {
                await readDisplayValues(displayID: display.id)
            }
        }
    }

    func resolveTargetDisplay() -> ExternalDisplayDevice? {
        guard isStarted else { return nil }
        let prefs = DisplayControlPreferences.shared
        guard hasActiveExternalDisplays else { return displays.first { $0.isBuiltIn } }

        switch prefs.targetMode {
        case .cursor:
            let mouseLoc = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }),
               let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let target = displays.first(where: { $0.id == num }) {
                return target
            }
            return activeExternalDisplays.first

        case .focusedWindow:
            if let app = NSWorkspace.shared.frontmostApplication,
               let screen = NSScreen.main,
               let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let target = displays.first(where: { $0.id == num }) {
                _ = app
                return target
            }
            return activeExternalDisplays.first

        case .customSingle:
            if !prefs.primaryDisplayUUID.isEmpty,
               let target = displays.first(where: { $0.uuid == prefs.primaryDisplayUUID }) {
                return target
            }
            return activeExternalDisplays.first

        case .allDisplays, .syncWithBuiltIn:
            return activeExternalDisplays.first
        }
    }

    func isDisplayCurrentAudioOutput(_ display: ExternalDisplayDevice) -> Bool {
        guard !display.isBuiltIn else { return false }
        if AudioDeviceManager.shared.currentOutputDevice == nil {
            AudioDeviceManager.shared.refreshDevices()
        }
        guard let currentAudio = AudioDeviceManager.shared.currentOutputDevice else {
            return false
        }
        switch currentAudio.transportType {
        case .bluetooth, .builtIn, .airPlay, .continuity:

            return false
        case .hdmi, .displayPort:
            let normDisplay = display.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normAudio = currentAudio.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if normDisplay == normAudio || normDisplay.contains(normAudio) || normAudio.contains(normDisplay) {
                return true
            }
            if activeExternalDisplays.count == 1 {
                return true
            }
            return false
        case .usb:
            let normDisplay = display.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normAudio = currentAudio.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return normDisplay == normAudio || normDisplay.contains(normAudio) || normAudio.contains(normDisplay)
        case .virtual, .other:
            let normDisplay = display.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normAudio = currentAudio.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return !normDisplay.isEmpty && !normAudio.isEmpty && (normDisplay.contains(normAudio) || normAudio.contains(normDisplay))
        }
    }

    func shouldInterceptVolumeKeys() -> Bool {
        guard isStarted else { return false }
        guard DisplayControlPreferences.shared.enableVolumeKeys else { return false }
        guard let target = resolveTargetDisplay(), !target.isBuiltIn else { return false }
        let cfg = DisplayControlPreferences.shared.config(for: target.uuid)
        guard cfg.isAudioEnabled && target.supportsVolume else { return false }
        return isDisplayCurrentAudioOutput(target)
    }

    func increaseBrightness(step: Float = 0.0625) {
        guard isStarted else { return }
        let prefs = DisplayControlPreferences.shared
        if prefs.targetMode == .allDisplays {
            for display in activeExternalDisplays {
                adjustBrightness(for: display, delta: step)
            }
        } else if let target = resolveTargetDisplay() {
            adjustBrightness(for: target, delta: step)
        }
    }

    func decreaseBrightness(step: Float = 0.0625) {
        guard isStarted else { return }
        let prefs = DisplayControlPreferences.shared
        if prefs.targetMode == .allDisplays {
            for display in activeExternalDisplays {
                adjustBrightness(for: display, delta: -step)
            }
        } else if let target = resolveTargetDisplay() {
            adjustBrightness(for: target, delta: -step)
        }
    }

    private func adjustBrightness(for display: ExternalDisplayDevice, delta: Float) {
        let cfg = DisplayControlPreferences.shared.config(for: display.uuid)
        let maxLimit: Float = (cfg.xdrConfig.isEnabled && display.supportsXDRBoost) ? 2.0 : 1.0
        let newBrightness = max(0.0, min(maxLimit, display.brightness + delta))
        setBrightness(displayID: display.id, value: newBrightness)
    }

    func setBrightness(displayID: CGDirectDisplayID, value: Float) {
        guard isStarted else { return }
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        var device = displays[idx]
        let cfg = DisplayControlPreferences.shared.config(for: device.uuid)
        let maxLimit: Float = (cfg.xdrConfig.isEnabled && device.supportsXDRBoost) ? 2.0 : 1.0
        let clamped = max(0.0, min(maxLimit, value))
        device.brightness = clamped
        displays[idx] = device

        if clamped > 1.0 {
            XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: displayID, alpha: 0.0)
            SoftwareDimmer.shared.applyDimming(displayID: displayID, factor: 1.0)
            XDRAndOverlayEngine.shared.setXDRBoost(displayID: displayID, factor: clamped, enabled: true)
            DisplayControlPreferences.shared.updateConfig(for: device.uuid) {
                $0.xdrConfig.isEnabled = true
                $0.xdrConfig.boostFactor = clamped
            }
            if device.isBuiltIn {
                DisplayBrightnessManager.shared.setBrightness(1.0)
            }
            let title = DisplayControlPreferences.shared.showDisplayTitleInHUD ? "\(device.name) (XDR)" : nil
            HUDManager.shared.showHUD(type: .brightness, value: min(1.0, clamped), displayTitle: title)
            return
        } else {
            XDRAndOverlayEngine.shared.setXDRBoost(displayID: displayID, factor: 1.0, enabled: false)
        }

        if device.isBuiltIn {

            if cfg.allowSubZeroOverlayDimming && clamped < 0.08 {
                let overlayAlpha = CGFloat((0.08 - clamped) / 0.08) * 0.92
                XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: displayID, alpha: overlayAlpha)
            } else {
                XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: displayID, alpha: 0.0)
            }
            DisplayBrightnessManager.shared.setBrightness(clamped)
            if DisplayControlPreferences.shared.syncBrightnessWithBuiltIn {
                for ext in activeExternalDisplays {
                    applyBrightnessToExternal(ext, value: clamped)
                }
            }
            return
        }

        applyBrightnessToExternal(device, value: clamped)

        let title = DisplayControlPreferences.shared.showDisplayTitleInHUD ? device.name : nil
        HUDManager.shared.showHUD(type: .brightness, value: clamped, displayTitle: title)
    }

    private func applyBrightnessToExternal(_ display: ExternalDisplayDevice, value: Float) {
        let prefs = DisplayControlPreferences.shared
        let cfg = prefs.config(for: display.uuid)
        guard cfg.isBrightnessEnabled else { return }

        let minHw = cfg.minHardwareBrightness
        let maxHw = cfg.maxHardwareBrightness
        let curve = cfg.brightnessCurve
        let curvedValue = curve.transform(value: value)

        switch cfg.dimmingMode {
        case .combined:
            if curvedValue >= minHw && minHw > 0.0 {
                XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: 0.0)
                SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: 1.0)
                let hwRange = max(0.01, maxHw - minHw)
                let hwNormalized = (curvedValue - minHw) / hwRange
                let ddcValue = UInt16(round(hwNormalized * 100.0))
                sendDDCWrite(displayID: display.id, code: .luminance, value: ddcValue)
            } else if minHw == 0.0 && curvedValue >= 0.12 {
                XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: 0.0)
                SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: 1.0)
                let ddcValue = UInt16(round((curvedValue * maxHw) * 100.0))
                sendDDCWrite(displayID: display.id, code: .luminance, value: ddcValue)
            } else {

                let threshold = max(0.12, minHw)
                sendDDCWrite(displayID: display.id, code: .luminance, value: UInt16(round(minHw * 100.0)))
                let softFactor = max(0.05, curvedValue / max(0.001, threshold))
                SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: softFactor)
                if cfg.allowSubZeroOverlayDimming {
                    let overlayAlpha = CGFloat(max(0.0, 1.0 - softFactor)) * 0.96
                    XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: overlayAlpha)
                }
            }

        case .hardwareOnly:
            XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: 0.0)
            SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: 1.0)
            let hwRange = max(0.01, maxHw - minHw)
            let mapped = minHw + curvedValue * hwRange
            let ddcValue = UInt16(round(mapped * 100.0))
            sendDDCWrite(displayID: display.id, code: .luminance, value: ddcValue)

        case .softwareOnly:
            XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: 0.0)
            SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: curvedValue)

        case .overlayOnly:
            SoftwareDimmer.shared.applyDimming(displayID: display.id, factor: 1.0)
            let alpha = CGFloat(max(0.0, min(0.98, 1.0 - curvedValue)))
            XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: alpha)

        case .disabled:
            XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: display.id, alpha: 0.0)
        }
    }

    @discardableResult
    func increaseVolume(step: Float = 0.0625) -> Bool {
        guard isStarted else { return false }
        guard let target = resolveTargetDisplay(), !target.isBuiltIn else { return false }
        let newVol = max(0.0, min(1.0, target.volume + step))
        setVolume(displayID: target.id, value: newVol)
        return true
    }

    @discardableResult
    func decreaseVolume(step: Float = 0.0625) -> Bool {
        guard isStarted else { return false }
        guard let target = resolveTargetDisplay(), !target.isBuiltIn else { return false }
        let newVol = max(0.0, min(1.0, target.volume - step))
        setVolume(displayID: target.id, value: newVol)
        return true
    }

    func setVolume(displayID: CGDirectDisplayID, value: Float) {
        guard isStarted else { return }
        let clamped = max(0.0, min(1.0, value))
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        var device = displays[idx]
        device.volume = clamped
        if device.isMuted && clamped > 0 {
            device.isMuted = false
        }
        displays[idx] = device

        let cfg = DisplayControlPreferences.shared.config(for: device.uuid)
        let minVol = cfg.minHardwareVolume
        let maxVol = cfg.maxHardwareVolume
        let mapped = minVol + clamped * max(0.01, maxVol - minVol)
        let ddcVal = UInt16(round(mapped * 100.0))

        sendDDCWrite(displayID: displayID, code: .audioVolume, value: ddcVal)

        let title = DisplayControlPreferences.shared.showDisplayTitleInHUD ? device.name : nil
        HUDManager.shared.showHUD(type: .volume, value: clamped, isMuted: device.isMuted, displayTitle: title)
    }

    @discardableResult
    func toggleMute(displayID: CGDirectDisplayID? = nil) -> Bool {
        guard isStarted else { return false }
        let targetID = displayID ?? resolveTargetDisplay()?.id
        guard let targetID, let idx = displays.firstIndex(where: { $0.id == targetID }) else { return false }
        var device = displays[idx]
        device.isMuted.toggle()
        displays[idx] = device

        let muteVal: UInt16 = device.isMuted ? 1 : 2
        sendDDCWrite(displayID: targetID, code: .audioMute, value: muteVal)

        let title = DisplayControlPreferences.shared.showDisplayTitleInHUD ? device.name : nil
        HUDManager.shared.showHUD(type: .volume, value: device.volume, isMuted: device.isMuted, displayTitle: title)
        return true
    }

    func setContrast(displayID: CGDirectDisplayID, value: Float) {
        guard isStarted else { return }
        let clamped = max(0.0, min(1.0, value))
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].contrast = clamped
        let ddcVal = UInt16(round(clamped * 100.0))
        sendDDCWrite(displayID: displayID, code: .contrast, value: ddcVal)
    }

    func setSharpness(displayID: CGDirectDisplayID, value: Float) {
        guard isStarted else { return }
        let clamped = max(0.0, min(1.0, value))
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].sharpness = clamped
        let ddcVal = UInt16(round(clamped * 100.0))
        sendDDCWrite(displayID: displayID, code: .sharpness, value: ddcVal)
    }

    func setHardwareRGBGain(displayID: CGDirectDisplayID, red: Float, green: Float, blue: Float) {
        guard isStarted else { return }
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].redGainDDC = max(0.0, min(1.0, red))
        displays[idx].greenGainDDC = max(0.0, min(1.0, green))
        displays[idx].blueGainDDC = max(0.0, min(1.0, blue))
        sendDDCWrite(displayID: displayID, code: .redGain, value: UInt16(round(displays[idx].redGainDDC * 100.0)))
        sendDDCWrite(displayID: displayID, code: .greenGain, value: UInt16(round(displays[idx].greenGainDDC * 100.0)))
        sendDDCWrite(displayID: displayID, code: .blueGain, value: UInt16(round(displays[idx].blueGainDDC * 100.0)))
    }

    func setColorPreset(displayID: CGDirectDisplayID, preset: DDCProtocol.ColorPreset) {
        guard isStarted else { return }
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].colorPreset = preset
        sendDDCWrite(displayID: displayID, code: .colorPreset, value: preset.rawValue)
    }

    func setInputSource(displayID: CGDirectDisplayID, source: DDCProtocol.InputSource) {
        guard isStarted else { return }
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].inputSource = source
        sendDDCWrite(displayID: displayID, code: .inputSource, value: source.rawValue)
    }

    func setPowerState(displayID: CGDirectDisplayID, state: DDCProtocol.PowerState) {
        guard isStarted else { return }
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].powerState = state
        sendDDCWrite(displayID: displayID, code: .powerControl, value: state.rawValue)
    }

    func sendFactoryReset(displayID: CGDirectDisplayID) {
        guard isStarted else { return }
        sendDDCWrite(displayID: displayID, code: .factoryReset, value: 1)
    }

    func updateSoftwareColor(for display: ExternalDisplayDevice, _ modify: (inout DisplayColorAdjustment) -> Void) {
        guard isStarted else { return }
        DisplayControlPreferences.shared.updateConfig(for: display.uuid) { cfg in
            modify(&cfg.colorAdjustment)
        }
        let updated = DisplayControlPreferences.shared.config(for: display.uuid).colorAdjustment
        SoftwareDimmer.shared.applyColorAdjustment(displayID: display.id, adjustment: updated)
    }

    func resetSoftwareColor(for display: ExternalDisplayDevice) {
        guard isStarted else { return }
        DisplayControlPreferences.shared.updateConfig(for: display.uuid) { cfg in
            cfg.colorAdjustment = DisplayColorAdjustment()
        }
        SoftwareDimmer.shared.applyColorAdjustment(displayID: display.id, adjustment: DisplayColorAdjustment())
    }

    func setXDRUpscaling(for display: ExternalDisplayDevice, enabled: Bool, factor: Float) {
        guard isStarted else { return }
        let clampedFactor = max(1.0, min(2.0, factor))
        DisplayControlPreferences.shared.updateConfig(for: display.uuid) { cfg in
            cfg.xdrConfig.isEnabled = enabled
            cfg.xdrConfig.boostFactor = clampedFactor
        }
        XDRAndOverlayEngine.shared.setXDRBoost(displayID: display.id, factor: clampedFactor, enabled: enabled)
        if let idx = displays.firstIndex(where: { $0.id == display.id }) {
            displays[idx].brightness = enabled ? clampedFactor : min(1.0, displays[idx].brightness)
        }
    }

    func toggleBlackout(for display: ExternalDisplayDevice) {
        guard isStarted else { return }
        let current = XDRAndOverlayEngine.shared.isBlackedOut(displayID: display.id)
        let next = !current
        XDRAndOverlayEngine.shared.setBlackout(displayID: display.id, enabled: next)
        if let idx = displays.firstIndex(where: { $0.id == display.id }) {
            displays[idx].isBlackedOut = next
        }
    }

    func readDisplayValues(displayID: CGDirectDisplayID) async {
        guard isStarted else { return }
        let prefs = DisplayControlPreferences.shared
        let retries = prefs.ddcRetryAttempts
        let sleepMs = prefs.ddcReadSleepMs

        if let (curBright, maxBright) = await DDCCommunicationService.shared.read(
            displayID: displayID,
            code: .luminance,
            retries: retries,
            sleepMs: sleepMs
        ) {
            let normalized = maxBright > 0 ? Float(curBright) / Float(maxBright) : 0.5
            if let idx = displays.firstIndex(where: { $0.id == displayID }) {
                displays[idx].brightness = normalized
                displays[idx].supportsDDC = true
            }
        }

        if let (curVol, maxVol) = await DDCCommunicationService.shared.read(
            displayID: displayID,
            code: .audioVolume,
            retries: retries,
            sleepMs: sleepMs
        ) {
            let normalized = maxVol > 0 ? Float(curVol) / Float(maxVol) : 0.5
            if let idx = displays.firstIndex(where: { $0.id == displayID }) {
                displays[idx].volume = normalized
                displays[idx].supportsVolume = true
            }
        }
    }

    private func sendDDCWrite(displayID: CGDirectDisplayID, code: DDCProtocol.VCPCode, value: UInt16) {
        let prefs = DisplayControlPreferences.shared
        guard isStarted, prefs.isDDCEnabled, DisplayControlGate.isOpen else { return }
        let retries = prefs.ddcRetryAttempts
        let sleepMs = prefs.ddcWriteSleepMs

        Task {
            _ = await DDCCommunicationService.shared.write(
                displayID: displayID,
                code: code,
                value: value,
                retries: retries,
                sleepMs: sleepMs
            )
        }
    }

    private func detectConnectionType(displayID: CGDirectDisplayID, name: String, isBuiltIn: Bool, isVirtual: Bool) -> DisplayConnectionType {
        if isBuiltIn { return .internalDisplay }
        if isVirtual { return .virtualDisplay }
        let lower = name.lowercased()
        if lower.contains("sidecar") || lower.contains("ipad") || lower.contains("airplay") {
            return .sidecarAirPlay
        }
        if lower.contains("hdmi") { return .hdmi }
        if lower.contains("displayport") || lower.contains("dp") { return .displayPort }
        if lower.contains("thunderbolt") || lower.contains("studio display") || lower.contains("xdr") { return .thunderbolt }
        if lower.contains("type-c") || lower.contains("usb-c") { return .usbC }
        return .displayPort
    }
}
