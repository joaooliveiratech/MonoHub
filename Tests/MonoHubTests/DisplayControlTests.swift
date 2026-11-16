import CoreGraphics
import Foundation
import Testing
@testable import MonoHub

@Suite("Controle DDC/CI e Monitores Externos (BetterDisplay Pro)", .serialized)
@MainActor
struct DisplayControlTests {

    @Test("Construção de pacotes Set VCP e cálculo de checksum XOR DDC/CI")
    func setVCPPacketGeneration() {
        // Luminance 50% (0x10, 50)
        let brightnessPacket = DDCProtocol.buildSetVCPPacket(code: .luminance, value: 50)
        #expect(brightnessPacket.count == 6)
        #expect(brightnessPacket[0] == 0x84)
        #expect(brightnessPacket[1] == 0x03)
        #expect(brightnessPacket[2] == DDCProtocol.VCPCode.luminance.rawValue)
        #expect(brightnessPacket[3] == 0x00) // high byte
        #expect(brightnessPacket[4] == 50)   // low byte

        let expectedChecksum = DDCProtocol.calculateChecksum(
            destination: DDCProtocol.i2cWriteAddress8Bit,
            bytes: [DDCProtocol.sourceAddress, 0x84, 0x03, 0x10, 0x00, 50]
        )
        #expect(brightnessPacket[5] == expectedChecksum)

        // Speaker volume 80% (0x62, 80)
        let volumePacket = DDCProtocol.buildSetVCPPacket(code: .audioVolume, value: 80)
        #expect(volumePacket[2] == DDCProtocol.VCPCode.audioVolume.rawValue)
        #expect(volumePacket[4] == 80)
        let expectedVolChecksum = DDCProtocol.calculateChecksum(
            destination: DDCProtocol.i2cWriteAddress8Bit,
            bytes: [DDCProtocol.sourceAddress, 0x84, 0x03, 0x62, 0x00, 80]
        )
        #expect(volumePacket[5] == expectedVolChecksum)

        // Mute toggle (0x8D, 1 = mute)
        let mutePacket = DDCProtocol.buildSetVCPPacket(code: .audioMute, value: 1)
        #expect(mutePacket[2] == DDCProtocol.VCPCode.audioMute.rawValue)
        #expect(mutePacket[4] == 1)

        // Sharpness (0x87, 75)
        let sharpnessPacket = DDCProtocol.buildSetVCPPacket(code: .sharpness, value: 75)
        #expect(sharpnessPacket[2] == 0x87)
        #expect(sharpnessPacket[4] == 75)
    }

    @Test("Construção de pacotes Get VCP e Capabilities Request")
    func getVCPAndCapabilitiesPacketGeneration() {
        let req = DDCProtocol.buildGetVCPPacket(code: .luminance)
        #expect(req.count == 4)
        #expect(req[0] == 0x82)
        #expect(req[1] == 0x01)
        #expect(req[2] == DDCProtocol.VCPCode.luminance.rawValue)

        let expectedChecksum = DDCProtocol.calculateChecksum(
            destination: DDCProtocol.i2cWriteAddress8Bit,
            bytes: [DDCProtocol.sourceAddress, 0x82, 0x01, 0x10]
        )
        #expect(req[3] == expectedChecksum)

        let capReq = DDCProtocol.buildCapabilitiesRequestPacket(offset: 0x0020)
        #expect(capReq.count == 5)
        #expect(capReq[0] == 0x83)
        #expect(capReq[1] == 0xF3)
        #expect(capReq[2] == 0x00)
        #expect(capReq[3] == 0x20)
    }

    @Test("Parser de resposta Get VCP Reply do monitor")
    func parseVCPReplySuccess() {
        let reply: [UInt8] = [0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 100, 0x00, 65, 0x00]
        let parsed = DDCProtocol.parseVCPReply(reply: reply, expectedCode: .luminance)

        #expect(parsed != nil)
        #expect(parsed?.current == 65)
        #expect(parsed?.max == 100)
    }

