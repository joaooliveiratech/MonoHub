import Foundation

nonisolated enum DDCProtocol {

    static let i2cAddress7Bit: UInt8 = 0x37
    static let i2cWriteAddress8Bit: UInt8 = 0x6E
    static let sourceAddress: UInt8 = 0x51

    enum VCPCode: UInt8, Sendable, CaseIterable, Identifiable, Codable {
        case factoryReset = 0x04
        case restoreLuminanceContrast = 0x05
        case restoreColor = 0x08
        case colorTemperatureIncrement = 0x0B
        case colorTemperatureRequest = 0x0C
        case luminance = 0x10
        case contrast = 0x12
        case colorPreset = 0x14
        case redGain = 0x16
        case greenGain = 0x18
        case blueGain = 0x1A
        case inputSource = 0x60
        case audioVolume = 0x62
        case redBlackLevel = 0x6C
        case greenBlackLevel = 0x6E
        case blueBlackLevel = 0x70
        case displayScaling = 0x86
        case sharpness = 0x87
        case audioMute = 0x8D
        case audioTreble = 0x8F
        case audioBass = 0x91
        case audioBalance = 0x93
        case imageOrientation = 0xAA
        case osdControl = 0xCA
        case osdLanguage = 0xCC
        case powerControl = 0xD6
        case kvmSwitch = 0xE7
        case pbpMode = 0xE9

        var id: UInt8 { rawValue }

        var localizedName: String {
            switch self {
            case .factoryReset: return localized("Factory Reset")
            case .restoreLuminanceContrast: return localized("Reset Brightness & Contrast")
            case .restoreColor: return localized("Reset Color Defaults")
            case .colorTemperatureIncrement: return localized("Color Temperature Step")
            case .colorTemperatureRequest: return localized("Color Temperature")
            case .luminance: return localized("Brightness")
            case .contrast: return localized("Contrast")
            case .colorPreset: return localized("Color Preset")
            case .redGain: return localized("Red Gain")
            case .greenGain: return localized("Green Gain")
            case .blueGain: return localized("Blue Gain")
            case .inputSource: return localized("Input Source")
            case .audioVolume: return localized("Volume")
            case .redBlackLevel: return localized("Red Black Level")
            case .greenBlackLevel: return localized("Green Black Level")
            case .blueBlackLevel: return localized("Blue Black Level")
            case .displayScaling: return localized("Hardware Scaling")
            case .sharpness: return localized("Sharpness")
            case .audioMute: return localized("Mute")
            case .audioTreble: return localized("Audio Treble")
            case .audioBass: return localized("Audio Bass")
            case .audioBalance: return localized("Audio Balance")
            case .imageOrientation: return localized("Hardware Orientation")
            case .osdControl: return localized("OSD Lock")
            case .osdLanguage: return localized("OSD Language")
            case .powerControl: return localized("Power Mode")
            case .kvmSwitch: return localized("KVM USB Switch")
            case .pbpMode: return localized("Hardware PbP/PiP")
            }
        }
    }

    enum InputSource: UInt16, Sendable, CaseIterable, Identifiable, Codable {
        case displayPort1 = 0x0F
        case displayPort2 = 0x10
        case hdmi1 = 0x11
        case hdmi2 = 0x12
        case hdmi3 = 0x13
        case hdmi4 = 0x14
        case usbC = 0x1B
        case thunderbolt = 0x1C
        case analogVGA = 0x01
        case dvi = 0x03
        case dvi2 = 0x04

        var id: UInt16 { rawValue }

        var title: String {
            switch self {
            case .displayPort1: return "DisplayPort 1"
            case .displayPort2: return "DisplayPort 2"
            case .hdmi1: return "HDMI 1"
            case .hdmi2: return "HDMI 2"
            case .hdmi3: return "HDMI 3"
            case .hdmi4: return "HDMI 4"
            case .usbC: return "USB-C / Thunderbolt"
            case .thunderbolt: return "Thunderbolt 2"
            case .analogVGA: return "VGA"
            case .dvi: return "DVI 1"
            case .dvi2: return "DVI 2"
            }
        }

        var systemImage: String {
            switch self {
            case .displayPort1, .displayPort2: return "display"
            case .hdmi1, .hdmi2, .hdmi3, .hdmi4: return "cable.connector"
            case .usbC, .thunderbolt: return "cable.connector.horizontal"
            case .analogVGA, .dvi, .dvi2: return "tv"
            }
        }
    }

    enum ColorPreset: UInt16, Sendable, CaseIterable, Identifiable, Codable {
        case sRGB = 0x01
        case native = 0x02
        case warm4000K = 0x03
        case warm5000K = 0x04
        case standard6500K = 0x05
        case cool7500K = 0x06
        case cool9300K = 0x08
        case user1 = 0x0B
        case user2 = 0x0C

        var id: UInt16 { rawValue }

        var title: String {
            switch self {
            case .sRGB: return "sRGB"
            case .native: return localized("Native")
            case .warm4000K: return "4000K (Warm)"
            case .warm5000K: return "5000K (D50)"
            case .standard6500K: return "6500K (D65)"
            case .cool7500K: return "7500K (Cool)"
            case .cool9300K: return "9300K (High Cool)"
            case .user1: return localized("Custom User 1")
            case .user2: return localized("Custom User 2")
            }
        }
    }

    enum PowerState: UInt16, Sendable, CaseIterable, Identifiable, Codable {
        case on = 0x01
        case standby = 0x02
        case suspend = 0x03
        case off = 0x04
        case hardOff = 0x05

        var id: UInt16 { rawValue }

        var title: String {
            switch self {
            case .on: return localized("On")
            case .standby: return localized("Standby")
            case .suspend: return localized("Suspend")
            case .off: return localized("Power Off")
            case .hardOff: return localized("Hard Power Off")
            }
        }

        var systemImage: String {
            switch self {
            case .on: return "power"
            case .standby: return "moon.fill"
            case .suspend: return "powersleep"
            case .off, .hardOff: return "poweroff"
            }
        }
    }

    struct CapabilitiesDescriptor: Sendable, Equatable {
        let modelName: String?
        let mccsVersion: String?
        let supportedVCPCodes: Set<VCPCode>
        let supportedInputs: [InputSource]
        let supportedColorPresets: [ColorPreset]
        let rawString: String
    }

    static func calculateChecksum(destination: UInt8 = i2cWriteAddress8Bit, bytes: [UInt8]) -> UInt8 {
        var checksum = destination
        for byte in bytes {
            checksum ^= byte
        }
        return checksum
    }

    static func buildSetVCPPacket(code: VCPCode, value: UInt16) -> [UInt8] {
        let length: UInt8 = 0x84
        let command: UInt8 = 0x03
        let highByte = UInt8((value >> 8) & 0xFF)
        let lowByte = UInt8(value & 0xFF)

        let checksum = calculateChecksum(
            destination: i2cWriteAddress8Bit,
            bytes: [sourceAddress, length, command, code.rawValue, highByte, lowByte]
        )

        return [length, command, code.rawValue, highByte, lowByte, checksum]
    }

    static func buildGetVCPPacket(code: VCPCode) -> [UInt8] {
        let length: UInt8 = 0x82
        let command: UInt8 = 0x01
        let checksum = calculateChecksum(
            destination: i2cWriteAddress8Bit,
            bytes: [sourceAddress, length, command, code.rawValue]
        )

        return [length, command, code.rawValue, checksum]
    }

    static func buildCapabilitiesRequestPacket(offset: UInt16) -> [UInt8] {
        let length: UInt8 = 0x83
        let command: UInt8 = 0xF3
        let highByte = UInt8((offset >> 8) & 0xFF)
        let lowByte = UInt8(offset & 0xFF)
        let checksum = calculateChecksum(
            destination: i2cWriteAddress8Bit,
            bytes: [sourceAddress, length, command, highByte, lowByte]
        )
        return [length, command, highByte, lowByte, checksum]
    }

    static func parseVCPReply(reply: [UInt8], expectedCode: VCPCode) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 10 else { return nil }

        let offset = reply[0] == i2cWriteAddress8Bit ? 1 : 0
        guard reply.count >= offset + 9 else { return nil }

        let length = reply[offset]
        guard (length & 0x7F) >= 8 else { return nil }

        let command = reply[offset + 1]
        guard command == 0x02 else { return nil }

        let resultCode = reply[offset + 2]
        guard resultCode == 0x00 else { return nil }

        let code = reply[offset + 3]
        guard code == expectedCode.rawValue else { return nil }

        let maxHigh = UInt16(reply[offset + 5])
        let maxLow = UInt16(reply[offset + 6])
        let curHigh = UInt16(reply[offset + 7])
        let curLow = UInt16(reply[offset + 8])

        let maxValue = (maxHigh << 8) | maxLow
        let currentValue = (curHigh << 8) | curLow

        return (current: currentValue, max: maxValue)
    }

    static func parseCapabilitiesString(_ raw: String) -> CapabilitiesDescriptor {
        let model = extractTagValue(in: raw, tag: "model")
        let mccsVer = extractTagValue(in: raw, tag: "mccs_ver")
        var vcpCodes = Set<VCPCode>()
        var inputs: [InputSource] = []
        var presets: [ColorPreset] = []

        if let vcpContent = extractTagValue(in: raw, tag: "vcp") {
            let tokens = tokenizeVCPBlock(vcpContent)
            for token in tokens {
                guard let codeByte = UInt8(token.code, radix: 16),
                      let vcp = VCPCode(rawValue: codeByte) else { continue }
                vcpCodes.insert(vcp)

                if vcp == .inputSource {
                    for sub in token.subValues {
                        if let val = UInt16(sub, radix: 16), let src = InputSource(rawValue: val) {
                            inputs.append(src)
                        }
                    }
                } else if vcp == .colorPreset {
                    for sub in token.subValues {
                        if let val = UInt16(sub, radix: 16), let preset = ColorPreset(rawValue: val) {
                            presets.append(preset)
                        }
                    }
                }
            }
        }

        return CapabilitiesDescriptor(
            modelName: model,
            mccsVersion: mccsVer,
            supportedVCPCodes: vcpCodes,
            supportedInputs: inputs,
            supportedColorPresets: presets,
            rawString: raw
        )
    }

    private static func extractTagValue(in source: String, tag: String) -> String? {
        guard let tagRange = source.range(of: "\(tag)(", options: .caseInsensitive) else { return nil }
        var depth = 1
        var current = tagRange.upperBound
        while current < source.endIndex && depth > 0 {
            let ch = source[current]
            if ch == "(" { depth += 1 }
            else if ch == ")" { depth -= 1 }
            if depth > 0 {
                current = source.index(after: current)
            }
        }
        guard depth == 0 else { return nil }
        return String(source[tagRange.upperBound..<current]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenizeVCPBlock(_ content: String) -> [(code: String, subValues: [String])] {
        var results: [(code: String, subValues: [String])] = []
        var idx = content.startIndex

        while idx < content.endIndex {
            while idx < content.endIndex && (content[idx].isWhitespace || content[idx] == ",") {
                idx = content.index(after: idx)
            }
            guard idx < content.endIndex else { break }

            let codeStart = idx
            while idx < content.endIndex && content[idx].isHexDigit {
                idx = content.index(after: idx)
            }
            let codeStr = String(content[codeStart..<idx])
            guard !codeStr.isEmpty else {
                idx = content.index(after: idx)
                continue
            }

            var subValues: [String] = []
            while idx < content.endIndex && content[idx].isWhitespace {
                idx = content.index(after: idx)
            }

            if idx < content.endIndex && content[idx] == "(" {
                idx = content.index(after: idx)
                let subStart = idx
                var depth = 1
                while idx < content.endIndex && depth > 0 {
                    if content[idx] == "(" { depth += 1 }
                    else if content[idx] == ")" { depth -= 1 }
                    if depth > 0 {
                        idx = content.index(after: idx)
                    }
                }
                let subStr = String(content[subStart..<idx])
                subValues = subStr
                    .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                    .filter { !$0.isEmpty }
                if idx < content.endIndex && content[idx] == ")" {
                    idx = content.index(after: idx)
                }
            }

            results.append((code: codeStr, subValues: subValues))
        }

        return results
    }
}
