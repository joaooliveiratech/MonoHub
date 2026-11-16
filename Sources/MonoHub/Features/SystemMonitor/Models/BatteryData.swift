import Foundation

nonisolated struct ConnectedDeviceBattery: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let level: Double
    let iconName: String
    let leftPercent: Int?
    let rightPercent: Int?
    let casePercent: Int?

    init(
        id: String,
        name: String,
        level: Double,
        iconName: String = "wave.3.right",
        leftPercent: Int? = nil,
        rightPercent: Int? = nil,
        casePercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.level = min(max(level, 0), 1)
        self.iconName = iconName
        self.leftPercent = leftPercent
        self.rightPercent = rightPercent
        self.casePercent = casePercent
    }

    var levelPercent: Int {
        Int((level * 100).rounded())
    }

    var hasComponents: Bool {
        leftPercent != nil || rightPercent != nil || casePercent != nil
    }
}

nonisolated enum EnergyMode: Sendable, Equatable {
    case lowPower
    case automatic
    case highPower

    var title: String {
        switch self {
        case .lowPower: return localized("Low Power")
        case .automatic: return localized("Automatic")
        case .highPower: return localized("High Power")
        }
    }

    var symbol: String {
        switch self {
        case .lowPower: return "leaf.fill"
        case .automatic: return "gauge.with.dots.needle.50percent"
        case .highPower: return "gauge.with.dots.needle.100percent"
        }
    }
}

nonisolated enum BatteryPowerState: Sendable, Equatable {
    case discharging
    case charging
    case chargingPaused
    case fullyCharged
    case acPowerOnly

    var symbol: String {
        switch self {
        case .discharging: return "clock"
        case .charging: return "bolt.fill"
        case .chargingPaused: return "pause.circle.fill"
        case .fullyCharged: return "checkmark.circle.fill"
        case .acPowerOnly: return "powerplug.portrait.fill"
        }
    }
}

nonisolated struct BatteryData: Sendable, Equatable {
    var hasBattery = false
    var level: Double = 1
    var isCharging = false
    var isACConnected = true
    var isFullyCharged = false
    var isLowPowerMode = false
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var cycleCount: Int?
    var designCycleCount: Int?
    var designCapacityMah: Int?
    var fullChargeCapacityMah: Int?
    var batteryPowerWatts: Double = 0
    var systemPowerWatts: Double?
    var adapterWatts: Int?
    var voltageVolts: Double?
    var temperatureCelsius: Double?
    var connectedDevices: [ConnectedDeviceBattery] = []
    var topProcesses: [ProcessItem] = []
    var policies: PowerPolicies?

    var isConnectedToPower: Bool {
        isCharging || isACConnected
    }

    var levelPercent: Int {
        Int((level * 100).rounded())
    }

    var activeEnergyMode: EnergyMode? {
        guard let policies else { return nil }
        if isLowPowerMode { return .lowPower }
        return isACConnected || !hasBattery ? policies.energyModeOnAdapter : policies.energyModeOnBattery
    }

    var isHeldAtChargeLimit: Bool {
        guard powerState == .chargingPaused, let limit = policies?.chargeLimitPercent else { return false }
        return levelPercent >= limit - 1
    }

    var powerState: BatteryPowerState {
        guard hasBattery else { return .acPowerOnly }
        if isCharging { return .charging }
        if isACConnected {
            return isFullyCharged || levelPercent >= 100 ? .fullyCharged : .chargingPaused
        }
        return .discharging
    }

    var healthPercent: Int? {
        guard let design = designCapacityMah, let full = fullChargeCapacityMah, design > 0 else { return nil }
        return min(max(Int((Double(full) / Double(design) * 100).rounded()), 0), 100)
    }

    var conditionDescription: String {
        guard let health = healthPercent else { return localized("Unknown") }
        return health >= 80 ? "Normal" : localized("Service Recommended")
    }

    var stateTitle: String {
        switch powerState {
        case .discharging: return localized("On Battery")
        case .charging: return localized("Charging")
        case .chargingPaused: return isHeldAtChargeLimit ? localized("Charge Limit Reached") : localized("Charging on Hold")
        case .fullyCharged: return localized("Fully Charged")
        case .acPowerOnly: return localized("External Power")
        }
    }

    var stateDetail: String {
        switch powerState {
        case .discharging:
            if let minutes = timeToEmptyMinutes { return localized("%@ remaining", Formatting.duration(minutes: minutes)) }
            return localized("Calculating time remaining…")
        case .charging:
            if let minutes = timeToFullMinutes { return localized("%@ until full", Formatting.duration(minutes: minutes)) }
            return localized("Calculating time until full…")
        case .chargingPaused:
            if isHeldAtChargeLimit, let limit = policies?.chargeLimitPercent {
                return localized("Held at %d%% to preserve battery health", limit)
            }
            if policies?.isChargeHeldByOptimization == true {
                return localized("Optimized Charging: finishes to 100% before you usually need it")
            }
            return localized("Your Mac is running on external power without charging the battery")
        case .fullyCharged:
            return localized("Connected to power")
        case .acPowerOnly:
            return localized("This Mac has no internal battery")
        }
    }

    var chargeLimitDescription: String {
        guard let limit = policies?.chargeLimitPercent, limit < 100 else { return localized("Off (100%)") }
        return "\(limit)%"
    }

    var powerSourceDescription: String {
        guard isACConnected else { return localized("Battery") }
        if let adapterWatts { return localized("%d W Power Adapter", adapterWatts) }
        return localized("Power Adapter")
    }
}