    @Test("Parser rejeita respostas com erro ou código VCP divergente")
    func parseVCPReplyErrors() {
        let errorReply: [UInt8] = [0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 100, 0x00, 50, 0x00]
        #expect(DDCProtocol.parseVCPReply(reply: errorReply, expectedCode: .luminance) == nil)

        let mismatchedReply: [UInt8] = [0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 100, 0x00, 50, 0x00]
        #expect(DDCProtocol.parseVCPReply(reply: mismatchedReply, expectedCode: .luminance) == nil)

        let shortReply: [UInt8] = [0x88, 0x02, 0x00]
        #expect(DDCProtocol.parseVCPReply(reply: shortReply, expectedCode: .luminance) == nil)
    }

    @Test("Parser de Capabilities MCCS extrai modelo, versão, VCPs, entradas e presets de cor")
    func parseMCCSCapabilitiesString() {
        let raw = "(prot(monitor)type(LCD)model(DELL U2723QE)mccs_ver(2.1)vcp(10 12 14(01 05 08 0B) 16 18 1A 60(0F 11 12 1B) 62 87 8D D6(01 04)))"
        let desc = DDCProtocol.parseCapabilitiesString(raw)

        #expect(desc.modelName == "DELL U2723QE")
        #expect(desc.mccsVersion == "2.1")
        #expect(desc.supportedVCPCodes.contains(.luminance))
        #expect(desc.supportedVCPCodes.contains(.contrast))
        #expect(desc.supportedVCPCodes.contains(.sharpness))
        #expect(desc.supportedVCPCodes.contains(.redGain))
        #expect(desc.supportedVCPCodes.contains(.inputSource))
        #expect(desc.supportedInputs.contains(.displayPort1))
        #expect(desc.supportedInputs.contains(.hdmi1))
        #expect(desc.supportedInputs.contains(.usbC))
        #expect(desc.supportedColorPresets.contains(.sRGB))
        #expect(desc.supportedColorPresets.contains(.standard6500K))
    }

    @Test("Curvas de Brilho Linear e Perceptual (Gamma 2.2)")
    func brightnessCurves() {
        let linear = BrightnessCurve.linear
        #expect(linear.transform(value: 0.0) == 0.0)
        #expect(linear.transform(value: 0.5) == 0.5)
        #expect(linear.transform(value: 1.0) == 1.0)
        #expect(linear.invert(value: 0.5) == 0.5)

        let perceptual = BrightnessCurve.perceptual
        #expect(perceptual.transform(value: 0.0) == 0.0)
        #expect(perceptual.transform(value: 1.0) == 1.0)

        let transformed = perceptual.transform(value: 0.5)
        #expect(transformed > 0.21 && transformed < 0.23)

        let restored = perceptual.invert(value: transformed)
        #expect(abs(restored - 0.5) < 0.001)
    }

    @Test("Calibração de Temperatura de Cor Kelvin e Tabela Gamma Composta (BetterDisplay Pro)")
    func colorTemperatureAndCompositeGamma() {
        // 6500K D65 neutral should return (1.0, 1.0, 1.0)
        let neutral = DisplayColorAdjustment.kelvinToRGB(kelvin: 6500)
        #expect(neutral.r == 1.0 && neutral.g == 1.0 && neutral.b == 1.0)

        // 3400K Warm night should reduce blue relative to red
        let warm = DisplayColorAdjustment.kelvinToRGB(kelvin: 3400)
        #expect(warm.r > warm.g)
        #expect(warm.g > warm.b)

        // 9000K Cool should boost blue relative to red
        let cool = DisplayColorAdjustment.kelvinToRGB(kelvin: 9000)
        #expect(cool.b > cool.r)

        // Composite transfer table with inversion and grayscale
        let linearRamp: [CGGammaValue] = (0..<256).map { CGGammaValue($0) / 255.0 }
        let adj = DisplayColorAdjustment(
            temperatureKelvin: 5000,
            redGain: 1.0,
            greenGain: 0.9,
            blueGain: 0.8,
            gammaOffset: 0.1,
            softwareContrast: 1.1,
            isGrayscale: true,
            isInverted: false
        )
        let tables = SoftwareDimmer.computeTransferTables(
            base: (red: linearRamp, green: linearRamp, blue: linearRamp),
            factor: 0.8,
            color: adj
        )
        #expect(tables.red.count == 256)
        // Because grayscale is enabled, R == G == B for every entry
        #expect(abs(tables.red[128] - tables.green[128]) < 0.0001)
        #expect(abs(tables.green[128] - tables.blue[128]) < 0.0001)
    }

