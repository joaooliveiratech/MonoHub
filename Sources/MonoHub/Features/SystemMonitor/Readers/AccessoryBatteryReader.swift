import Foundation
import IOBluetooth
import IOKit
import ObjectiveC

private typealias BatteryPercentGetter = @convention(c) (AnyObject, Selector) -> UInt8

@MainActor
final class AccessoryBatteryReader {
    private let selectorSingle = NSSelectorFromString("batteryPercentSingle")
    private let selectorCombined = NSSelectorFromString("batteryPercentCombined")
    private let selectorLeft = NSSelectorFromString("batteryPercentLeft")
    private let selectorRight = NSSelectorFromString("batteryPercentRight")
    private let selectorCase = NSSelectorFromString("batteryPercentCase")

    func read() -> [ConnectedDeviceBattery] {
        var devices: [ConnectedDeviceBattery] = []
        var seen = Set<String>()

        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where device.isConnected() {
            let name = device.nameOrAddress ?? "Bluetooth"
            guard !seen.contains(name) else { continue }

            let left = validPercent(query(device, selectorLeft))
            let right = validPercent(query(device, selectorRight))
            let caseLevel = validPercent(query(device, selectorCase))
            let single = validPercent(query(device, selectorSingle)) ?? validPercent(query(device, selectorCombined))

            if left != nil || right != nil || caseLevel != nil {
                let buds = [left, right].compactMap { $0 }
                let average = buds.isEmpty ? Double(caseLevel ?? 0) : Double(buds.reduce(0, +)) / Double(buds.count)
                seen.insert(name)
                devices.append(ConnectedDeviceBattery(
                    id: device.addressString ?? name,
                    name: name,
                    level: average / 100,
                    iconName: Self.symbol(for: name),
                    leftPercent: left,
                    rightPercent: right,
                    casePercent: caseLevel
                ))
            } else if let single {
                seen.insert(name)
                devices.append(ConnectedDeviceBattery(
                    id: device.addressString ?? name,
                    name: name,
                    level: Double(single) / 100,
                    iconName: Self.symbol(for: name)
                ))
            }
        }

        let services = IORegistry.services(matching: "AppleDeviceManagementHIDEventService")
        defer { IORegistry.release(services) }
        for service in services {
            guard let percent = IORegistry.number(service, "BatteryPercent")?.intValue, (1...100).contains(percent) else { continue }
            let name = (IORegistry.property(service, "Product") as? String) ?? localized("Accessory")
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            devices.append(ConnectedDeviceBattery(
                id: "hid-\(name)",
                name: name,
                level: Double(percent) / 100,
                iconName: Self.symbol(for: name)
            ))
        }

        return devices
    }

    private func query(_ device: IOBluetoothDevice, _ selector: Selector) -> UInt8 {
        guard let method = class_getInstanceMethod(IOBluetoothDevice.self, selector) else { return 0 }
        let getter = unsafeBitCast(method_getImplementation(method), to: BatteryPercentGetter.self)
        return getter(device, selector)
    }

    private func validPercent(_ value: UInt8) -> Int? {
        (1...100).contains(value) ? Int(value) : nil
    }

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpod") { return "airpods" }
        if lower.contains("beats") || lower.contains("headphone") || lower.contains("fone") { return "headphones" }
        if lower.contains("mouse") { return "magicmouse.fill" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lower.contains("keyboard") || lower.contains("teclado") { return "keyboard.fill" }
        if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") { return "gamecontroller.fill" }
        if lower.contains("pencil") { return "applepencil" }
        return "wave.3.right"
    }
}
