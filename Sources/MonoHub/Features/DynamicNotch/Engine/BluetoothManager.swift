import Foundation
import Observation
import IOBluetooth
import CoreAudio
import IOKit
import IOKit.ps

@_silgen_name("IOPSCopyPowerSourcesByType")
nonisolated private func MonoNotch_IOPSCopyPowerSourcesByType(_ type: Int32) -> Unmanaged<CFTypeRef>?

nonisolated struct BluetoothTelemetryEntry: Sendable {
    var name: String?
    var address: String?
    var isConnectedInProfiler: Bool = false
    var batteryMain: Int?
    var batteryCase: Int?
    var batteryLeft: Int?
    var batteryRight: Int?
    var isCharging: Bool = false
    var firmware: String?
    var vendorName: String?
    var minorType: String?
    var transportType: String?
    var serialNumber: String?
    var rssi: Int?
    var lowWarnLevel: Int = 20
}

nonisolated struct BluetoothNativeDevice: Sendable {
    let name: String
    let address: String
    let isConnected: Bool
    let rssi: Int?
}

nonisolated struct BluetoothScanResult: Sendable {
    let native: [BluetoothNativeDevice]
    let accessoryPower: [String: BluetoothTelemetryEntry]
    let hidBatteries: [String: Int]
    let telemetry: [String: BluetoothTelemetryEntry]?
}

@Observable
@MainActor
final class BluetoothManager {
    static let shared = BluetoothManager()

    private(set) var connectedDevices: [BluetoothDeviceInfo] = []
    private(set) var allDevices: [BluetoothDeviceInfo] = []
    private(set) var isScanning: Bool = false

    @ObservationIgnored private var telemetryCache: [String: BluetoothTelemetryEntry] = [:]
    @ObservationIgnored private var lastTelemetryDate: Date = .distantPast
    @ObservationIgnored private var lastRefreshDate: Date = .distantPast
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private(set) var isEnabled = false

    private static let telemetryMaxAge: TimeInterval = 300
    private static let minimumRefreshInterval: TimeInterval = 5

    private init() {}

    func start() {
        isEnabled = true
    }

    func stop() {
        isEnabled = false
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        telemetryCache.removeAll()
        lastTelemetryDate = .distantPast
        lastRefreshDate = .distantPast
        isScanning = false
        allDevices = []
        connectedDevices = []
    }

    func refreshDevices(includeProfiler: Bool = false, force: Bool = false) {
        guard isEnabled else { return }
        let now = Date()
        if !force && isScanning { return }
        if !force && !includeProfiler && now.timeIntervalSince(lastRefreshDate) < Self.minimumRefreshInterval { return }

        let wantsProfiler = includeProfiler && (force || telemetryCache.isEmpty || now.timeIntervalSince(lastTelemetryDate) > Self.telemetryMaxAge)
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isScanning = true
        lastRefreshDate = now

        refreshTask = Task { [weak self] in
            let result = await Self.scan(includeProfiler: wantsProfiler)
            guard let self, !Task.isCancelled, generation == self.refreshGeneration, self.isEnabled else { return }
            if let telemetry = result.telemetry {
                self.telemetryCache = telemetry
                self.lastTelemetryDate = Date()
            }
            self.mergeAndPublish(
                nativeDevices: result.native,
                telemetry: self.telemetryCache,
                accessoryPower: result.accessoryPower,
                hidBatteries: result.hidBatteries
            )
            self.isScanning = false
        }
    }

    @concurrent
    nonisolated private static func scan(includeProfiler: Bool) async -> BluetoothScanResult {
        let native = queryIOBluetoothDevices()
        let power = queryAccessoryPowerSources()
        let hid = queryIORegistryHIDBatteries()
        let telemetry = includeProfiler ? await querySystemProfilerTelemetry() : nil
        return BluetoothScanResult(native: native, accessoryPower: power, hidBatteries: hid, telemetry: telemetry)
    }