    @Test("Parser VESA EDID 1.4 e Gerador de Plist de Override (HiDPI + Full RGB)")
    func edidParserAndOverridePlist() {
        let dummyDisplay = ExternalDisplayDevice(
            id: 2,
            uuid: "EDID-TEST-UUID",
            name: "Dell U2723QE",
            vendorNumber: 0x10AC,
            modelNumber: 0xD0B3,
            serialNumber: 123456,
            connectionType: .usbC,
            isBuiltIn: false,
            brightness: 0.8,
            volume: 0.5,
            contrast: 0.5,
            isMuted: false,
            supportsDDC: true,
            supportsVolume: true,
            supportsPower: true,
            supportsInputSwitch: true,
            supportsXDRBoost: true,
            maxPotentialEDR: 2.0,
            currentEDR: 1.6,
            logicalSize: CGSize(width: 2560, height: 1440),
            pixelSize: CGSize(width: 3840, height: 2160)
        )

        let rawEDID = EDIDInspectorService.shared.synthesizeHardwareEDID(for: dummyDisplay)
        #expect(rawEDID.count == 128)

        let parsed = EDIDParser.parse(
            bytes: rawEDID,
            nativePixelWidth: 3840,
            nativePixelHeight: 2160,
            maxEDRFactor: 1.6,
            maxPotentialEDRFactor: 2.0
        )
        #expect(parsed != nil)
        #expect(parsed?.manufacturerCode == "DEL")
        #expect(parsed?.manufacturerName == "Dell Inc.")
        #expect(parsed?.checksumValid == true)
        #expect(parsed?.edidVersion == "1.4")
        #expect(parsed?.supportsHDR == true)
        #expect(parsed?.maxPotentialEDRNits == 1000.0)

        let plist = EDIDParser.generateOverridePlist(
            vendorID: dummyDisplay.vendorNumber,
            productID: dummyDisplay.modelNumber,
            displayName: dummyDisplay.name,
            forceFullRGB: true,
            unlockNightShift: true
        )
        #expect(plist.contains("<key>DisplayPixelEncoding</key>"))
        #expect(plist.contains("<key>DisplaySupportsNightShift</key>"))
        #expect(plist.contains("<key>scale-resolutions</key>"))
    }

    @Test("Virtual Screens (Dummy Displays) e Picture-in-Picture (PiP) Teleprompter")
    func virtualScreensAndPiPStreams() {
        // Engines only run while the External Displays module gate is open.
        DisplayControlGate.setOpen(true)
        defer { DisplayControlGate.setOpen(false) }

        let vConfig = VirtualScreenConfig(
            name: "Sidecar iPad Pro",
            aspectRatio: .ratio4x3,
            refreshRate: 60.0,
            hiDPIEnabled: true
        )
        #expect(vConfig.maxWidth == 2880)
        #expect(vConfig.maxHeight == 2160)

        let simID = VirtualScreenEngine.shared.connectVirtualScreen(vConfig)
        #expect(simID != nil)
        if let simID {
            #expect(VirtualScreenEngine.shared.isVirtualDisplayID(simID) == true)
        }

        VirtualScreenEngine.shared.disconnectVirtualScreen(id: vConfig.id)
        #expect(VirtualScreenEngine.shared.activeDisplayID(for: vConfig.id) == nil)

        // PiP Stream Config & Teleprompter Flip
        let pipCfg = PiPStreamConfig(
            sourceDisplayID: 1,
            sourceName: "Built-in Display",
            flipMode: .horizontal,
            cropPreset: .centerZoom
        )
        #expect(pipCfg.cropPreset.normalizedRect == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))

        DisplayPiPStreamEngine.shared.startPiPStream(pipCfg)
        #expect(DisplayPiPStreamEngine.shared.activeStreams.count == 1)
        DisplayPiPStreamEngine.shared.stopPiPStream(id: pipCfg.id)
        #expect(DisplayPiPStreamEngine.shared.activeStreams.isEmpty)
    }

