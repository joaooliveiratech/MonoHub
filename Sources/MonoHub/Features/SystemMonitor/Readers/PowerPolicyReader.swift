import Foundation
import IOKit

@_silgen_name("IOPMCopyPMPreferences")
nonisolated private func pmCopyPreferences() -> Unmanaged<CFMutableDictionary>?

@_silgen_name("IOPMFeatureIsAvailable")
nonisolated private func pmFeatureIsAvailable(_ feature: CFString, _ powerSource: CFString?) -> Bool

nonisolated struct PowerPolicies: Sendable, Equatable {
    var energyModeOnBattery: EnergyMode = .automatic
    var energyModeOnAdapter: EnergyMode = .automatic
    var supportsHighPower = false
    var chargeLimitPercent: Int?
    var isChargeHeldByOptimization = false
}

nonisolated struct ChargePolicy: Sendable, Equatable {
    let reason: String
    let limitPercent: Int
    let isTerminated: Bool

    var isManualLimit: Bool {
        reason.localizedCaseInsensitiveContains("manual")
    }
}

nonisolated final class PowerPolicyReader {
    static let chargingPolicyPath = "/Library/Preferences/com.apple.powerd.charging.plist"
    private static let refreshNanoseconds: UInt64 = 10_000_000_000

    private var cached = PowerPolicies()
    private var lastRead: UInt64 = 0
    private lazy var supportsHighPower = pmFeatureIsAvailable("HighPowerMode" as CFString, nil)

    func read(force: Bool) -> PowerPolicies {
        let now = monotonicNanoseconds()
        guard force || lastRead == 0 || now &- lastRead >= Self.refreshNanoseconds else { return cached }
        lastRead = now

        var policies = PowerPolicies()
        policies.supportsHighPower = supportsHighPower
        if let preferences = pmCopyPreferences()?.takeRetainedValue() as? [String: Any] {
            policies.energyModeOnBattery = Self.energyMode(from: preferences["Battery Power"] as? [String: Any])
            policies.energyModeOnAdapter = Self.energyMode(from: preferences["AC Power"] as? [String: Any])
        }

        let active = Self.chargePolicies(at: Self.chargingPolicyPath).filter { !$0.isTerminated }
        policies.chargeLimitPercent = active.first(where: \.isManualLimit)?.limitPercent
        policies.isChargeHeldByOptimization = active.contains { !$0.isManualLimit }
        cached = policies
        return policies
    }

    static func energyMode(from settings: [String: Any]?) -> EnergyMode {
        guard let settings else { return .automatic }
        if (settings["LowPowerMode"] as? NSNumber)?.intValue == 1 { return .lowPower }
        if (settings["HighPowerMode"] as? NSNumber)?.intValue == 1 { return .highPower }
        return .automatic
    }

    static func chargePolicies(at path: String) -> [ChargePolicy] {
        guard let file = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: file, format: nil) as? [String: Any],
              let archive = plist["policies"] as? Data else {
            return []
        }
        return chargePolicies(fromArchive: archive)
    }

    static func chargePolicies(fromArchive archive: Data) -> [ChargePolicy] {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return [] }
        unarchiver.requiresSecureCoding = true
        unarchiver.setClass(ChargePolicyArchive.self, forClassName: "ChargeCtrlPolicy")
        defer { unarchiver.finishDecoding() }
        let root = unarchiver.decodeObject(
            of: [NSArray.self, ChargePolicyArchive.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [ChargePolicyArchive]
        return (root ?? []).compactMap { archived in
            guard (1...100).contains(archived.limitPercent) else { return nil }
            return ChargePolicy(reason: archived.reason, limitPercent: archived.limitPercent, isTerminated: archived.isTerminated)
        }
    }
}

nonisolated final class ChargePolicyArchive: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let reason: String
    let limitPercent: Int
    let isTerminated: Bool

    init(reason: String, limitPercent: Int, isTerminated: Bool) {
        self.reason = reason
        self.limitPercent = limitPercent
        self.isTerminated = isTerminated
    }

    required init?(coder: NSCoder) {
        reason = (coder.decodeObject(of: NSString.self, forKey: "reason") as String?) ?? ""
        limitPercent = coder.decodeInteger(forKey: "soclimit")
        isTerminated = coder.decodeBool(forKey: "terminated")
    }

    func encode(with coder: NSCoder) {
        coder.encode(reason as NSString, forKey: "reason")
        coder.encode(limitPercent, forKey: "soclimit")
        coder.encode(isTerminated, forKey: "terminated")
    }
}
