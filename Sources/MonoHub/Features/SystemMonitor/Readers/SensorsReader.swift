import Foundation
import IOKit
import IOKit.hidsystem

@_silgen_name("IOHIDEventSystemClientCreate")
nonisolated private func hidEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
nonisolated private func hidEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDServiceClientCopyEvent")
nonisolated private func hidServiceClientCopyEvent(_ service: IOHIDServiceClient, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
nonisolated private func hidEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

nonisolated final class SensorsReader {
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16
    private static let quickDieSampleCount = 4

    private var client: IOHIDEventSystemClient?
    private var dieSensors: [IOHIDServiceClient] = []
    private var ssdSensor: IOHIDServiceClient?
    private var batterySensor: IOHIDServiceClient?
    private var didDiscover = false
    private var quickRotation = 0
    private var history = RollingHistory()

    func read(detailed: Bool) -> SensorsData {
        discoverIfNeeded()

        var data = SensorsData()
        data.thermalState = ProcessInfo.processInfo.thermalState
        data.uptimeSeconds = ProcessInfo.processInfo.systemUptime

        let dies = detailed ? dieSensors : quickSubset()
        let readings = dies.compactMap(temperature(of:))
        if !readings.isEmpty {
            data.socTemperature = readings.reduce(0, +) / Double(readings.count)
            data.socTemperatureMax = readings.max()
        }
        if detailed {
            data.ssdTemperature = ssdSensor.flatMap(temperature(of:))
            data.batteryTemperature = batterySensor.flatMap(temperature(of:))
        }

        if let soc = data.socTemperature {
            history.append(soc)
        }
        data.history = history
        return data
    }

    func readBatteryTemperature() -> Double? {
        discoverIfNeeded()
        return batterySensor.flatMap(temperature(of:))
    }

    private func quickSubset() -> [IOHIDServiceClient] {
        guard dieSensors.count > Self.quickDieSampleCount else { return dieSensors }
        quickRotation = (quickRotation + 1) % dieSensors.count
        return (0..<Self.quickDieSampleCount).map { dieSensors[(quickRotation + $0 * 3) % dieSensors.count] }
    }

    private func temperature(of service: IOHIDServiceClient) -> Double? {
        guard let event = hidServiceClientCopyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
            return nil
        }
        let value = hidEventGetFloatValue(event, Self.temperatureField)
        return value > 0 && value < 130 ? value : nil
    }

    private func discoverIfNeeded() {
        guard !didDiscover else { return }
        didDiscover = true

        guard let created = hidEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        client = created
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = hidEventSystemClientSetMatching(created, matching)
        guard let services = IOHIDEventSystemClientCopyServices(created) as? [IOHIDServiceClient] else { return }

        var seen = Set<String>()
        var dies: [(String, IOHIDServiceClient)] = []
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  seen.insert(name).inserted else { continue }
            if name.hasPrefix("PMU tdie") || name.contains("MTR Temp Sensor") {
                dies.append((name, service))
            } else if name.hasPrefix("NAND") {
                ssdSensor = ssdSensor ?? service
            } else if name.hasPrefix("gas gauge battery") {
                batterySensor = batterySensor ?? service
            }
        }
        dieSensors = dies.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.map(\.1)
    }
}