    private func mergeAndPublish(
        nativeDevices: [BluetoothNativeDevice],
        telemetry: [String: BluetoothTelemetryEntry],
        accessoryPower: [String: BluetoothTelemetryEntry],
        hidBatteries: [String: Int]
    ) {
        let sorted = Self.merge(
            nativeDevices: nativeDevices,
            telemetry: telemetry,
            accessoryPower: accessoryPower,
            hidBatteries: hidBatteries
        )
        if sorted != allDevices {
            allDevices = sorted
        }
        let connected = sorted.filter { $0.isConnected }
        if connected != connectedDevices {
            connectedDevices = connected
        }
    }

    nonisolated static func merge(
        nativeDevices: [BluetoothNativeDevice],
        telemetry: [String: BluetoothTelemetryEntry],
        accessoryPower: [String: BluetoothTelemetryEntry],
        hidBatteries: [String: Int]
    ) -> [BluetoothDeviceInfo] {
        var mergedByNormalizedAddr: [String: BluetoothDeviceInfo] = [:]
        var mergedOrder: [String] = []

        func lookupPower(forName name: String) -> BluetoothTelemetryEntry? {
            let normName = normalizeName(name)
            if let exact = accessoryPower[normName] {
                return exact
            }
            for (key, val) in accessoryPower where !normName.isEmpty && !key.isEmpty && (normName.contains(key) || key.contains(normName)) {
                return val
            }
            return nil
        }

        func lookupHIDBattery(forName name: String, address: String?) -> Int? {
            if let address, let battery = hidBatteries[normalizeAddress(address)] {
                return battery
            }
            let normName = normalizeName(name)
            if let battery = hidBatteries[normName] { return battery }
            for (key, value) in hidBatteries where !normName.isEmpty && (normName.contains(key) || key.contains(normName)) {
                return value
            }
            return nil
        }

        for nd in nativeDevices {
            let normAddr = normalizeAddress(nd.address)
            guard mergedByNormalizedAddr[normAddr] == nil else { continue }
            let t = telemetry[normAddr]
            let p = lookupPower(forName: nd.name)
            let hidBat = lookupHIDBattery(forName: nd.name, address: nd.address)

            let displayName = (nd.name == "Bluetooth" || nd.name.isEmpty) ? (t?.name ?? p?.name ?? "Bluetooth") : nd.name
            let category = detectCategory(name: displayName, minorType: t?.minorType ?? p?.minorType ?? "")

            mergedByNormalizedAddr[normAddr] = BluetoothDeviceInfo(
                id: normAddr,
                name: displayName,
                address: nd.address,
                batteryLevel: p?.batteryMain ?? hidBat ?? t?.batteryMain,
                batteryCaseLevel: p?.batteryCase ?? t?.batteryCase,
                batteryLeftLevel: p?.batteryLeft ?? t?.batteryLeft,
                batteryRightLevel: p?.batteryRight ?? t?.batteryRight,
                isCharging: (p?.isCharging == true) || (t?.isCharging == true),
                firmwareVersion: t?.firmware,
                vendorName: t?.vendorName ?? p?.vendorName,
                transportType: p?.transportType ?? t?.transportType,
                serialNumber: t?.serialNumber,
                rssi: nd.rssi ?? t?.rssi,
                isConnected: nd.isConnected || (t?.isConnectedInProfiler == true),
                category: category,
                lowBatteryWarningLevel: p?.lowWarnLevel ?? 20
            )
            mergedOrder.append(normAddr)
        }

        for (normAddr, t) in telemetry where mergedByNormalizedAddr[normAddr] == nil {
            let displayName = t.name ?? localized("Bluetooth Device")
            let p = lookupPower(forName: displayName)
            let hidBat = lookupHIDBattery(forName: displayName, address: t.address)

            mergedByNormalizedAddr[normAddr] = BluetoothDeviceInfo(
                id: normAddr,
                name: displayName,
                address: t.address ?? normAddr,
                batteryLevel: p?.batteryMain ?? hidBat ?? t.batteryMain,
                batteryCaseLevel: p?.batteryCase ?? t.batteryCase,
                batteryLeftLevel: p?.batteryLeft ?? t.batteryLeft,
                batteryRightLevel: p?.batteryRight ?? t.batteryRight,
                isCharging: (p?.isCharging == true) || t.isCharging,
                firmwareVersion: t.firmware,
                vendorName: t.vendorName ?? p?.vendorName,
                transportType: p?.transportType ?? t.transportType,
                serialNumber: t.serialNumber,
                rssi: t.rssi,
                isConnected: t.isConnectedInProfiler,
                category: detectCategory(name: displayName, minorType: t.minorType ?? p?.minorType ?? ""),
                lowBatteryWarningLevel: p?.lowWarnLevel ?? 20
            )
            mergedOrder.append(normAddr)
        }

        return mergedOrder.compactMap { mergedByNormalizedAddr[$0] }.sorted {
            if $0.isConnected != $1.isConnected {
                return $0.isConnected && !$1.isConnected
            }
            if ($0.primaryBattery != nil) != ($1.primaryBattery != nil) {
                return $0.primaryBattery != nil
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func connect(device: BluetoothDeviceInfo) {
        guard let addr = device.address else { return }
        Task { [weak self] in
            await Self.setConnection(address: addr, connected: true)
            try? await Task.sleep(for: .seconds(1))
            self?.refreshDevices(force: true)
        }
    }

    func disconnect(device: BluetoothDeviceInfo) {
        guard let addr = device.address else { return }
        Task { [weak self] in
            await Self.setConnection(address: addr, connected: false)
            try? await Task.sleep(for: .milliseconds(800))
            self?.refreshDevices(force: true)
        }
    }

    @concurrent
    nonisolated private static func setConnection(address: String, connected: Bool) async {
        guard let device = IOBluetoothDevice(addressString: normalizeAddress(address)) else { return }
        if connected {
            _ = device.openConnection()
        } else {
            _ = device.closeConnection()
        }
    }

    func toggleConnection(for device: BluetoothDeviceInfo) {
        if device.isConnected {
            disconnect(device: device)
        } else {
            connect(device: device)
        }
    }

    private static nonisolated func queryAccessoryPowerSources() -> [String: BluetoothTelemetryEntry] {
        guard let blob = MonoNotch_IOPSCopyPowerSourcesByType(4)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return [:]
        }

        var map: [String: BluetoothTelemetryEntry] = [:]

        for src in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
                  let rawName = desc[kIOPSNameKey] as? String else {
                continue
            }

            let capacity = desc[kIOPSCurrentCapacityKey] as? Int
            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? ((desc[kIOPSIsChargingKey] as? Int) == 1)
            let powerState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let chargingOrAC = isCharging || powerState == kIOPSACPowerValue
            let transportRaw = desc[kIOPSTransportTypeKey] as? String
            let transport = transportRaw == "Bluetooth LE" ? "BLE" : transportRaw
            let categoryStr = desc["Accessory Category"] as? String
            let partId = (desc["Part Identifier"] as? String ?? "").lowercased()
            let lowWarn = desc["Low Warn Level"] as? Int ?? 20
            let vendorID = desc["Vendor ID"] as? Int

            let isCaseEntry = partId == "case" || categoryStr?.lowercased().contains("case") == true || rawName.lowercased().hasSuffix(" case")
            let baseName: String
            if isCaseEntry && rawName.lowercased().hasSuffix(" case") {
                baseName = String(rawName.dropLast(5))
            } else {
                baseName = rawName
            }

            let key = normalizeName(baseName)
            var entry = map[key] ?? BluetoothTelemetryEntry(name: baseName)
            entry.transportType = entry.transportType ?? transport
            entry.minorType = entry.minorType ?? categoryStr
            entry.lowWarnLevel = lowWarn
            if let vendorID, entry.vendorName == nil {
                entry.vendorName = vendorNameFromID(vendorID)
            }

            if isCaseEntry {
                entry.batteryCase = capacity
            } else if let combinedParts = desc["Combined Parts"] as? [[String: Any]], !combinedParts.isEmpty {
                for part in combinedParts {
                    let pId = (part["Part Identifier"] as? String ?? "").lowercased()
                    let pCap = part[kIOPSCurrentCapacityKey] as? Int
                    let pCharging = (part[kIOPSIsChargingKey] as? Bool) ?? ((part[kIOPSIsChargingKey] as? Int) == 1)
                    if pId == "left" {
                        entry.batteryLeft = pCap
                    } else if pId == "right" {
                        entry.batteryRight = pCap
                    }
                    if pCharging {
                        entry.isCharging = true
                    }
                }
                if entry.batteryMain == nil {
                    entry.batteryMain = capacity
                }
                if chargingOrAC {
                    entry.isCharging = true
                }
            } else if partId == "left" {
                entry.batteryLeft = capacity
                if chargingOrAC { entry.isCharging = true }
            } else if partId == "right" {
                entry.batteryRight = capacity
                if chargingOrAC { entry.isCharging = true }
            } else {
                entry.batteryMain = capacity
                if chargingOrAC { entry.isCharging = true }
            }

            map[key] = entry
        }

        return map
    }

    private static nonisolated func queryIORegistryHIDBatteries() -> [String: Int] {
        var result: [String: Int] = [:]
        guard let matching = IOServiceMatching("IOHIDDevice") else { return result }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            guard let battery = props["BatteryPercent"] as? Int, battery > 0 && battery <= 100 else {
                continue
            }

            if let product = props["Product"] as? String {
                result[normalizeName(product)] = battery
            }
            if let addr = props["DeviceAddress"] as? String ?? props["SerialNumber"] as? String {
                result[normalizeAddress(addr)] = battery
            }
        }
        return result
    }

