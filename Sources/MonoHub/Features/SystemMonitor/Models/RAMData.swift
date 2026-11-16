import Foundation

nonisolated enum MemoryPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return localized("High")
        case .critical: return localized("Critical", context: "pressure")
        }
    }
}

nonisolated struct RAMData: Sendable, Equatable {
    var totalBytes: UInt64 = 0
    var appBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var cachedBytes: UInt64 = 0
    var freeBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var pressureLevel: MemoryPressureLevel = .normal
    var pressure: Double = 0
    var history = RollingHistory()
    var topProcesses: [ProcessItem] = []

    var usedBytes: UInt64 {
        min(appBytes + wiredBytes + compressedBytes, totalBytes)
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}
