import Foundation

enum HUDType: String, Sendable {
    case volume
    case brightness
    case backlight
    case batteryCharging
    case micMute
    case micVolume

    var iconName: String {
        switch self {
        case .volume: return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .backlight: return "keyboard"
        case .batteryCharging: return "bolt.fill"
        case .micMute, .micVolume: return "mic.fill"
        }
    }

    var title: String {
        switch self {
        case .volume: return localized("Volume")
        case .brightness: return localized("Brightness")
        case .backlight: return localized("Keyboard Brightness")
        case .batteryCharging: return localized("Charging")
        case .micMute: return localized("Microphone")
        case .micVolume: return localized("Microphone Level")
        }
    }
}

nonisolated struct HUDEvent: Sendable, Equatable {
    let type: HUDType
    let value: Float
    let isMuted: Bool
    let displayTitle: String?
    let customIconName: String?
    let timestamp: Date

    init(
        type: HUDType,
        value: Float,
        isMuted: Bool = false,
        displayTitle: String? = nil,
        customIconName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.value = value
        self.isMuted = isMuted
        self.displayTitle = displayTitle
        self.customIconName = customIconName
        self.timestamp = timestamp
    }

    var percentageString: String {
        if type == .micMute {
            return isMuted ? localized("Muted") : localized("Microphone Active")
        }
        if isMuted && type == .volume {
            return localized("Muted")
        }
        return "\(Int(round(value * 100)))%"
    }
}
