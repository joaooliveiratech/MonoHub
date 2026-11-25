import AppKit
import Darwin
import Foundation
import IOKit.ps
import Observation

struct SystemHealthMetrics: Sendable {
    let cpuUsage: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let memoryPressure: Double
    let diskUsedPercentage: Double
    let diskFreeBytes: Int64
    let networkInBytesPerSec: Double
    let networkOutBytesPerSec: Double

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage * 100.0)
    }

    var formattedMemory: String {
        "\(Formatting.bytes(Int64(memoryUsedBytes))) / \(Formatting.bytes(Int64(memoryTotalBytes)))"
    }
}

@Observable
@MainActor
final class SystemMonitorEngine {
    static let shared = SystemMonitorEngine()
    static let dashboardModules: Set<ModuleType> = [.cpu, .ram, .network, .battery, .sensors]
    static let overviewProcessLimit = 5
    private static let accessoryRefreshInterval: TimeInterval = 15

    private(set) var cpuData = CPUData()
    private(set) var ramData = RAMData()
    private(set) var gpuData = GPUData()
    private(set) var diskData = DiskData()
    private(set) var networkData = NetworkData()
    private(set) var batteryData = BatteryData()
    private(set) var sensorsData = SensorsData()
    private(set) var detailedModule: ModuleType?

    @ObservationIgnored var onSample: (() -> Void)?
    @ObservationIgnored private(set) var powerPolicies: PowerPolicies?
    @ObservationIgnored private var sampler: Sampler?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var request = SampleRequest()
    @ObservationIgnored private var isSampling = false
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var distributedObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var powerSourceLoop: CFRunLoopSource?
    @ObservationIgnored private var policyTask: Task<Void, Never>?
    @ObservationIgnored private var accessoryTask: Task<Void, Never>?
    @ObservationIgnored private let accessoryReader = AccessoryBatteryReader()
    @ObservationIgnored private var accessories: [ConnectedDeviceBattery] = []
    @ObservationIgnored private var lastAccessoryRead: Date = .distantPast
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var sessionInactive = false
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var menuBarVisible = true
    @ObservationIgnored private var windowMonitoringActive = false
    @ObservationIgnored private var dashboardMonitoringActive = false
    @ObservationIgnored private var windowVisible = true
    @ObservationIgnored private var windowFocusedModule: ModuleType?
    @ObservationIgnored private var windowProcessRankings: ProcessRankings = .cpu
    private(set) var notchAudience = false

    private init() {}

    var isActive: Bool {
        sampler != nil
    }

    var currentRequest: SampleRequest {
        request
    }

