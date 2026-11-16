import AppKit
import Foundation
import Testing
@testable import MonoHub

@Suite("Battery charging, energy mode and counter deltas", .serialized)
@MainActor
struct BatteryPolicyTests {
    init() {
        Localization.language = .english
    }
    private func archive(_ policies: [ChargePolicyArchive]) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("ChargeCtrlPolicy", for: ChargePolicyArchive.self)
        archiver.encode(policies as NSArray, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    @Test("Charge policies decode the powerd archive format")
    func decodeChargePolicies() throws {
        let data = try archive([
            ChargePolicyArchive(reason: "manualChargeLimit", limitPercent: 80, isTerminated: false),
            ChargePolicyArchive(reason: "obc", limitPercent: 80, isTerminated: true),
            ChargePolicyArchive(reason: "broken", limitPercent: 0, isTerminated: false)
        ])
        let policies = PowerPolicyReader.chargePolicies(fromArchive: data)
        #expect(policies.count == 2)
        #expect(policies[0] == ChargePolicy(reason: "manualChargeLimit", limitPercent: 80, isTerminated: false))
        #expect(policies[0].isManualLimit)
        #expect(!policies[1].isManualLimit)
        #expect(PowerPolicyReader.chargePolicies(fromArchive: Data("garbage".utf8)).isEmpty)
    }

    @Test("Energy mode follows LowPowerMode and HighPowerMode flags")
    func energyModeParsing() {
        #expect(PowerPolicyReader.energyMode(from: nil) == .automatic)
        #expect(PowerPolicyReader.energyMode(from: ["LowPowerMode": 0, "HighPowerMode": 0]) == .automatic)
        #expect(PowerPolicyReader.energyMode(from: ["LowPowerMode": 1, "HighPowerMode": 0]) == .lowPower)
        #expect(PowerPolicyReader.energyMode(from: ["LowPowerMode": 0, "HighPowerMode": 1]) == .highPower)
    }

    @Test("Live power policies are readable without privileges")
    func livePolicies() {
        let reader = PowerPolicyReader()
        let policies = reader.read(force: true)
        if let limit = policies.chargeLimitPercent {
            #expect((1...100).contains(limit))
        }
        #expect(reader.read(force: false) == policies)
        for policy in PowerPolicyReader.chargePolicies(at: PowerPolicyReader.chargingPolicyPath) {
            #expect((1...100).contains(policy.limitPercent))
        }
        let battery = BatteryReader().read(detailed: true)
        #expect(battery.policies != nil)
    }

    @Test("Charge limit explains paused charging")
    func chargeLimitState() {
        var data = BatteryData()
        data.hasBattery = true
        data.level = 0.8
        data.isACConnected = true
        data.policies = PowerPolicies(chargeLimitPercent: 80)
        #expect(data.powerState == .chargingPaused)
        #expect(data.isHeldAtChargeLimit)
        #expect(data.stateTitle == "Charge Limit Reached")
        #expect(data.stateDetail.contains("80%"))
        #expect(data.chargeLimitDescription == "80%")

        data.level = 0.5
        #expect(!data.isHeldAtChargeLimit)
        #expect(data.stateTitle == "Charging on Hold")

        data.policies = PowerPolicies()
        #expect(data.chargeLimitDescription == "Off (100%)")
    }

    @Test("Active energy mode tracks the power source and Low Power Mode")
    func activeEnergyMode() {
        var data = BatteryData()
        data.hasBattery = true
        #expect(data.activeEnergyMode == nil)

        data.policies = PowerPolicies(energyModeOnBattery: .lowPower, energyModeOnAdapter: .highPower, supportsHighPower: true)
        data.isACConnected = true
        #expect(data.activeEnergyMode == .highPower)
        data.isACConnected = false
        #expect(data.activeEnergyMode == .lowPower)

        data.policies = PowerPolicies()
        data.isLowPowerMode = true
        #expect(data.activeEnergyMode == .lowPower)
    }

    @Test("Menu bar battery shows bolt when charging and plug when only connected")
    func powerIndicator() throws {
        #expect(PowerIndicator(isCharging: true, isConnected: true) == .charging)
        #expect(PowerIndicator(isCharging: false, isConnected: true) == .pluggedIn)
        #expect(PowerIndicator(isCharging: false, isConnected: false) == .none)
        #expect(PowerIndicator.pluggedIn.symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) } != nil)

        func state(charging: Bool, connected: Bool) -> BatteryGlyphState {
            BatteryGlyphState(percent: 80, isCharging: charging, isConnected: connected, isLowPowerMode: false, dynamicColors: true)
        }
        let bolt = try #require(MenuBarRenderer.image(for: .battery(state(charging: true, connected: true))).tiffRepresentation)
        let plug = try #require(MenuBarRenderer.image(for: .battery(state(charging: false, connected: true))).tiffRepresentation)
        let plain = try #require(MenuBarRenderer.image(for: .battery(state(charging: false, connected: false))).tiffRepresentation)
        #expect(bolt != plug)
        #expect(plug != plain)

        let inside = MenuBarRenderer.image(for: .batteryInside(state(charging: false, connected: false)))
        let insidePlugged = MenuBarRenderer.image(for: .batteryInside(state(charging: false, connected: true)))
        #expect(insidePlugged.size.width > inside.size.width)
        #expect(MenuBarContent.battery(state(charging: false, connected: true)).accessibilityLabel.contains("connected"))
    }

    @Test("Menu bar rendering is deterministic across cache hits")
    func renderCache() throws {
        let content = MenuBarContent.batteryWithPercent(
            BatteryGlyphState(percent: 42, isCharging: true, isConnected: true, isLowPowerMode: false, dynamicColors: true),
            value: "42%"
        )
        let first = MenuBarRenderer.image(for: content)
        let second = MenuBarRenderer.image(for: content)
        #expect(first.size == second.size)
        #expect(try #require(first.tiffRepresentation) == (try #require(second.tiffRepresentation)))
    }

    @Test("Network deltas ignore interfaces that just appeared or reset")
    func networkDelta() {
        typealias Counters = NetworkReader.InterfaceCounters
        let previous: [UInt16: Counters] = [4: Counters(received: 1_000, sent: 500)]
        let current: [UInt16: Counters] = [
            4: Counters(received: 1_600, sent: 700),
            9: Counters(received: 50_000_000_000, sent: 9_000_000_000)
        ]
        #expect(NetworkReader.delta(from: previous, to: current) == Counters(received: 600, sent: 200))
        #expect(NetworkReader.delta(from: current, to: [4: Counters(received: 10, sent: 10)]) == Counters(received: 0, sent: 0))
    }

    @Test("Disk deltas ignore drives that just appeared or reset")
    func diskDelta() {
        typealias Counters = DiskReader.DriverCounters
        let previous: [UInt64: Counters] = [1: Counters(read: 100, written: 100)]
        let current: [UInt64: Counters] = [
            1: Counters(read: 400, written: 150),
            2: Counters(read: 80_000_000_000, written: 1)
        ]
        #expect(DiskReader.delta(from: previous, to: current) == Counters(read: 300, written: 50))
        #expect(DiskReader.delta(from: current, to: [1: Counters(read: 0, written: 0)]) == Counters(read: 0, written: 0))
    }
}
