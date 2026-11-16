import Foundation
import IOKit
import IOKit.ps

nonisolated final class BatteryReader {
    private var smartBattery: io_service_t = 0
    private let policyReader = PowerPolicyReader()

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
            readSmartBattery(into: &data)
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

    private func readSmartBattery(into data: inout BatteryData) {
        if smartBattery == 0 {
            smartBattery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard smartBattery != 0 else { return }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(smartBattery, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return
        }

        data.cycleCount = int(properties["CycleCount"])
        data.designCycleCount = int(properties["DesignCycleCount9C"])

        let batteryData = properties["BatteryData"] as? [String: Any]
        data.designCapacityMah = int(batteryData?["DesignCapacity"]) ?? int(properties["DesignCapacity"])
        data.fullChargeCapacityMah = int(batteryData?["NominalChargeCapacity"])
            ?? int(properties["NominalChargeCapacity"])
            ?? int(batteryData?["FullChargeCapacity"])
            ?? int(properties["AppleRawMaxCapacity"])

        if let millivolts = int(properties["Voltage"]), millivolts > 0 {
            data.voltageVolts = Double(millivolts) / 1_000
        }
        let amperage = int(properties["InstantAmperage"]) ?? int(properties["Amperage"]) ?? 0
        if let volts = data.voltageVolts {
            data.batteryPowerWatts = volts * Double(amperage) / 1_000
        }

        if let rawTemperature = int(properties["Temperature"]) ?? int(batteryData?["Temperature"]), rawTemperature > 0 {
            data.temperatureCelsius = Double(rawTemperature) / 100
        }

        if let adapter = properties["AdapterDetails"] as? [String: Any], data.isACConnected {
            if let watts = int(adapter["Watts"]), watts > 0 {
                data.adapterWatts = watts
            }
        }

        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
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

    private func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.int64Value
        guard raw > Int64(Int32.min), raw < Int64(Int32.max) else {
            return Int(Int32(truncatingIfNeeded: raw))
        }
        return Int(raw)
    }
}
