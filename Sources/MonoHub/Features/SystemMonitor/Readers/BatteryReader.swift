import Foundation
import IOKit
import IOKit.ps

nonisolated final class BatteryReader {
    private struct CapacityInfo {
        var cycleCount: Int?
        var designCycleCount: Int?
        var designCapacityMah: Int?
        var fullChargeCapacityMah: Int?
    }

    private static let capacityRefreshNanoseconds: UInt64 = 300_000_000_000
    private static let detailedCapacityRefreshNanoseconds: UInt64 = 30_000_000_000

    private var smartBattery: io_service_t = 0
    private let policyReader = PowerPolicyReader()
    private var capacity = CapacityInfo()
    private var lastCapacityRead: UInt64 = 0

    deinit {
        if smartBattery != 0 {
            IOObjectRelease(smartBattery)
        }
    }

    func read(detailed: Bool, refreshPolicies: Bool = false, telemetry: Bool = false) -> BatteryData {
        var data = BatteryData()
        data.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        readPowerSources(into: &data)
        if detailed {
            data.policies = policyReader.read(force: refreshPolicies)
        }
        if detailed || telemetry, data.hasBattery {
            readSmartBattery(into: &data, detailed: detailed)
        }
        return data
    }

    private func readPowerSources(into data: inout BatteryData) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery" else {
                continue
            }
            data.hasBattery = true
            if let current = description["Current Capacity"] as? Int,
               let maximum = description["Max Capacity"] as? Int, maximum > 0 {
                data.level = min(max(Double(current) / Double(maximum), 0), 1)
            }
            data.isCharging = (description["Is Charging"] as? Bool) ?? false
            data.isFullyCharged = (description["Is Charged"] as? Bool) ?? false
            data.isACConnected = (description["Power Source State"] as? String) == "AC Power"
            if let minutes = description["Time to Empty"] as? Int, minutes > 0, !data.isACConnected {
                data.timeToEmptyMinutes = minutes
            }
            if let minutes = description["Time to Full Charge"] as? Int, minutes > 0, data.isCharging {
                data.timeToFullMinutes = minutes
            }
        }

        if !data.hasBattery {
            data.isACConnected = true
        }
    }

    private func readSmartBattery(into data: inout BatteryData, detailed: Bool) {
        if smartBattery == 0 {
            smartBattery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard smartBattery != 0 else { return }

        // Copying only the keys we show avoids serializing the whole AppleSmartBattery
        // tree (lifetime data, cell arrays, charger blobs) across the kernel boundary.
        let now = monotonicNanoseconds()
        let capacityAge = now &- lastCapacityRead
        if lastCapacityRead == 0
            || capacityAge > Self.capacityRefreshNanoseconds
            || (detailed && capacityAge > Self.detailedCapacityRefreshNanoseconds) {
            capacity = readCapacity()
            lastCapacityRead = now
        }
        data.cycleCount = capacity.cycleCount
        data.designCycleCount = capacity.designCycleCount
        data.designCapacityMah = capacity.designCapacityMah
        data.fullChargeCapacityMah = capacity.fullChargeCapacityMah

        if let millivolts = int(property("Voltage")), millivolts > 0 {
            data.voltageVolts = Double(millivolts) / 1_000
        }
        let amperage = int(property("InstantAmperage")) ?? int(property("Amperage")) ?? 0
        if let volts = data.voltageVolts {
            data.batteryPowerWatts = volts * Double(amperage) / 1_000
        }

        if let rawTemperature = int(property("Temperature")), rawTemperature > 0 {
            data.temperatureCelsius = Double(rawTemperature) / 100
        }

        if data.isACConnected, let adapter = property("AdapterDetails") as? [String: Any],
           let watts = int(adapter["Watts"]), watts > 0 {
            data.adapterWatts = watts
        }

        if let telemetry = property("PowerTelemetryData") as? [String: Any] {
            let load = int(telemetry["SystemLoad"]) ?? 0
            let input = int(telemetry["SystemPowerIn"]) ?? 0
            let milliwatts = load > 0 ? load : input
            if milliwatts > 0, milliwatts < 500_000 {
                data.systemPowerWatts = Double(milliwatts) / 1_000
            }
        }
        if data.systemPowerWatts == nil, !data.isACConnected, data.batteryPowerWatts < 0 {
            data.systemPowerWatts = -data.batteryPowerWatts
        }
    }

    private func readCapacity() -> CapacityInfo {
        var info = CapacityInfo()
        info.cycleCount = int(property("CycleCount"))
        info.designCycleCount = int(property("DesignCycleCount9C"))
        let batteryData = property("BatteryData") as? [String: Any]
        info.designCapacityMah = int(batteryData?["DesignCapacity"]) ?? int(property("DesignCapacity"))
        info.fullChargeCapacityMah = int(batteryData?["NominalChargeCapacity"])
            ?? int(property("NominalChargeCapacity"))
            ?? int(batteryData?["FullChargeCapacity"])
            ?? int(property("AppleRawMaxCapacity"))
        return info
    }

    private func property(_ key: String) -> Any? {
        IORegistry.property(smartBattery, key)
    }

    private func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.int64Value
        guard raw > Int64(Int32.min), raw < Int64(Int32.max) else {
            return Int(Int32(truncatingIfNeeded: raw))
        }
        return Int(raw)
    }
}
