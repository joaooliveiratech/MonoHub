import Foundation

nonisolated enum ProcessMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case gpu
    case energy
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "% CPU"
        case .memory: return localized("Memory")
        case .gpu: return "% GPU"
        case .energy: return localized("Energy Impact")
        case .disk: return localized("Disk I/O")
        }
    }

    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return localized("Memory")
        case .gpu: return "GPU"
        case .energy: return localized("Energy")
        case .disk: return localized("Disk")
        }
    }
}

nonisolated struct ProcessUsageBadge: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let value: String
    let symbol: String
    let metric: ProcessMetric?
}

nonisolated struct ProcessItem: Identifiable, Sendable, Equatable {
    let pid: pid_t
    let name: String
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let gpuPercent: Double
    let diskBytesPerSec: UInt64
    let powerWatts: Double
    let recentEnergyJoules: Double
    let energyImpact: Double
    let wakeupsPerSec: Double
    let threadCount: Int
    let bundlePath: String?

    var id: pid_t { pid }

    var isApp: Bool {
        bundlePath != nil
    }

    init(
        pid: pid_t,
        name: String,
        cpuPercent: Double = 0,
        residentMemoryBytes: UInt64 = 0,
        gpuPercent: Double = 0,
        diskBytesPerSec: UInt64 = 0,
        powerWatts: Double = 0,
        recentEnergyJoules: Double = 0,
        energyImpact: Double = 0,
        wakeupsPerSec: Double = 0,
        threadCount: Int = 0,
        bundlePath: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
        self.gpuPercent = gpuPercent
        self.diskBytesPerSec = diskBytesPerSec
        self.powerWatts = powerWatts
        self.recentEnergyJoules = recentEnergyJoules
        self.energyImpact = energyImpact
        self.wakeupsPerSec = wakeupsPerSec
        self.threadCount = threadCount
        self.bundlePath = bundlePath
    }

    var formattedCPU: String {
        "\(Formatting.decimal(cpuPercent, digits: 1))%"
    }

    var formattedGPU: String {
        "\(Formatting.decimal(gpuPercent, digits: 1))%"
    }

    var formattedMemory: String {
        Formatting.bytes(residentMemoryBytes)
    }

    var formattedDiskSpeed: String {
        Formatting.speed(diskBytesPerSec)
    }

    var formattedPower: String {
        if powerWatts >= 0.05 {
            return Formatting.watts(powerWatts)
        }
        if energyImpact >= 0.1 {
            return Formatting.decimal(energyImpact, digits: 1)
        }
        return formattedRecentEnergy
    }

    var formattedRecentEnergy: String {
        let wattHours = recentEnergyJoules / 3_600.0
        if wattHours >= 0.1 {
            return "\(Formatting.decimal(wattHours, digits: wattHours >= 10 ? 1 : 2)) Wh"
        }
        let milliWattHours = wattHours * 1_000.0
        if milliWattHours >= 1.0 {
            return "\(Int(milliWattHours.rounded())) mWh"
        }
        if recentEnergyJoules >= 1.0 {
            return "\(Int(recentEnergyJoules.rounded())) J"
        }
        return "0 mWh"
    }

    func usageBadges(excluding primary: ProcessMetric, maxCount: Int = 3) -> [ProcessUsageBadge] {
        var badges: [ProcessUsageBadge] = []
        badges.reserveCapacity(4)

        if primary != .cpu && (cpuPercent >= 0.1 || primary == .energy || primary == .memory) {
            badges.append(ProcessUsageBadge(
                id: "cpu",
                label: "CPU",
                value: formattedCPU,
                symbol: "cpu",
                metric: .cpu
            ))
        }

        if primary != .gpu && gpuPercent >= 0.1 {
            badges.append(ProcessUsageBadge(
                id: "gpu",
                label: "GPU",
                value: formattedGPU,
                symbol: "cube.transparent",
                metric: .gpu
            ))
        }

        if primary != .memory && residentMemoryBytes > 0 {
            badges.append(ProcessUsageBadge(
                id: "ram",
                label: "RAM",
                value: formattedMemory,
                symbol: "memorychip",
                metric: .memory
            ))
        }

        if primary != .disk && diskBytesPerSec >= 1_024 {
            badges.append(ProcessUsageBadge(
                id: "disk",
                label: "SSD",
                value: formattedDiskSpeed,
                symbol: "internaldrive",
                metric: .disk
            ))
        }

        if primary != .energy && powerWatts >= 0.05 {
            badges.append(ProcessUsageBadge(
                id: "power",
                label: localized("Power"),
                value: Formatting.watts(powerWatts),
                symbol: "bolt.fill",
                metric: .energy
            ))
        }

        if primary == .energy && recentEnergyJoules >= 3.6 {
            badges.append(ProcessUsageBadge(
                id: "recent",
                label: localized("Recent"),
                value: formattedRecentEnergy,
                symbol: "clock.arrow.circlepath",
                metric: .energy
            ))
        }

        if badges.count < maxCount && wakeupsPerSec >= 15 {
            badges.append(ProcessUsageBadge(
                id: "wakeups",
                label: "Wake",
                value: "\(Int(wakeupsPerSec.rounded()))/s",
                symbol: "waveform.path.ecg",
                metric: nil
            ))
        }

        if badges.count < maxCount && threadCount > 0 && primary == .cpu {
            badges.append(ProcessUsageBadge(
                id: "threads",
                label: "Threads",
                value: "\(threadCount)t",
                symbol: "point.3.connected.trianglepath.dotted",
                metric: nil
            ))
        }

        return Array(badges.prefix(maxCount))
    }

    var detailedHelpSummary: String {
        var parts = ["\(name) (PID \(pid))"]
        parts.append("CPU: \(formattedCPU)")
        parts.append("\(localized("Memory")): \(formattedMemory)")
        if gpuPercent >= 0.1 {
            parts.append("GPU: \(formattedGPU)")
        }
        if diskBytesPerSec > 0 {
            parts.append("\(localized("Disk")): \(formattedDiskSpeed)")
        }
        if powerWatts >= 0.01 || recentEnergyJoules >= 1 {
            parts.append("\(localized("Energy")): \(Formatting.watts(powerWatts)) (\(localized("Recent")): \(formattedRecentEnergy))")
        }
        if wakeupsPerSec >= 1 {
            parts.append("Wakeups: \(Int(wakeupsPerSec.rounded()))/s")
        }
        if threadCount > 0 {
            parts.append("Threads: \(threadCount)")
        }
        return parts.joined(separator: " · ")
    }
}