    @Test("Configuração individual de monitor e limites de hardware (BetterDisplay Pro)")
    func displayDeviceConfigRanges() {
        var cfg = DisplayDeviceConfig(
            dimmingMode: .combined,
            minHardwareBrightness: 0.15,
            maxHardwareBrightness: 0.95,
            minHardwareVolume: 0.05,
            maxHardwareVolume: 0.90,
            brightnessCurve: .perceptual
        )

        #expect(cfg.minHardwareBrightness == 0.15)
        #expect(cfg.maxHardwareBrightness == 0.95)
        #expect(cfg.dimmingMode == .combined)

        cfg = DisplayDeviceConfig(
            minHardwareBrightness: -0.5,
            maxHardwareBrightness: 1.5
        )
        #expect(cfg.minHardwareBrightness == 0.0)
        #expect(cfg.maxHardwareBrightness == 1.0)
    }

    @Test("Preferências de DDC, Virtual Screens e Âncoras de Layout")
    func displayPreferencesDefaults() {
        let suite = "com.antigravity.monohub.tests.display"
        let testDefaults = UserDefaults(suiteName: suite)!
        testDefaults.removePersistentDomain(forName: suite)
        defer { testDefaults.removePersistentDomain(forName: suite) }
        let prefs = DisplayControlPreferences(defaults: testDefaults)

        #expect(prefs.isDDCEnabled == true)
        #expect(prefs.targetMode == .cursor)
        #expect(prefs.enableVolumeKeys == true)
        #expect(prefs.globalDimmingMode == .combined)
        #expect(prefs.ddcWriteSleepMs >= 5 && prefs.ddcWriteSleepMs <= 100)
        #expect(prefs.ddcRetryAttempts >= 1 && prefs.ddcRetryAttempts <= 5)

        prefs.targetMode = .syncWithBuiltIn
        #expect(prefs.targetMode == .syncWithBuiltIn)

        prefs.ddcWriteSleepMs = 40
        #expect(prefs.ddcWriteSleepMs == 40)

        let vScreen = VirtualScreenConfig(name: "Test Dummy", aspectRatio: .ratio21x9)
        prefs.virtualScreens.append(vScreen)
        #expect(prefs.virtualScreens.count == 1)
    }

    @Test("HUDEvent aceita displayTitle e customIconName mantendo compatibilidade")
    func hudEventDisplayTitle() {
        let defaultHUD = HUDEvent(type: .brightness, value: 0.8)
        #expect(defaultHUD.displayTitle == nil)
        #expect(defaultHUD.customIconName == nil)
        #expect(defaultHUD.percentageString == "80%")

        let titledHUD = HUDEvent(type: .brightness, value: 0.65, displayTitle: "Dell U2720Q")
        #expect(titledHUD.displayTitle == "Dell U2720Q")
        #expect(titledHUD.percentageString == "65%")

        let headphoneHUD = HUDEvent(
            type: .volume,
            value: 0.45,
            isMuted: false,
            displayTitle: "AirPods Pro de João",
            customIconName: "airpodspro"
        )
        #expect(headphoneHUD.displayTitle == "AirPods Pro de João")
        #expect(headphoneHUD.customIconName == "airpodspro")
        #expect(headphoneHUD.percentageString == "45%")

        let mutedVolumeHUD = HUDEvent(type: .volume, value: 0.4, isMuted: true, displayTitle: "LG UltraFine")
        #expect(mutedVolumeHUD.displayTitle == "LG UltraFine")
        #expect(mutedVolumeHUD.isMuted == true)
    }

