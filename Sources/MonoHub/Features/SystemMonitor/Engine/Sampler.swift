import Dispatch
import Foundation
import Synchronization

nonisolated struct SampleRequest: Sendable, Equatable {
    var menuBarModules: Set<ModuleType> = []
    var detailedModule: ModuleType?
    var processLimit = 5
    var processRankings: ProcessRankings = []
    var windowAudience = false
    var topProcessesLimit = 5
    var showBatteryProcesses = true
    var showDiskProcesses = true

    func needs(_ module: ModuleType) -> Bool {
        menuBarModules.contains(module) || detailedModule == module
    }

    var isEmpty: Bool {
        menuBarModules.isEmpty && detailedModule == nil
    }

    var wantsProcesses: Bool {
        detailedModule == .cpu || (processLimit > 0 && !processRankings.isEmpty)
    }
}

nonisolated struct SampleResult: Sendable {
    var cpu: CPUData?
    var ram: RAMData?
    var gpu: GPUData?
    var disk: DiskData?
    var network: NetworkData?
    var battery: BatteryData?
    var sensors: SensorsData?
    var processes: ProcessSnapshot?
}

nonisolated final class Sampler: @unchecked Sendable {
    static let batteryIdleTicks: UInt64 = 30
    static let batteryWindowTicks: UInt64 = 5
    static let sensorsIdleTicks: UInt64 = 3
    private static let minimumImmediateSpacing: UInt64 = 400_000_000

    private let queue = DispatchQueue(label: "com.antigravity.monostats.sampler", qos: .utility)
    private let request = Mutex(SampleRequest())
    private let batteryInvalidated = Atomic<Bool>(true)
    private let immediatePending = Atomic<Bool>(false)
    private let deliver: @Sendable (SampleResult) -> Void

    private let cpuReader = CPUReader()
    private let ramReader = RAMReader()
    private let gpuReader = GPUReader()
    private let diskReader = DiskReader()
    private let networkReader = NetworkReader()
    private let batteryReader = BatteryReader()
    private let sensorsReader = SensorsReader()
    private let processReader = ProcessReader()

    private var timer: (any DispatchSourceTimer)?
    private var isTimerRunning = false
    private var interval: TimeInterval = 2
    private var tick: UInt64 = 0
    private var lastSampleTime: UInt64 = 0
    private var lastSampledRequest: SampleRequest?
    private var isShutDown = false

    init(deliver: @escaping @Sendable (SampleResult) -> Void) {
        self.deliver = deliver
    }

    deinit {
        if let timer {
            timer.setEventHandler {}
            if !isTimerRunning {
                timer.resume()
            }
            timer.cancel()
        }
    }

    static func leeway(for interval: TimeInterval) -> DispatchTimeInterval {
        let factor = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.25 : 0.15
        let floor = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.35 : 0.25
        return .milliseconds(Int(max(interval * factor, floor) * 1_000))
    }

    func update(_ newRequest: SampleRequest) {
        request.withLock { $0 = newRequest }
    }

    func invalidateBattery() {
        batteryInvalidated.store(true, ordering: .relaxed)
    }

    func configure(interval newInterval: TimeInterval, running: Bool) {
        queue.async { [self] in
            guard !isShutDown else { return }
            let clamped = max(newInterval, 0.5)
            let intervalChanged = clamped != interval
            interval = clamped

            if running {
                let source = timer ?? makeTimer()
                if intervalChanged || !isTimerRunning {
                    source.schedule(deadline: .now() + clamped, repeating: clamped, leeway: Self.leeway(for: clamped))
                }
                if !isTimerRunning {
                    source.resume()
                    isTimerRunning = true
                }
            } else if let timer, isTimerRunning {
                timer.suspend()
                isTimerRunning = false
            }
        }
    }

    func sampleNow() {
        guard !immediatePending.exchange(true, ordering: .acquiringAndReleasing) else { return }
        queue.async { [self] in
            immediatePending.store(false, ordering: .releasing)
            guard !isShutDown else { return }
            let current = request.withLock { $0 }
            let elapsed = monotonicNanoseconds() &- lastSampleTime
            if lastSampledRequest == current, elapsed < Self.minimumImmediateSpacing {
                return
            }
            sample(current)
        }
    }

    func shutdown() {
        queue.async { [self] in
            isShutDown = true
            if let timer {
                timer.setEventHandler {}
                if !isTimerRunning {
                    timer.resume()
                }
                timer.cancel()
            }
            timer = nil
            isTimerRunning = false
        }
    }

    private func makeTimer() -> any DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            sample(request.withLock { $0 })
        }
        source.activate()
        source.suspend()
        timer = source
        isTimerRunning = false
        return source
    }

    private func sample(_ current: SampleRequest) {
        guard !current.isEmpty else { return }
        tick &+= 1
        lastSampleTime = monotonicNanoseconds()
        let requestChanged = lastSampledRequest != current
        lastSampledRequest = current
        let detailed = current.detailedModule
        var result = SampleResult()

        if current.needs(.cpu) {
            result.cpu = cpuReader.read(detailed: detailed == .cpu)
        }
        if current.needs(.ram) {
            result.ram = ramReader.read()
        }
        if current.needs(.gpu) {
            result.gpu = gpuReader.read()
        }
        if current.needs(.disk) {
            result.disk = diskReader.read(detailed: detailed == .disk, includeIO: detailed == .disk || current.windowAudience)
        }
        if current.needs(.network) {
            result.network = networkReader.read(
                detailed: detailed == .network,
                includeAddresses: detailed == .network || current.windowAudience
            )
        }
        if current.needs(.battery) {
            let invalidated = batteryInvalidated.exchange(false, ordering: .relaxed)
            let cadence = current.windowAudience ? Self.batteryWindowTicks : Self.batteryIdleTicks
            if detailed == .battery || invalidated || requestChanged || tick % cadence == 1 {
                var battery = batteryReader.read(
                    detailed: detailed == .battery,
                    refreshPolicies: invalidated,
                    telemetry: current.windowAudience
                )
                if detailed == .battery, battery.hasBattery, battery.temperatureCelsius == nil {
                    battery.temperatureCelsius = sensorsReader.readBatteryTemperature()
                }
                result.battery = battery
            }
        }
        if current.needs(.sensors) {
            let isDetailed = detailed == .sensors
            if isDetailed || requestChanged || tick % Self.sensorsIdleTicks == 1 {
                result.sensors = sensorsReader.read(detailed: isDetailed)
            }
        }

        var effectiveRankings = current.processRankings
        var effectiveLimit = current.processLimit
        if detailed == .battery, current.showBatteryProcesses, current.topProcessesLimit > 0 {
            effectiveLimit = max(effectiveLimit, current.topProcessesLimit)
            effectiveRankings.insert(.energy)
        }
        if detailed == .disk, current.showDiskProcesses, current.topProcessesLimit > 0 {
            effectiveLimit = max(effectiveLimit, current.topProcessesLimit)
            effectiveRankings.insert(.disk)
        }

        let wantsProcessScan = current.wantsProcesses || (effectiveLimit > 0 && !effectiveRankings.isEmpty)
        if wantsProcessScan {
            let isBackgroundOnly = detailed == nil && !current.windowAudience && current.processLimit > 0 && current.processLimit < 5
            let cpuHigh = (result.cpu?.totalUsage ?? 0) >= 0.35
            if !isBackgroundOnly || cpuHigh {
                let snapshot = processReader.read(limit: effectiveLimit, rankings: effectiveRankings)
                result.processes = snapshot
                if !snapshot.topEnergy.isEmpty {
                    result.battery?.topProcesses = snapshot.topEnergy
                }
                if !snapshot.topDisk.isEmpty {
                    result.disk?.topProcesses = snapshot.topDisk
                }
            }
        }

        deliver(result)
    }
}
