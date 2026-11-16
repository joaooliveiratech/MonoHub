import Foundation
import IOKit.ps
import Observation

@Observable
@MainActor
final class BatteryManager {
    static let shared = BatteryManager()

    private(set) var batteryInfo: BatteryInfo = .standard
    private(set) var isMonitoring = false

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var previousPluggedIn: Bool?

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        previousPluggedIn = nil
        refreshBatteryInfo()

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.refreshBatteryInfo()
            }
        }, opaque)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                BatteryManager.shared.refreshBatteryInfo()
            }
        }
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
        previousPluggedIn = nil
        isMonitoring = false
    }

    func refreshBatteryInfo() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else {
                continue
            }

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String ?? "") == kIOPSACPowerValue
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let percentage = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100) : curCap

            let newInfo = BatteryInfo(
                percentage: min(100, max(0, percentage)),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeRemainingMinutes: isCharging ? timeToFull : timeToEmpty,
                maxCapacity: maxCap
            )

            if let previousPluggedIn, !previousPluggedIn && isPluggedIn {
                HUDManager.shared.showHUD(type: .batteryCharging, value: Float(newInfo.percentage) / 100.0)
            }
            previousPluggedIn = isPluggedIn

            if newInfo != batteryInfo {
                batteryInfo = newInfo
            }
            return
        }
    }
}