    func activate() {
        guard sampler == nil else {
            reloadConfiguration()
            return
        }
        generation &+= 1
        let token = generation
        sampler = Sampler { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    SystemMonitorEngine.shared.apply(result, generation: token)
                }
            }
        }
        request = SampleRequest()
        isSampling = false
        registerObservers()
        registerPowerSourceNotifications()
        reloadConfiguration()
        if request.needs(.battery) {
            refreshPowerPolicies()
        }
    }

    func deactivate() {
        guard let sampler else { return }
        sampler.shutdown()
        self.sampler = nil
        generation &+= 1
        unregisterObservers()
        policyTask?.cancel()
        policyTask = nil
        accessoryTask?.cancel()
        accessoryTask = nil

        request = SampleRequest()
        isSampling = false
        screensAsleep = false
        sessionInactive = false
        screenLocked = false
        menuBarVisible = true
        windowMonitoringActive = false
        dashboardMonitoringActive = false
        windowVisible = true
        windowFocusedModule = nil
        windowProcessRankings = .cpu
        accessories = []
        lastAccessoryRead = .distantPast
        powerPolicies = nil
        if detailedModule != nil { detailedModule = nil }

        cpuData = CPUData()
        ramData = RAMData()
        gpuData = GPUData()
        diskData = DiskData()
        networkData = NetworkData()
        batteryData = BatteryData()
        sensorsData = SensorsData()
    }

    func sampleMetrics() -> SystemHealthMetrics {
        var disk = statvfs()
        var diskTotal: UInt64 = 0
        var diskFree: UInt64 = 0
        if statvfs("/", &disk) == 0 {
            diskTotal = UInt64(disk.f_frsize) * UInt64(disk.f_blocks)
            diskFree = UInt64(disk.f_frsize) * UInt64(disk.f_bavail)
        }
        let diskUsed = diskTotal > 0 ? Double(diskTotal - min(diskFree, diskTotal)) / Double(diskTotal) : 0
        let ram = ramData.totalBytes > 0 ? ramData : RAMReader().read()
        let memTotal = ram.totalBytes > 0 ? ram.totalBytes : HardwareInfo.shared.totalMemoryBytes
        return SystemHealthMetrics(
            cpuUsage: min(max(cpuData.totalUsage, 0.0), 1.0),
            memoryUsedBytes: ram.usedBytes,
            memoryTotalBytes: memTotal,
            memoryPressure: min(max(ram.pressure, 0.0), 1.0),
            diskUsedPercentage: diskUsed,
            diskFreeBytes: Int64(clamping: diskFree),
            networkInBytesPerSec: Double(networkData.downloadBytesPerSec),
            networkOutBytesPerSec: Double(networkData.uploadBytesPerSec)
        )
    }

    func setDashboardMonitoring(active: Bool) {
        guard dashboardMonitoringActive != active else { return }
        dashboardMonitoringActive = active
        reloadConfiguration()
    }

    func setWindowMonitoring(active: Bool, focusedModule: ModuleType? = nil) {
        let focus = active ? focusedModule : nil
        guard windowMonitoringActive != active || windowFocusedModule != focus else { return }
        windowMonitoringActive = active
        windowFocusedModule = focus
        if active, focus == .battery || focus == nil {
            scheduleAccessoryRefresh()
        }
        reloadConfiguration()
    }

    func setWindowProcessRanking(_ rankings: ProcessRankings) {
        guard windowProcessRankings != rankings else { return }
        windowProcessRankings = rankings
        reloadConfiguration()
    }

    func stopAllWindowMonitoring() {
        guard windowMonitoringActive || dashboardMonitoringActive else { return }
        windowMonitoringActive = false
        dashboardMonitoringActive = false
        windowFocusedModule = nil
        reloadConfiguration()
    }

    func setWindowVisible(_ visible: Bool) {
        guard windowVisible != visible else { return }
        windowVisible = visible
        reloadConfiguration()
    }

    func setDetailedModule(_ module: ModuleType?) {
        guard detailedModule != module else { return }
        detailedModule = module
        if module == .battery {
            scheduleAccessoryRefresh()
        }
        reloadConfiguration()
    }

    func setMenuBarVisible(_ visible: Bool) {
        guard menuBarVisible != visible else { return }
        menuBarVisible = visible
        updateRunningState()
    }

    var isMenuBarVisible: Bool {
        menuBarVisible
    }

    func reloadConfiguration() {
        guard let sampler else { return }
        let updated = Self.makeRequest(
            prefs: MonitorPreferences.shared,
            panelModule: detailedModule,
            windowActive: windowMonitoringActive && windowVisible,
            windowFocus: windowFocusedModule,
            dashboardActive: dashboardMonitoringActive && windowVisible,
            windowRankings: windowProcessRankings,
            notchAudience: notchAudience
        )
        if updated != request {
            let needsImmediate = !updated.menuBarModules.subtracting(request.menuBarModules).isEmpty
                || updated.detailedModule != request.detailedModule
                || updated.processRankings != request.processRankings
                || updated.processLimit != request.processLimit
            request = updated
            sampler.update(updated)
            if needsImmediate && isSampling {
                sampler.sampleNow()
            }
        }
        updateRunningState()
    }

    func setNotchAudience(_ active: Bool) {
        guard notchAudience != active else { return }
        notchAudience = active
        reloadConfiguration()
    }

    static func makeRequest(
        prefs: MonitorPreferences,
        panelModule: ModuleType?,
        windowActive: Bool,
        windowFocus: ModuleType?,
        dashboardActive: Bool,
        windowRankings: ProcessRankings,
        notchAudience: Bool = false
    ) -> SampleRequest {
        guard FeatureManager.shared.isEnabled(.systemMonitor) else {
            return SampleRequest()
        }
        var request = SampleRequest()
        var modules = (prefs.isMenuBarActive && StatusItemController.shared.isSetUp) ? prefs.enabledModules : []
        if windowActive {
            if let focus = windowFocus {
                modules.insert(focus)
            } else {
                modules.formUnion(ModuleType.allCases)
            }
        }
        if dashboardActive {
            modules.formUnion(dashboardModules)
        }
        if notchAudience {
            modules.formUnion([.cpu, .sensors])
        }
        request.menuBarModules = modules
        request.windowAudience = windowActive || dashboardActive
        request.detailedModule = panelModule ?? (windowActive ? windowFocus : nil)
        request.topProcessesLimit = max(prefs.topProcessesCount, 0)
        request.showBatteryProcesses = prefs.showTopProcessesBattery
        request.showDiskProcesses = prefs.showTopProcessesDisk

        if let detail = request.detailedModule {
            if detail.usesProcessList {
                let limit = processLimit(for: detail, prefs: prefs)
                request.processLimit = limit
                request.processRankings = limit > 0 ? rankings(for: detail) : []
            } else {
                request.processLimit = 0
            }
        } else if windowActive {
            request.processLimit = overviewProcessLimit
            request.processRankings = windowRankings
        } else if notchAudience {
            request.processLimit = 3
            request.processRankings = .cpu
        } else {
            request.processLimit = 0
        }
        return request
    }

    private static func processLimit(for module: ModuleType, prefs: MonitorPreferences) -> Int {
        let enabled: Bool
        switch module {
        case .cpu: enabled = prefs.showTopProcessesCPU
        case .ram: enabled = prefs.showTopProcessesRAM
        case .gpu: enabled = prefs.showTopProcessesGPU
        default: enabled = false
        }
        return enabled ? max(prefs.topProcessesCount, 0) : 0
    }

    private static func rankings(for module: ModuleType) -> ProcessRankings {
        switch module {
        case .cpu: return .cpu
        case .ram: return .memory
        case .gpu: return .gpu
        default: return []
        }
    }

    private func updateRunningState() {
        guard let sampler else { return }
        let isFeatureEnabled = FeatureManager.shared.isEnabled(.systemMonitor)
        let prefs = MonitorPreferences.shared
        let pauseForSleep = screenLocked || sessionInactive || (prefs.pauseWhenSleeping && screensAsleep)
        let hasMenuBarAudience = isFeatureEnabled && prefs.isMenuBarActive && menuBarVisible && StatusItemController.shared.isSetUp && !prefs.enabledModules.isEmpty
        let hasWindowAudience = isFeatureEnabled && (detailedModule != nil || ((windowMonitoringActive || dashboardMonitoringActive) && windowVisible))
        let hasNotchAudience = isFeatureEnabled && notchAudience && !NotchWindowController.shared.isDisplayAsleep && !AppExclusionManager.shared.isSuppressed
        let running = isFeatureEnabled && !pauseForSleep && !request.isEmpty && (hasMenuBarAudience || hasWindowAudience || hasNotchAudience)
        let processInfo = ProcessInfo.processInfo
        let interval = Sampler.effectiveInterval(
            base: prefs.refreshInterval,
            lowPower: processInfo.isLowPowerModeEnabled,
            thermalState: processInfo.thermalState,
            isInteractive: hasWindowAudience
        )
        sampler.configure(interval: interval, running: running)
        let resumed = running && !isSampling
        isSampling = running
        if resumed {
            sampler.sampleNow()
        }
    }

    private func apply(_ result: SampleResult, generation token: UInt64) {
        guard token == generation, sampler != nil else { return }
        if var cpu = result.cpu {
            if let processes = result.processes {
                if !processes.topCPU.isEmpty || request.processRankings.contains(.cpu) {
                    cpu.topProcesses = processes.topCPU
                } else {
                    cpu.topProcesses = cpuData.topProcesses
                }
                cpu.processCount = processes.processCount
                cpu.threadCount = processes.threadCount
            } else if request.wantsProcesses {
                cpu.topProcesses = cpuData.topProcesses
                cpu.processCount = cpu.processCount ?? cpuData.processCount
                cpu.threadCount = cpu.threadCount ?? cpuData.threadCount
            }
            if cpu != cpuData { cpuData = cpu }
        }
        if var ram = result.ram {
            if let processes = result.processes {
                if !processes.topMemory.isEmpty || request.processRankings.contains(.memory) {
                    ram.topProcesses = processes.topMemory
                } else {
                    ram.topProcesses = ramData.topProcesses
                }
            } else if request.wantsProcesses {
                ram.topProcesses = ramData.topProcesses
            }
            if ram != ramData { ramData = ram }
        }
        if var gpu = result.gpu {
            if let processes = result.processes {
                if !processes.topGPU.isEmpty || request.processRankings.contains(.gpu) {
                    gpu.topProcesses = processes.topGPU
                } else {
                    gpu.topProcesses = gpuData.topProcesses
                }
            } else if request.wantsProcesses {
                gpu.topProcesses = gpuData.topProcesses
            }
            if gpu != gpuData { gpuData = gpu }
        }
        if var disk = result.disk {
            if let processes = result.processes, (!processes.topDisk.isEmpty || request.processRankings.contains(.disk) || detailedModule == .disk) {
                disk.topProcesses = processes.topDisk
            } else {
                disk.topProcesses = diskData.topProcesses
            }
            if disk != diskData { diskData = disk }
        } else if let processes = result.processes, !processes.topDisk.isEmpty, diskData.topProcesses != processes.topDisk {
            var updated = diskData
            updated.topProcesses = processes.topDisk
            diskData = updated
        }
        if let network = result.network, network != networkData {
            networkData = network
        }
        if let sensors = result.sensors, sensors != sensorsData {
            sensorsData = sensors
        }
        if var battery = result.battery {
            if let policies = battery.policies {
                powerPolicies = policies
            }
            if detailedModule == .battery || (windowMonitoringActive && windowVisible && (windowFocusedModule == nil || windowFocusedModule == .battery)) {
                refreshAccessories(force: false)
                battery.connectedDevices = accessories
            }
            if let processes = result.processes, (!processes.topEnergy.isEmpty || request.processRankings.contains(.energy) || detailedModule == .battery) {
                battery.topProcesses = processes.topEnergy
            } else if battery.topProcesses.isEmpty {
                battery.topProcesses = batteryData.topProcesses
            }
            if battery != batteryData { batteryData = battery }
        } else if let processes = result.processes, !processes.topEnergy.isEmpty, batteryData.topProcesses != processes.topEnergy {
            var updated = batteryData
            updated.topProcesses = processes.topEnergy
            batteryData = updated
        }
        if result.cpu != nil || result.sensors != nil {
            LiveActivityCenter.shared.evaluateSystemHealth(cpu: cpuData, sensors: sensorsData)
        }
        onSample?()
    }

    private func refreshAccessories(force: Bool) {
        guard sampler != nil else { return }
        guard force || Date().timeIntervalSince(lastAccessoryRead) > Self.accessoryRefreshInterval else { return }
        lastAccessoryRead = Date()
        accessories = accessoryReader.read()
    }

    /// IOBluetooth queries talk to bluetoothd over XPC; deferring them to the next
    /// main-loop turn lets the panel or window appear before the round trip happens.
    private func scheduleAccessoryRefresh() {
        accessoryTask?.cancel()
        accessoryTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            refreshAccessories(force: true)
            if batteryData.connectedDevices != accessories {
                var updated = batteryData
                updated.connectedDevices = accessories
                batteryData = updated
            }
        }
    }

    private func refreshPowerPolicies() {
        policyTask?.cancel()
        let token = generation
        policyTask = Task.detached(priority: .utility) {
            let policies = PowerPolicyReader().read(force: true)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let engine = SystemMonitorEngine.shared
                guard engine.generation == token, engine.isActive else { return }
                engine.powerPolicies = policies
            }
        }
    }

    private func registerObservers() {
        unregisterObservers()
        let workspace = NSWorkspace.shared.notificationCenter
        let handlers: [(Notification.Name, @MainActor (SystemMonitorEngine) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.screensAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.screensAsleep = false }),
            (NSWorkspace.sessionDidResignActiveNotification, { $0.sessionInactive = true }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionInactive = false })
        ]
        for (name, handler) in handlers {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let engine = SystemMonitorEngine.shared
                    guard engine.isActive else { return }
                    handler(engine)
                    engine.updateRunningState()
                }
            }
            observers.append((workspace, token))
        }

        let distributed = DistributedNotificationCenter.default()
        let lockHandlers: [(Notification.Name, @MainActor (SystemMonitorEngine) -> Void)] = [
            (Notification.Name("com.apple.screenIsLocked"), { $0.screenLocked = true }),
            (Notification.Name("com.apple.screenIsUnlocked"), { $0.screenLocked = false })
        ]
        for (name, handler) in lockHandlers {
            let token = distributed.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let engine = SystemMonitorEngine.shared
                    guard engine.isActive else { return }
                    handler(engine)
                    engine.updateRunningState()
                }
            }
            distributedObservers.append(token)
        }

        let powerToken = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let engine = SystemMonitorEngine.shared
                engine.powerSourceDidChange()
                engine.updateRunningState()
            }
        }
        observers.append((NotificationCenter.default, powerToken))

        let thermalToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let engine = SystemMonitorEngine.shared
                guard engine.isActive else { return }
                engine.updateRunningState()
            }
        }
        observers.append((NotificationCenter.default, thermalToken))
    }

    private func unregisterObservers() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributed.removeObserver(observer)
        }
        distributedObservers.removeAll()
        if let powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceLoop, .defaultMode)
            CFRunLoopSourceInvalidate(powerSourceLoop)
        }
        powerSourceLoop = nil
    }

    private func registerPowerSourceNotifications() {
        guard powerSourceLoop == nil else { return }
        let callback: IOPowerSourceCallbackType = { _ in
            MainActor.assumeIsolated {
                SystemMonitorEngine.shared.powerSourceDidChange()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceLoop = source
    }

    private func powerSourceDidChange() {
        guard let sampler else { return }
        sampler.invalidateBattery()
        guard request.needs(.battery) else { return }
        refreshPowerPolicies()
        if isSampling {
            sampler.sampleNow()
        }
    }
}