    @Test("Controle de volume não intercepta monitor externo quando fones estão ativos")
    func volumeInterceptionWithHeadphones() {
        let manager = ExternalDisplayManager.shared
        let externalDisplay = ExternalDisplayDevice(
            id: 991,
            uuid: "test-ext-display",
            name: "Dell U2723QE",
            vendorNumber: 123,
            modelNumber: 456,
            serialNumber: 789,
            connectionType: .displayPort,
            isBuiltIn: false,
            brightness: 0.7,
            volume: 0.5,
            contrast: 0.5,
            isMuted: false,
            supportsDDC: true,
            supportsVolume: true,
            supportsPower: true,
            supportsInputSwitch: true
        )
        _ = externalDisplay

        // Built-in displays never intercept volume
        let builtInDisplay = ExternalDisplayDevice(
            id: 1,
            uuid: "builtin-screen",
            name: "Built-in Retina",
            vendorNumber: 0,
            modelNumber: 0,
            serialNumber: 0,
            connectionType: .internalDisplay,
            isBuiltIn: true,
            brightness: 0.8,
            volume: 0.5,
            contrast: 0.5,
            isMuted: false,
            supportsDDC: false,
            supportsVolume: false,
            supportsPower: false,
            supportsInputSwitch: false
        )
        #expect(manager.isDisplayCurrentAudioOutput(builtInDisplay) == false)
    }

    @Test("Modelos de Entrada de Vídeo, Presets de Cor e Estados de Energia DDC")
    func inputSourcesAndPowerStates() {
        #expect(DDCProtocol.InputSource.hdmi1.rawValue == 0x11)
        #expect(DDCProtocol.InputSource.hdmi2.rawValue == 0x12)
        #expect(DDCProtocol.InputSource.displayPort1.rawValue == 0x0F)
        #expect(DDCProtocol.InputSource.usbC.rawValue == 0x1B)

        #expect(DDCProtocol.PowerState.on.rawValue == 0x01)
        #expect(DDCProtocol.PowerState.standby.rawValue == 0x02)
        #expect(DDCProtocol.PowerState.off.rawValue == 0x04)

        #expect(DDCProtocol.ColorPreset.sRGB.rawValue == 0x01)
        #expect(DDCProtocol.ColorPreset.standard6500K.rawValue == 0x05)
    }

    @Test("Detecção de divergência de layout multi-monitor evita reconfiguração espúria de tela")
    func layoutDivergenceDetection() {
        let entry = DisplayLayoutEntry(
            displayUUID: "ext-1",
            displayName: "Dell 4K",
            originX: 1920,
            originY: 0,
            width: 2560,
            height: 1440,
            isHiDPI: true,
            refreshRate: 60,
            rotation: 0,
            isMainDisplay: false,
            mirrorOfUUID: nil
        )
        let anchor = DisplayLayoutAnchor(name: "Test Layout", entries: [entry])

        var matchingDisplay = ExternalDisplayDevice(
            id: 2,
            uuid: "ext-1",
            name: "Dell 4K",
            vendorNumber: 0,
            modelNumber: 0,
            serialNumber: 0,
            connectionType: .displayPort,
            isBuiltIn: false,
            brightness: 0.8,
            volume: 0.5,
            contrast: 0.5,
            isMuted: false,
            origin: CGPoint(x: 1920, y: 0),
            logicalSize: CGSize(width: 2560, height: 1440),
            pixelSize: CGSize(width: 5120, height: 2880),
            refreshRate: 60,
            isHiDPI: true
        )

        // Same origins and rotation -> does NOT diverge
        #expect(!ResolutionAndLayoutEngine.shared.doesLayoutDiverge(from: anchor, currentDisplays: [matchingDisplay]))

        // Moved origin -> does diverge
        matchingDisplay.origin = CGPoint(x: 1800, y: 0)
        #expect(ResolutionAndLayoutEngine.shared.doesLayoutDiverge(from: anchor, currentDisplays: [matchingDisplay]))
    }

