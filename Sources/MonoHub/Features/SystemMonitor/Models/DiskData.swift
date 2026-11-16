import Foundation

nonisolated struct DiskData: Sendable, Equatable {
    var volumeName: String = "Macintosh HD"
    var fileSystem: String?
    var totalBytes: UInt64 = 0
    var freeBytes: UInt64 = 0
    var availableForImportantUsageBytes: UInt64?
    var readBytesPerSec: UInt64 = 0
    var writeBytesPerSec: UInt64 = 0
    var totalReadBytes: UInt64 = 0
    var totalWrittenBytes: UInt64 = 0
    var readHistory = RollingHistory()
    var writeHistory = RollingHistory()
    var topProcesses: [ProcessItem] = []

    var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}
