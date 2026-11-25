import Darwin
import Foundation
import IOKit

nonisolated struct ProcessSnapshot: Sendable {
    var topCPU: [ProcessItem] = []
    var topMemory: [ProcessItem] = []
    var topGPU: [ProcessItem] = []
    var topEnergy: [ProcessItem] = []
    var topDisk: [ProcessItem] = []
    var processCount = 0
    var threadCount = 0
}

nonisolated struct ProcessRankings: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    static let cpu = ProcessRankings(rawValue: 1 << 0)
    static let memory = ProcessRankings(rawValue: 1 << 1)
    static let gpu = ProcessRankings(rawValue: 1 << 2)
    static let energy = ProcessRankings(rawValue: 1 << 3)
    static let disk = ProcessRankings(rawValue: 1 << 4)
    static let all: ProcessRankings = [.cpu, .memory, .gpu, .energy, .disk]
}

nonisolated final class ProcessReader {
    private struct Sample {
        let pid: pid_t
        let cpuPercent: Double
        let residentBytes: UInt64
        let diskBytesPerSec: UInt64
        let powerWatts: Double
        let recentEnergyJoules: Double
        let energyImpact: Double
        let wakeupsPerSec: Double
        let energyRankScore: Double
    }

    private struct MetricsState {
        var cpuTimeNS: UInt64
        var energyNJ: UInt64
        var wakeups: UInt64
        var diskBytes: UInt64
        var smoothedPowerWatts: Double
        var windowStartTimestamp: UInt64
        var windowStartEnergyNJ: UInt64
    }

    private static let recentWindowNanoseconds: UInt64 = 900_000_000_000

    private let hardware = HardwareInfo.shared
    private let hostPort = mach_host_self()
    private var pidBuffer: [pid_t] = []
    private var samplesBuffer: [Sample] = []
    private var previousMetrics: [pid_t: MetricsState] = [:]
    private var currentMetrics: [pid_t: MetricsState] = [:]
    private var previousGPUTime: [pid_t: UInt64] = [:]
    private var currentGPUTime: [pid_t: UInt64] = [:]
    private var latestGPUPercent: [pid_t: Double] = [:]
    private var previousTimestamp: UInt64 = 0
    private var previousGPUTimestamp: UInt64 = 0
    private var identityCache: [pid_t: (name: String, bundlePath: String?)] = [:]
    private var threadCountCache: [pid_t: Int] = [:]
    private var accelerators: [io_service_t] = []
    private var ticksSinceCachePrune = 0

    func read(limit: Int, includeGPU: Bool) -> ProcessSnapshot {
        read(limit: limit, rankings: includeGPU ? [.cpu, .memory, .gpu] : [.cpu, .memory])
    }

    func read(limit: Int, rankings: ProcessRankings) -> ProcessSnapshot {
        var snapshot = ProcessSnapshot()
        let systemCounts = Self.readSystemCounts(hostPort: hostPort)
        snapshot.processCount = systemCounts.tasks
        snapshot.threadCount = systemCounts.threads

        guard limit > 0, !rankings.isEmpty else {
            if snapshot.processCount == 0 {
                let pids = listPIDs()
                snapshot.processCount = pids.count
            }
            return snapshot
        }

        let pids = listPIDs()
        if snapshot.processCount == 0 {
            snapshot.processCount = pids.count
        }

        let now = monotonicNanoseconds()
        let nowMach = mach_absolute_time()
        let elapsed = previousTimestamp > 0 && now > previousTimestamp ? Double(now - previousTimestamp) : 0
        let elapsedSeconds = elapsed / 1_000_000_000.0
        let cores = Double(max(hardware.logicalCores, 1))

        if rankings.contains(.gpu) || rankings.contains(.energy) {
            updateGPUUsage(now: now)
        } else {
            previousGPUTime.removeAll(keepingCapacity: true)
            currentGPUTime.removeAll(keepingCapacity: true)
            latestGPUPercent.removeAll(keepingCapacity: true)
            previousGPUTimestamp = 0
        }

        samplesBuffer.removeAll(keepingCapacity: true)
        if samplesBuffer.capacity < pids.count {
            samplesBuffer.reserveCapacity(pids.count)
        }
        currentMetrics.removeAll(keepingCapacity: true)
        if currentMetrics.capacity < pids.count {
            currentMetrics.reserveCapacity(pids.count)
        }

        var rusage = rusage_info_v6()
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        var fallbackThreads = 0

        for pid in pids where pid > 0 {
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { ptr in
                proc_pid_rusage(pid, RUSAGE_INFO_V6, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: rusage_info_t?.self))
            }

            let cpuTime: UInt64
            let residentBytes: UInt64
            let energyNJ: UInt64
            let wakeups: UInt64
            let diskBytes: UInt64
            let startAbstime: UInt64

            if rusageResult == 0 {
                cpuTime = hardware.machTicksToNanoseconds(rusage.ri_user_time &+ rusage.ri_system_time)
                residentBytes = rusage.ri_phys_footprint > 0 ? rusage.ri_phys_footprint : rusage.ri_resident_size
                energyNJ = rusage.ri_energy_nj
                wakeups = rusage.ri_pkg_idle_wkups &+ (rusage.ri_interrupt_wkups / 4)
                diskBytes = rusage.ri_diskio_bytesread &+ rusage.ri_diskio_byteswritten
                startAbstime = rusage.ri_proc_start_abstime
            } else {
                guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize else { continue }
                cpuTime = hardware.machTicksToNanoseconds(taskInfo.pti_total_user &+ taskInfo.pti_total_system)
                residentBytes = taskInfo.pti_resident_size
                energyNJ = 0
                wakeups = 0
                diskBytes = 0
                startAbstime = 0
                fallbackThreads &+= Int(taskInfo.pti_threadnum)
            }

            var cpuPercent = 0.0
            var rawCorePercent = 0.0
            var diskRate: UInt64 = 0
            var wakeupsRate = 0.0
            var instantWatts = 0.0
            var smoothedWatts = 0.0
            var winStartTS = now
            var winStartEnergy = energyNJ

            let processAgeNS = (startAbstime > 0 && nowMach > startAbstime)
                ? max(hardware.machTicksToNanoseconds(nowMach - startAbstime), 1_000_000_000)
                : 60_000_000_000
            let processAgeSec = max(Double(processAgeNS) / 1_000_000_000.0, 1.0)
            let lifetimeJoules = Double(energyNJ) / 1_000_000_000.0
            let lifetimeAvgWatts = min(lifetimeJoules / processAgeSec, 65.0)

            if let prev = previousMetrics[pid] {
                winStartTS = prev.windowStartTimestamp
                winStartEnergy = prev.windowStartEnergyNJ
                if now &- winStartTS > Self.recentWindowNanoseconds {
                    winStartTS = now &- (Self.recentWindowNanoseconds / 2)
                    winStartEnergy = prev.energyNJ
                }

                if elapsed > 0 {
                    if cpuTime >= prev.cpuTimeNS {
                        rawCorePercent = Double(cpuTime &- prev.cpuTimeNS) / elapsed * 100.0
                        cpuPercent = min(rawCorePercent / cores, 100.0)
                    }
                    if diskBytes >= prev.diskBytes, elapsedSeconds > 0 {
                        diskRate = UInt64(Double(diskBytes &- prev.diskBytes) / elapsedSeconds)
                    }
                    if wakeups >= prev.wakeups, elapsedSeconds > 0 {
                        wakeupsRate = Double(wakeups &- prev.wakeups) / elapsedSeconds
                    }
                    if energyNJ >= prev.energyNJ {
                        instantWatts = min(Double(energyNJ &- prev.energyNJ) / elapsed, 80.0)
                    } else if rawCorePercent > 0 {
                        instantWatts = (rawCorePercent / 100.0) * 1.2
                    }
                }
                smoothedWatts = prev.smoothedPowerWatts > 0
                    ? (prev.smoothedPowerWatts * 0.65 + instantWatts * 0.35)
                    : max(instantWatts, lifetimeAvgWatts * 0.5)
            } else {
                smoothedWatts = lifetimeAvgWatts
                instantWatts = lifetimeAvgWatts
            }

            currentMetrics[pid] = MetricsState(
                cpuTimeNS: cpuTime,
                energyNJ: energyNJ,
                wakeups: wakeups,
                diskBytes: diskBytes,
                smoothedPowerWatts: smoothedWatts,
                windowStartTimestamp: winStartTS,
                windowStartEnergyNJ: winStartEnergy
            )

            let gpuPct = latestGPUPercent[pid] ?? 0
            let effectiveWatts = max(instantWatts, smoothedWatts * 0.8) + (gpuPct * 0.06)
            let sessionDeltaJoules = energyNJ >= winStartEnergy ? Double(energyNJ &- winStartEnergy) / 1_000_000_000.0 : 0
            let recentBaselineJoules = lifetimeAvgWatts * min(processAgeSec, 900.0)
            let recentEnergyJoules = max(sessionDeltaJoules, recentBaselineJoules)

            let impact = min(
                max(effectiveWatts * 14.0, rawCorePercent * 0.65)
                    + min(wakeupsRate * 0.04, 25.0)
                    + gpuPct * 0.5
                    + min(Double(diskRate) / 5_000_000.0, 10.0),
                100.0
            )

            let energyRankScore = impact * 1.6 + min(recentEnergyJoules * 0.12, 80.0) + (effectiveWatts * 12.0)

            samplesBuffer.append(Sample(
                pid: pid,
                cpuPercent: cpuPercent,
                residentBytes: residentBytes,
                diskBytesPerSec: diskRate,
                powerWatts: effectiveWatts,
                recentEnergyJoules: recentEnergyJoules,
                energyImpact: impact,
                wakeupsPerSec: wakeupsRate,
                energyRankScore: energyRankScore
            ))
        }

        if snapshot.threadCount == 0 {
            snapshot.threadCount = max(fallbackThreads, snapshot.processCount * 2)
        }

        swap(&previousMetrics, &currentMetrics)
        previousTimestamp = now

        ticksSinceCachePrune &+= 1
        if ticksSinceCachePrune >= 32 || identityCache.count > 512 {
            ticksSinceCachePrune = 0
            identityCache = identityCache.filter { previousMetrics[$0.key] != nil }
        }

        threadCountCache.removeAll(keepingCapacity: true)
        if rankings.contains(.cpu) {
            snapshot.topCPU = Self.top(samplesBuffer, limit: limit) { $0.cpuPercent > $1.cpuPercent }
                .map { makeItem(from: $0) }
        }
        if rankings.contains(.memory) {
            snapshot.topMemory = Self.top(samplesBuffer, limit: limit) { $0.residentBytes > $1.residentBytes }
                .map { makeItem(from: $0) }
        }
        if rankings.contains(.gpu) {
            snapshot.topGPU = buildTopGPU(limit: limit)
        }
        if rankings.contains(.energy) {
            snapshot.topEnergy = buildTopEnergy(limit: limit)
        }
        if rankings.contains(.disk) {
            snapshot.topDisk = Self.top(samplesBuffer, limit: limit) { a, b in
                if a.diskBytesPerSec != b.diskBytesPerSec {
                    return a.diskBytesPerSec > b.diskBytesPerSec
                }
                return a.cpuPercent > b.cpuPercent
            }
            .filter { $0.diskBytesPerSec > 0 || $0.cpuPercent >= 0.5 }
            .map { makeItem(from: $0) }
        }

        return snapshot
    }

    static func readSystemCounts(hostPort: mach_port_t) -> (tasks: Int, threads: Int) {
        var pset: processor_set_name_t = 0
        guard processor_set_default(hostPort, &pset) == KERN_SUCCESS else { return (0, 0) }
        defer { mach_port_deallocate(mach_task_self_, pset) }

        var info = processor_set_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<processor_set_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(pset, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, 0) }
        return (Int(info.task_count), Int(info.thread_count))
    }

    private func buildTopEnergy(limit: Int) -> [ProcessItem] {

        let candidates = Self.top(samplesBuffer, limit: max(limit * 3, 12)) { a, b in
            a.energyRankScore > b.energyRankScore
        }
        let scored = candidates.compactMap { sample -> (ProcessItem, Double)? in
            guard sample.energyRankScore >= 0.05 || sample.recentEnergyJoules >= 0.5 || sample.cpuPercent >= 0.1 else {
                return nil
            }
            let item = makeItem(from: sample)
            let appMultiplier = item.isApp ? 1.35 : 1.0
            return (item, sample.energyRankScore * appMultiplier)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)

        if !scored.isEmpty {
            return scored
        }
        return Self.top(samplesBuffer, limit: limit) { $0.cpuPercent > $1.cpuPercent }
            .map { makeItem(from: $0) }
    }

    private static func top(_ samples: [Sample], limit: Int, by areInOrder: (Sample, Sample) -> Bool) -> [Sample] {
        var best: [Sample] = []
        best.reserveCapacity(limit + 1)
        for sample in samples {
            if best.count == limit, let last = best.last, !areInOrder(sample, last) { continue }
            let index = best.firstIndex { areInOrder(sample, $0) } ?? best.count
            best.insert(sample, at: index)
            if best.count > limit { best.removeLast() }
        }
        return best
    }

    private func listPIDs() -> ArraySlice<pid_t> {
        let estimated = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        let capacity = max(Int(estimated) / MemoryLayout<pid_t>.size + 64, 256)
        if pidBuffer.count < capacity {
            pidBuffer = [pid_t](repeating: 0, count: capacity)
        }
        let bytes = pidBuffer.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, raw.baseAddress, Int32(raw.count))
        }
        guard bytes > 0 else { return [] }
        return pidBuffer[0..<min(Int(bytes) / MemoryLayout<pid_t>.size, pidBuffer.count)]
    }

    private func makeItem(from sample: Sample, overrideGPU: Double? = nil) -> ProcessItem {
        let identity = identity(for: sample.pid)
        let gpu = overrideGPU ?? latestGPUPercent[sample.pid] ?? 0
        let threads = readThreadCount(for: sample.pid)
        return ProcessItem(
            pid: sample.pid,
            name: identity.name,
            cpuPercent: sample.cpuPercent,
            residentMemoryBytes: sample.residentBytes,
            gpuPercent: gpu,
            diskBytesPerSec: sample.diskBytesPerSec,
            powerWatts: sample.powerWatts,
            recentEnergyJoules: sample.recentEnergyJoules,
            energyImpact: sample.energyImpact,
            wakeupsPerSec: sample.wakeupsPerSec,
            threadCount: threads,
            bundlePath: identity.bundlePath
        )
    }

    private func readThreadCount(for pid: pid_t) -> Int {
        // The same process often appears in several rankings; one syscall per tick is enough.
        if let cached = threadCountCache[pid] {
            return cached
        }
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let count = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? Int(info.pti_threadnum) : 0
        threadCountCache[pid] = count
        return count
    }

    private func identity(for pid: pid_t) -> (name: String, bundlePath: String?) {
        if let cached = identityCache[pid] {
            return cached
        }

        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &path, UInt32(path.count))
        let executablePath = pathLength > 0 ? String(nullTerminated: path) : nil

        let bundlePath = executablePath.flatMap(Self.bundlePath(forExecutable:))
        var name = executablePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        if let bundlePath, name.isEmpty || name.caseInsensitiveCompare("Electron") == .orderedSame || name.caseInsensitiveCompare("MacOS") == .orderedSame {
            let bundleName = URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
            if !bundleName.isEmpty {
                name = bundleName
            }
        }
        if name.isEmpty {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            name = String(nullTerminated: nameBuffer)
        }
        if name.isEmpty {
            name = "PID \(pid)"
        }

        let identity = (name, bundlePath)
        identityCache[pid] = identity
        return identity
    }

    private static func bundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/", options: .caseInsensitive) else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private func updateGPUUsage(now: UInt64) {
        currentGPUTime.removeAll(keepingCapacity: true)
        latestGPUPercent.removeAll(keepingCapacity: true)

        if accelerators.isEmpty {
            accelerators = IORegistry.services(matching: "IOAccelerator")
        }

        for accelerator in accelerators {
            var children = io_iterator_t()
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            var child = IOIteratorNext(children)
            while child != 0 {
                if let creator = IORegistry.property(child, "IOUserClientCreator") as? String,
                   let pid = Self.pid(fromCreator: creator),
                   let usage = IORegistry.property(child, "AppUsage") as? [[String: Any]] {
                    let total = usage.reduce(UInt64(0)) { $0 &+ (($1["accumulatedGPUTime"] as? NSNumber)?.nonNegativeUInt64 ?? 0) }
                    currentGPUTime[pid, default: 0] &+= total
                }
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            IOObjectRelease(children)
        }

        let elapsed = previousGPUTimestamp > 0 && now > previousGPUTimestamp ? Double(now - previousGPUTimestamp) : 0
        if elapsed > 0 {
            for (pid, time) in currentGPUTime {
                if let previous = previousGPUTime[pid], time >= previous {
                    let pct = min(Double(time - previous) / elapsed * 100, 100)
                    if pct >= 0.1 {
                        latestGPUPercent[pid] = pct
                    }
                }
            }
        }
        swap(&previousGPUTime, &currentGPUTime)
        previousGPUTimestamp = now
    }

    private func buildTopGPU(limit: Int) -> [ProcessItem] {
        let ranked = latestGPUPercent
            .filter { $0.value >= 0.1 }
            .sorted { $0.value > $1.value }
            .prefix(limit)

        return ranked.map { pid, gpuPct in
            if let sample = samplesBuffer.first(where: { $0.pid == pid }) {
                return makeItem(from: sample, overrideGPU: gpuPct)
            }
            let identity = identity(for: pid)
            return ProcessItem(
                pid: pid,
                name: identity.name,
                gpuPercent: gpuPct,
                threadCount: readThreadCount(for: pid),
                bundlePath: identity.bundlePath
            )
        }
    }

    private static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits)
    }

    deinit {
        IORegistry.release(accelerators)
        if hostPort != mach_port_t(MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
    }
}