    private static nonisolated func queryIOBluetoothDevices() -> [BluetoothNativeDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return paired.compactMap { dev in
            guard let addr = dev.addressString, !addr.isEmpty else { return nil }
            let isConnected = dev.isConnected()
            let rawRSSI = dev.rawRSSI()
            let rssi: Int? = (isConnected && rawRSSI != 0 && rawRSSI != 127) ? Int(rawRSSI) : nil
            return BluetoothNativeDevice(name: dev.name ?? "Bluetooth", address: addr, isConnected: isConnected, rssi: rssi)
        }
    }

    private static nonisolated func querySystemProfilerTelemetry() async -> [String: BluetoothTelemetryEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["SPBluetoothDataType"] as? [[String: Any]] else {
                return [:]
            }

            var map: [String: BluetoothTelemetryEntry] = [:]

            for item in list {
                let connected = item["device_connected"] as? [[String: Any]] ?? []
                let notConnected = item["device_not_connected"] as? [[String: Any]] ?? []

                func parseList(_ devices: [[String: Any]], isConnected: Bool) {
                    for devDict in devices {
                        for (deviceName, detailsObj) in devDict {
                            guard let details = detailsObj as? [String: Any],
                                  let address = details["device_address"] as? String else { continue }

                            let normAddr = normalizeAddress(address)
                            let batteryMain = parseBattery(details["device_batteryLevelMain"]) ?? parseBattery(details["device_batteryLevel"])
                            let batteryCase = parseBattery(details["device_batteryLevelCase"]) ?? parseBattery(details["device_batteryPercentCase"])
                            let batteryLeft = parseBattery(details["device_batteryLevelLeft"])
                            let batteryRight = parseBattery(details["device_batteryLevelRight"])
                            let firmware = details["device_firmwareVersion"] as? String
                            let minorType = details["device_minorType"] as? String
                            let serial = details["device_serialNumber"] as? String
                            let services = details["device_services"] as? String ?? ""
                            let vendorRaw = details["device_vendorID"] as? String
                            let rssi = (details["device_rssi"] as? String).flatMap { Int($0) }

                            let transport: String?
                            if services.contains("BLE") {
                                transport = "BLE"
                            } else if services.contains("A2DP") || services.contains("AACP") {
                                transport = localized("Audio")
                            } else if services.contains("HID") {
                                transport = "HID"
                            } else {
                                transport = nil
                            }

                            let entry = BluetoothTelemetryEntry(
                                name: deviceName,
                                address: address,
                                isConnectedInProfiler: isConnected,
                                batteryMain: batteryMain,
                                batteryCase: batteryCase,
                                batteryLeft: batteryLeft,
                                batteryRight: batteryRight,
                                isCharging: false,
                                firmware: firmware,
                                vendorName: parseVendorString(vendorRaw),
                                minorType: minorType,
                                transportType: transport,
                                serialNumber: serial,
                                rssi: rssi
                            )
                            map[normAddr] = entry
                        }
                    }
                }

                parseList(connected, isConnected: true)
                parseList(notConnected, isConnected: false)
            }
            return map
        } catch {
            return [:]
        }
    }

    private static nonisolated func normalizeAddress(_ addr: String) -> String {
        addr.replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static nonisolated func normalizeName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static nonisolated func parseVendorString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw.localizedCaseInsensitiveContains("apple") { return "Apple" }
        let hexClean = raw
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "") ?? ""
        if let id = Int(hexClean, radix: 16) {
            return vendorNameFromID(id)
        }
        return nil
    }

    private static nonisolated func vendorNameFromID(_ id: Int) -> String? {
        switch id {
        case 0x004C, 0x05AC: return "Apple"
        case 0x046D: return "Logitech"
        case 0x054C: return "Sony"
        case 0x045E: return "Microsoft"
        case 0x009E: return "Bose"
        case 0x057E: return "Nintendo"
        case 0x0075: return "Samsung"
        case 0x1532: return "Razer"
        case 0x3434: return "Keychron"
        case 0x28DE: return "Valve"
        case 0x0B05: return "ASUS"
        case 0x046A: return "Cherry"
        default: return nil
        }
    }

    private static nonisolated func detectCategory(name: String, minorType: String) -> BluetoothDeviceCategory {
        let lowerName = name.lowercased()
        let lowerType = minorType.lowercased()

        if lowerName.contains("gamepad") || lowerName.contains("dualshock") || lowerName.contains("controller") || lowerName.contains("dualsense") || lowerName.contains("xbox") || lowerName.contains("switch") || lowerName.contains("joy-con") || lowerType.contains("gamepad") || lowerType.contains("joystick") {
            return .gamepad
        }
        if lowerName.contains("airpod") {
            return .airpods
        }
        if lowerName.contains("headphone") || lowerName.contains("wh-1000") || lowerName.contains("beats") || lowerName.contains("bose") || lowerName.contains("earbuds") || lowerName.contains("earphones") || lowerType.contains("headphone") || lowerType.contains("headset") {
            return .headphones
        }
        if lowerName.contains("mouse") || lowerName.contains("master") || lowerName.contains("trackball") || lowerType.contains("mouse") {
            return .mouse
        }
        if lowerName.contains("keyboard") || lowerName.contains("keychron") || lowerType.contains("keyboard") {
            return .keyboard
        }
        if lowerName.contains("trackpad") || lowerType.contains("trackpad") {
            return .trackpad
        }
        if lowerName.contains("iphone") || lowerType.contains("phone") {
            return .phone
        }
        if lowerName.contains("watch") {
            return .watch
        }
        if lowerName.contains("tv") || lowerName.contains("living room") || lowerName.contains("display") || lowerType.contains("display") {
            return .display
        }
        if lowerName.contains("speaker") || lowerName.contains("soundbar") || lowerName.contains("echo") || lowerName.contains("homepod") || lowerType.contains("speaker") {
            return .speaker
        }
        return .generic
    }

    private static nonisolated func parseBattery(_ val: Any?) -> Int? {
        if let i = val as? Int { return i }
        if let s = val as? String {
            let cleaned = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(cleaned)
        }
        return nil
    }
}
