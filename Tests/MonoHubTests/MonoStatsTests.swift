import AppKit
import Foundation
import Synchronization
import Testing
@testable import MonoHub

@Suite("MonoStats System Metrics Tests", .serialized)
@MainActor
struct MonoStatsTests {
    init() {
        Localization.language = .english
    }
    @Test("Hardware info detects cores, clusters and memory")
    func hardwareInfo() {
        let hardware = HardwareInfo.shared
        #expect(hardware.physicalCores > 0)
        #expect(hardware.logicalCores >= hardware.physicalCores)
        #expect(hardware.totalMemoryBytes > 0)
        #expect(!hardware.chipName.isEmpty)
        #expect(hardware.coreClusters.count == hardware.logicalCores)
        #expect(hardware.machTicksToNanoseconds(0) == 0)
    }

    @Test("Mach ticks convert to nanoseconds using the timebase")
    func machTimebase() {
        let hardware = HardwareInfo.shared
        let ticks: UInt64 = 24_000_000
        let nanoseconds = hardware.machTicksToNanoseconds(ticks)
        let expected = ticks * UInt64(hardware.machTimebaseNumer) / UInt64(hardware.machTimebaseDenom)
        #expect(nanoseconds == expected)
    }

    @Test("CPUReader samples valid load and per-core usage")
    func cpuReader() {
        let reader = CPUReader()
        _ = reader.read()
        Thread.sleep(forTimeInterval: 0.1)
        let sample = reader.read()
        #expect((0...1).contains(sample.totalUsage))
        #expect((0...1).contains(sample.userUsage))
        #expect((0...1).contains(sample.systemUsage))
        #expect(sample.coreUsages.count == HardwareInfo.shared.logicalCores)
        #expect(sample.history.values.count == 2)
    }

    @Test("RAMReader follows Activity Monitor accounting")
    func ramReader() {
        let data = RAMReader().read()
        #expect(data.totalBytes > 0)
        #expect(data.usedBytes <= data.totalBytes)
        #expect(data.appBytes > 0)
        #expect(data.wiredBytes > 0)
        #expect((0...1).contains(data.usedPercent))
        #expect((0...1).contains(data.pressure))
    }

    @Test("DiskReader reads the root volume and I/O counters")
    func diskReader() {
        let reader = DiskReader()
        let data = reader.read(detailed: true)
        #expect(data.totalBytes > 0)
        #expect(data.usedBytes <= data.totalBytes)
        #expect(!data.volumeName.isEmpty)
        #expect(data.totalReadBytes > 0)
    }

    @Test("NetworkReader computes rates with 64-bit counters")
    func networkReader() {
        let reader = NetworkReader()
        _ = reader.read(detailed: true)
        let data = reader.read(detailed: true)
        #expect(data.downloadHistory.values.count == 2)
        #expect(!Formatting.speed(data.downloadBytesPerSec).isEmpty)
    }

    @Test("BatteryReader returns consistent power information")
    func batteryReader() {
        let data = BatteryReader().read(detailed: true)
        #expect((0...1).contains(data.level))
        if let health = data.healthPercent {
            #expect((0...100).contains(health))
        }
        if !data.hasBattery {
            #expect(data.powerState == .acPowerOnly)
        }
    }

    @Test("Battery power state distinguishes paused charging")
    func batteryPowerState() {
        var data = BatteryData()
        data.hasBattery = true
        data.level = 0.8
        data.isACConnected = true
        data.isCharging = false
        #expect(data.powerState == .chargingPaused)

        data.isCharging = true
        #expect(data.powerState == .charging)

        data.isCharging = false
        data.isACConnected = false
        #expect(data.powerState == .discharging)

        data.isACConnected = true
        data.isFullyCharged = true
        #expect(data.powerState == .fullyCharged)
    }

    @Test("SensorsReader never fabricates temperatures")
    func sensorsReader() {
        let data = SensorsReader().read(detailed: true)
        if let temperature = data.socTemperature {
            #expect(temperature > 0 && temperature < 130)
            #expect((data.socTemperatureMax ?? 0) >= temperature)
        } else {
            #expect(data.formattedTemperature == "—")
        }
        #expect(!data.thermalDescription.isEmpty)
    }