    @Test("Ciclo de vida do DisplayControlFeature e liberação de recursos de overlay")
    func displayControlFeatureLifecycle() {
        DisplayControlFeature.activate()
        #expect(DisplayControlFeature.isActive)
        #expect(ExternalDisplayManager.shared.isRunning)

        XDRAndOverlayEngine.shared.closeAllOverlays()
        VirtualScreenEngine.shared.disconnectAll()

        DisplayControlFeature.deactivate()
        #expect(!DisplayControlFeature.isActive)
        #expect(!ExternalDisplayManager.shared.isRunning)
        #expect(!DisplayControlGate.isOpen)
    }

    @Test("Módulo desligado: nenhuma engine de display executa efeitos colaterais")
    func disabledModuleIsInert() async {
        DisplayControlFeature.deactivate()
        #expect(!DisplayControlGate.isOpen)

        let manager = ExternalDisplayManager.shared
        let mainID = CGMainDisplayID()

        // Manager: no scan, no target, no key interception
        manager.refreshDisplays(readDDCValues: true)
        #expect(manager.displays.isEmpty)
        #expect(manager.resolveTargetDisplay() == nil)
        #expect(!manager.shouldInterceptVolumeKeys())
        #expect(!manager.increaseVolume())
        #expect(!manager.toggleMute())

        // Gamma tables never touched
        SoftwareDimmer.shared.applyDimming(displayID: mainID, factor: 0.3)
        SoftwareDimmer.shared.applyColorAdjustment(displayID: mainID, adjustment: DisplayColorAdjustment(temperatureKelvin: 3400))
        #expect(!SoftwareDimmer.shared.hasModifiedDisplays)

        // Overlays / blackout / XDR never engaged
        XDRAndOverlayEngine.shared.setBlackout(displayID: mainID, enabled: true)
        XDRAndOverlayEngine.shared.setOverlayDimmingAlpha(displayID: mainID, alpha: 0.9)
        XDRAndOverlayEngine.shared.setXDRBoost(displayID: mainID, factor: 1.8, enabled: true)
        #expect(!XDRAndOverlayEngine.shared.isBlackedOut(displayID: mainID))
        #expect(XDRAndOverlayEngine.shared.currentXDRBoost(for: mainID) == 1.0)
        #expect(!XDRAndOverlayEngine.shared.hasActiveOverlays)

        // No display reconfiguration, virtual screens or DDC/CI I2C traffic
        #expect(!ResolutionAndLayoutEngine.shared.setMainDisplay(mainID))
        #expect(!ResolutionAndLayoutEngine.shared.setRotation(.degree90, for: mainID))
        #expect(!ResolutionAndLayoutEngine.shared.setMirroring(displayID: mainID, masterDisplayID: nil))
        #expect(VirtualScreenEngine.shared.connectVirtualScreen(VirtualScreenConfig(name: "Test")) == nil)
        let wrote = await DDCCommunicationService.shared.write(displayID: mainID, code: .luminance, value: 50)
        #expect(!wrote)
        let read = await DDCCommunicationService.shared.read(displayID: mainID, code: .luminance)
        #expect(read == nil)
    }

    @Test("Assinatura de topologia é estável sem mudança real de monitores (troca de Space não reconfigura)")
    func topologySignatureIsStable() {
        let first = ExternalDisplayManager.currentTopologySignature()
        let second = ExternalDisplayManager.currentTopologySignature()
        #expect(first == second)
    }
}
