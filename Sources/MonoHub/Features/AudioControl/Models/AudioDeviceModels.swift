import Foundation
public import CoreAudio

public enum AudioTransportType: Sendable, Hashable {
    case builtIn
    case bluetooth
    case hdmi
    case displayPort
    case usb
    case airPlay
    case virtual
    case continuity
    case other(UInt32)

    public init(rawValue: UInt32) {
        switch rawValue {
        case 1651274862: self = .builtIn
        case 1651275109, 1651271009: self = .bluetooth
        case 1751412073: self = .hdmi
        case 1685090932: self = .displayPort
        case 1970496032: self = .usb
        case 1634230896: self = .airPlay
        case 1986622068: self = .virtual
        case 1667463012: self = .continuity
        default: self = .other(rawValue)
        }
    }
}

public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool
    public let transportType: AudioTransportType

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        isInput: Bool,
        isOutput: Bool,
        transportType: AudioTransportType
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
        self.transportType = transportType
    }

    public var iconName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            return "airpodsmax"
        } else if lower.contains("airpods pro") {
            return "airpodspro"
        } else if lower.contains("airpods") {
            return "airpods"
        } else if lower.contains("beats") {
            return "headphones"
        } else if lower.contains("headphone") || lower.contains("fone") {
            return "headphones"
        }

        switch transportType {
        case .bluetooth:
            return isInput ? "mic.fill" : "headphones"
        case .builtIn:
            return isInput ? "mic.fill" : "laptopcomputer"
        case .hdmi, .displayPort:
            return "display"
        case .airPlay:
            return "airplayaudio"
        case .usb:
            return isInput ? "mic.fill" : "speaker.wave.2.fill"
        case .continuity:
            return "iphone"
        case .virtual:
            return "slider.horizontal.2.square"
        case .other:
            return isInput ? "mic.fill" : "speaker.wave.2.fill"
        }
    }
}