    @Test("ProcessReader ranks processes and resolves names")
    func processReader() {
        let reader = ProcessReader()
        _ = reader.read(limit: 5, includeGPU: true)
        Thread.sleep(forTimeInterval: 0.1)
        let snapshot = reader.read(limit: 5, includeGPU: true)
        #expect(snapshot.processCount > 0)
        #expect(snapshot.threadCount > 0)
        #expect(snapshot.topCPU.count <= 5)
        #expect(snapshot.topMemory.count == 5)
        #expect(snapshot.topGPU.count <= 5)
        for item in snapshot.topMemory {
            #expect(!item.name.isEmpty)
            #expect(item.pid > 0)
        }
        let cpuValues = snapshot.topCPU.map(\.cpuPercent)
        #expect(cpuValues == cpuValues.sorted(by: >))
        for item in snapshot.topCPU {
            #expect((0...100).contains(item.cpuPercent))
            #expect(item.formattedCPU.hasSuffix("%"))
        }
    }

    @Test("Rolling history keeps a bounded window")
    func rollingHistory() {
        var history = RollingHistory(capacity: 3)
        for value in [1.0, 2, 3, 4] {
            history.append(value)
        }
        #expect(history.values == [2, 3, 4])
        #expect(history.peak == 4)
    }

    @Test("Compact speed formatting stays short")
    func compactSpeed() {
        #expect(Formatting.compactSpeed(0) == "0K")
        #expect(Formatting.compactSpeed(512_000) == "512K")
        #expect(Formatting.compactSpeed(2_500_000) == "2.5M")
        #expect(Formatting.compactSpeed(45_000_000) == "45M")
        #expect(Formatting.percent(0.426) == "43%")
    }

    @Test("Preferences toggle modules and keep at least one enabled")
    func preferencesToggle() {
        let prefs = MonitorPreferences.shared
        let original = prefs.enabledModules
        defer { prefs.enabledModules = original }

        prefs.enabledModules = [.cpu]
        prefs.toggleModule(.cpu)
        #expect(prefs.enabledModules == [.cpu])

        prefs.toggleModule(.sensors)
        #expect(prefs.isModuleEnabled(.sensors))
    }

