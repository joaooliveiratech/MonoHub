import Foundation

enum BluetoothDeviceCategory: String, Sendable, Codable, CaseIterable {
    case airpods
    case headphones
    case mouse
    case keyboard
    case trackpad
    case speaker
    case gamepad
    case phone
    case watch
    case display
    case generic

    var iconName: String {
        switch self {
        case .airpods: return "airpodspro"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "hand.tap.fill"
        case .speaker: return "hifispeaker.fill"
        case .gamepad: return "gamecontroller.fill"
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .display: return "tv.fill"
        case .generic: return "wave.3.forward.circle.fill"
        }
    }

    var localizedName: String {
        switch self {
        case .airpods: return "AirPods"
        case .headphones: return localized("Headphones")
        case .mouse: return localized("Mouse")
        case .keyboard: return localized("Keyboard")
        case .trackpad: return localized("Trackpad")
        case .speaker: return localized("Speaker")
        case .gamepad: return localized("Controller")
        case .phone: return "iPhone"
        case .watch: return "Apple Watch"
        case .display: return localized("TV / Display")
        case .generic: return localized("Device")
        }
    }
}

nonisolated struct BluetoothDeviceInfo: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let address: String?
    let batteryLevel: Int?
    let batteryCaseLevel: Int?
    let batteryLeftLevel: Int?
    let batteryRightLevel: Int?
    let isCharging: Bool
    let firmwareVersion: String?
    let vendorName: String?
    let transportType: String?
    let serialNumber: String?
    let rssi: Int?
    let isConnected: Bool
    let category: BluetoothDeviceCategory
    let lowBatteryWarningLevel: Int

    var isAudioDevice: Bool {
        category == .airpods || category == .headphones || category == .speaker
    }

    var primaryBattery: Int? {
        batteryLevel ?? batteryLeftLevel ?? batteryRightLevel ?? batteryCaseLevel
    }

    var hasMultiPartBattery: Bool {
        batteryLeftLevel != nil || batteryRightLevel != nil || batteryCaseLevel != nil
    }

    var isLowBattery: Bool {
        guard let b = primaryBattery else { return false }
        return b <= lowBatteryWarningLevel
    }

    var signalQualityLabel: String? {
        guard let rssi else { return nil }
        if rssi >= -55 { return "Excelente" }
        if rssi >= -68 { return "Bom" }
        if rssi >= -80 { return "Regular" }
        return "Fraco"
    }

    init(
        id: String,
        name: String,
        address: String? = nil,
        batteryLevel: Int? = nil,
        batteryCaseLevel: Int? = nil,
        batteryLeftLevel: Int? = nil,
        batteryRightLevel: Int? = nil,
        isCharging: Bool = false,
        firmwareVersion: String? = nil,
        vendorName: String? = nil,
        transportType: String? = nil,
        serialNumber: String? = nil,
        rssi: Int? = nil,
        isConnected: Bool = true,
        category: BluetoothDeviceCategory = .generic,
        lowBatteryWarningLevel: Int = 20
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.batteryLevel = batteryLevel
        self.batteryCaseLevel = batteryCaseLevel
        self.batteryLeftLevel = batteryLeftLevel
        self.batteryRightLevel = batteryRightLevel
        self.isCharging = isCharging
        self.firmwareVersion = firmwareVersion
        self.vendorName = vendorName
        self.transportType = transportType
        self.serialNumber = serialNumber
        self.rssi = rssi
        self.isConnected = isConnected
        self.category = category
        self.lowBatteryWarningLevel = lowBatteryWarningLevel
    }
}