    @Test("Preferences reorder modules with drag offsets")
    func preferencesMove() {
        let prefs = MonitorPreferences.shared
        let original = prefs.moduleOrder
        defer { prefs.moduleOrder = original }

        prefs.moduleOrder = [.cpu, .ram, .gpu, .disk, .network, .battery, .sensors]
        prefs.moveModules(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(prefs.moduleOrder == [.ram, .gpu, .cpu, .disk, .network, .battery, .sensors])

        prefs.moveModules(fromOffsets: IndexSet(integer: 6), toOffset: 0)
        #expect(prefs.moduleOrder.first == .sensors)
        #expect(prefs.moduleOrder.count == ModuleType.allCases.count)
    }

    @Test("Display styles fall back to module defaults")
    func displayStyleFallback() {
        let prefs = MonitorPreferences.shared
        let original = prefs.displayStyles
        defer { prefs.displayStyles = original }

        prefs.displayStyles = [ModuleType.network.rawValue: DisplayStyle.stacked.rawValue]
        #expect(prefs.displayStyle(for: .network) == ModuleType.network.defaultStyle)

        prefs.applyPresetToAll(.stacked)
        #expect(prefs.displayStyle(for: .cpu) == .stacked)
        #expect(prefs.displayStyle(for: .battery) == .stacked)
        #expect(prefs.displayStyle(for: .network) == ModuleType.network.defaultStyle)
    }

    @Test("Menu bar images reserve two digits so common values never shift neighbors")
    func stableMenuBarWidths() {
        let low = MenuBarRenderer.image(for: .gaugeWithLabel(label: "CPU", value: "4%", ratio: 0.04, tint: .normal))
        let mid = MenuBarRenderer.image(for: .gaugeWithLabel(label: "CPU", value: "45%", ratio: 0.45, tint: .warning))
        let high = MenuBarRenderer.image(for: .gaugeWithLabel(label: "CPU", value: "100%", ratio: 1, tint: .critical))
        #expect(low.size.width == mid.size.width)
        #expect(high.size.width > mid.size.width)
        #expect(low.size.height == MenuBarRenderer.height)

        let slow = MenuBarRenderer.image(for: .network(download: "0K", upload: "0K", downloadActive: false, uploadActive: false))
        let fast = MenuBarRenderer.image(for: .network(download: "999K", upload: "45M", downloadActive: true, uploadActive: true))
        #expect(slow.size.width == fast.size.width)

        let cool = MenuBarRenderer.image(for: .symbolWithValue(symbol: "thermometer.medium", value: "9°", tint: .normal))
        let warm = MenuBarRenderer.image(for: .symbolWithValue(symbol: "thermometer.medium", value: "58°", tint: .warning))
        #expect(cool.size.width == warm.size.width)
    }

    @Test("Battery glyph is large and reflects charging state")
    func batteryGlyph() throws {
        let discharging = BatteryGlyphState(percent: 80, isCharging: false, isConnected: false, isLowPowerMode: false, dynamicColors: true)
        let charging = BatteryGlyphState(percent: 80, isCharging: true, isConnected: true, isLowPowerMode: false, dynamicColors: true)

        let icon = MenuBarRenderer.image(for: .battery(discharging))
        #expect(icon.size.width >= 27)

        let inside = MenuBarRenderer.image(for: .batteryInside(discharging))
        let insideCharging = MenuBarRenderer.image(for: .batteryInside(charging))
        #expect(insideCharging.size.width > inside.size.width)

        let plain = try #require(icon.tiffRepresentation)
        let bolt = try #require(MenuBarRenderer.image(for: .battery(charging)).tiffRepresentation)
        #expect(plain != bolt)

        #expect(discharging.fillTint == .normal)
        #expect(charging.fillTint == .charging)
        let low = BatteryGlyphState(percent: 12, isCharging: false, isConnected: false, isLowPowerMode: false, dynamicColors: true)
        #expect(low.fillTint == .critical)
    }

    @Test("Sample requests only include visible or detailed modules")
    func sampleRequest() {
        var request = SampleRequest(menuBarModules: [.cpu, .battery], detailedModule: nil, processLimit: 5)
        #expect(request.needs(.cpu))
        #expect(!request.needs(.gpu))
        request.detailedModule = .gpu
        #expect(request.needs(.gpu))
        #expect(ModuleType.gpu.usesProcessList)
        #expect(!ModuleType.battery.usesProcessList)
    }

    @Test("Sample request rejects empty work and only lists processes when shown")
    func sampleRequestProcesses() {
        #expect(SampleRequest().isEmpty)
        #expect(!SampleRequest().wantsProcesses)
        var request = SampleRequest(menuBarModules: [.disk], detailedModule: .disk, processLimit: 0)
        #expect(!request.wantsProcesses)
        request.detailedModule = .cpu
        #expect(request.wantsProcesses)
        request.detailedModule = .ram
        request.processLimit = 5
        #expect(!request.wantsProcesses)
        request.processRankings = .memory
        #expect(request.wantsProcesses)
    }

    @Test("Engine requests match who is looking")
    func engineRequests() {
        let prefs = MonitorPreferences.shared
        let original = (prefs.topProcessesCount, prefs.showTopProcessesGPU, prefs.showTopProcessesCPU)
        defer {
            prefs.topProcessesCount = original.0
            prefs.showTopProcessesGPU = original.1
            prefs.showTopProcessesCPU = original.2
        }
        prefs.topProcessesCount = 5
        prefs.showTopProcessesGPU = true
        prefs.showTopProcessesCPU = false

        let gpuPanel = SystemMonitorEngine.makeRequest(prefs: prefs, panelModule: .gpu, windowActive: false, windowFocus: nil, dashboardActive: false, windowRankings: .cpu)
        #expect(gpuPanel.detailedModule == .gpu)
        #expect(gpuPanel.processRankings == .gpu)
        #expect(gpuPanel.processLimit == 5)
        #expect(!gpuPanel.windowAudience)

        let cpuPanel = SystemMonitorEngine.makeRequest(prefs: prefs, panelModule: .cpu, windowActive: false, windowFocus: nil, dashboardActive: false, windowRankings: .cpu)
        #expect(cpuPanel.processRankings.isEmpty)
        #expect(cpuPanel.wantsProcesses)

        let overview = SystemMonitorEngine.makeRequest(prefs: prefs, panelModule: nil, windowActive: true, windowFocus: nil, dashboardActive: false, windowRankings: .memory)
        #expect(overview.menuBarModules == Set(ModuleType.allCases))
        #expect(overview.detailedModule == nil)
        #expect(overview.processRankings == .memory)
        #expect(overview.processLimit == SystemMonitorEngine.overviewProcessLimit)
        #expect(overview.windowAudience)

        let focused = SystemMonitorEngine.makeRequest(prefs: prefs, panelModule: nil, windowActive: true, windowFocus: .disk, dashboardActive: false, windowRankings: .cpu)
        #expect(focused.detailedModule == .disk)
        #expect(!focused.wantsProcesses)

        let dashboard = SystemMonitorEngine.makeRequest(prefs: prefs, panelModule: nil, windowActive: false, windowFocus: .gpu, dashboardActive: true, windowRankings: .cpu)
        #expect(dashboard.menuBarModules.isSuperset(of: SystemMonitorEngine.dashboardModules))
        #expect(dashboard.detailedModule == nil)
        #expect(!dashboard.wantsProcesses)
        #expect(dashboard.windowAudience)
    }

    @Test("Window sampling pauses while the main window is not visible")
    func windowVisibilityPausesSampling() async {
        let engine = SystemMonitorEngine.shared
        let wasActive = engine.isActive
        defer {
            engine.setWindowVisible(true)
            engine.stopAllWindowMonitoring()
            if wasActive { engine.activate() } else { engine.deactivate() }
        }
        engine.activate()
        engine.setWindowMonitoring(active: true, focusedModule: nil)
        #expect(engine.currentRequest.windowAudience)
        engine.setWindowVisible(false)
        #expect(!engine.currentRequest.windowAudience)
        engine.setWindowVisible(true)
        #expect(engine.currentRequest.windowAudience)
    }

    @Test("Process reader only ranks the requested metric")
    func processRankings() {
        let reader = ProcessReader()
        let snapshot = reader.read(limit: 3, rankings: .memory)
        #expect(snapshot.topCPU.isEmpty)
        #expect(snapshot.topGPU.isEmpty)
        #expect(snapshot.topMemory.count == 3)
        let memory = snapshot.topMemory.map(\.residentMemoryBytes)
        #expect(memory == memory.sorted(by: >))

        let countsOnly = reader.read(limit: 0, rankings: .cpu)
        #expect(countsOnly.processCount > 0)
        #expect(countsOnly.threadCount > 0)
        #expect(countsOnly.topCPU.isEmpty)

        let energySnapshot = reader.read(limit: 5, rankings: .energy)
        #expect(!energySnapshot.topEnergy.isEmpty)
        #expect(energySnapshot.topEnergy.count <= 5)
        for item in energySnapshot.topEnergy {
            #expect(!item.name.isEmpty)
            #expect(item.residentMemoryBytes > 0)
            #expect(!item.usageBadges(excluding: .energy).isEmpty)
            #expect(!item.detailedHelpSummary.isEmpty)
        }
    }

    @Test("ProcessItem builds multi-resource usage badges for what is being used")
    func processUsageBadges() {
        let item = ProcessItem(
            pid: 4242,
            name: "MonoHub",
            cpuPercent: 18.4,
            residentMemoryBytes: 256 * 1_048_576,
            gpuPercent: 9.2,
            diskBytesPerSec: 4_500_000,
            powerWatts: 1.8,
            recentEnergyJoules: 720,
            energyImpact: 24.5,
            wakeupsPerSec: 30,
            threadCount: 28,
            bundlePath: "/Applications/MonoHub.app"
        )
        #expect(item.isApp)
        #expect(item.formattedPower.contains("W"))
        #expect(item.formattedRecentEnergy.contains("Wh"))

        let cpuBadges = item.usageBadges(excluding: .cpu, maxCount: 4)
        #expect(cpuBadges.map(\.id).contains("gpu"))
        #expect(cpuBadges.map(\.id).contains("ram"))
        #expect(cpuBadges.map(\.id).contains("disk"))

        let energyBadges = item.usageBadges(excluding: .energy, maxCount: 4)
        #expect(energyBadges.map(\.id).contains("cpu"))
        #expect(energyBadges.map(\.id).contains("ram"))
    }

    @Test("CPU reader skips per-core work for the menu bar")
    func cpuReaderSummary() {
        let reader = CPUReader()
        let summary = reader.read(detailed: false)
        #expect(summary.coreUsages.isEmpty)
        #expect((0...1).contains(summary.totalUsage))
        let detailed = reader.read(detailed: true)
        #expect(detailed.coreUsages.count == HardwareInfo.shared.logicalCores)
        #expect(detailed.history.values.count == 2)
    }

    @Test("Disk reader skips I/O counters when only capacity is shown")
    func diskCapacityOnly() {
        let reader = DiskReader()
        let data = reader.read(detailed: false, includeIO: false)
        #expect(data.totalBytes > 0)
        #expect(data.totalReadBytes == 0)
        #expect(data.readHistory.values.isEmpty)
    }

    @Test("Cached sysctl MIBs read the same values as sysctlbyname")
    func sysctlMIB() {
        let memory = SysctlMIB("hw.memsize").read(UInt64(0))
        #expect(memory == HardwareInfo.shared.totalMemoryBytes)
        #expect(SysctlMIB("does.not.exist").read(Int32(0)) == nil)
    }

    @Test("Sampler survives suspend, resume and shutdown in any order")
    func samplerLifecycle() async {
        let received = Mutex(0)
        let sampler = Sampler { _ in received.withLock { $0 += 1 } }
        sampler.update(SampleRequest(menuBarModules: [.cpu, .ram], detailedModule: nil, processLimit: 0))
        sampler.configure(interval: 0.5, running: true)
        sampler.configure(interval: 0.5, running: true)
        sampler.sampleNow()
        sampler.sampleNow()
        try? await Task.sleep(for: .milliseconds(150))
        sampler.configure(interval: 1, running: false)
        sampler.configure(interval: 1, running: false)
        sampler.shutdown()
        sampler.sampleNow()
        try? await Task.sleep(for: .milliseconds(150))
        let afterShutdown = received.withLock { $0 }
        #expect(afterShutdown >= 1)
        try? await Task.sleep(for: .milliseconds(700))
        #expect(received.withLock { $0 } == afterShutdown)

        let idle = Sampler { _ in }
        idle.configure(interval: 1, running: false)
        idle.shutdown()
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("Engine activation is idempotent and deactivation drops all state")
    func engineLifecycle() async {
        let engine = SystemMonitorEngine.shared
        let wasActive = engine.isActive
        defer {
            if wasActive { engine.activate() } else { engine.deactivate() }
        }
        engine.activate()
        engine.activate()
        #expect(engine.isActive)
        engine.setWindowMonitoring(active: true, focusedModule: .ram)
        #expect(engine.currentRequest.detailedModule == .ram)
        try? await Task.sleep(for: .milliseconds(300))

        engine.deactivate()
        engine.deactivate()
        #expect(!engine.isActive)
        #expect(engine.currentRequest == SampleRequest())
        #expect(engine.cpuData == CPUData())
        #expect(engine.ramData == RAMData())
        #expect(engine.powerPolicies == nil)

        engine.setDashboardMonitoring(active: true)
        #expect(engine.currentRequest.isEmpty)
        engine.setDashboardMonitoring(active: false)
    }
}
