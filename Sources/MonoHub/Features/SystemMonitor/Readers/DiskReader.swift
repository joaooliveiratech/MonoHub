import Darwin
import Foundation
import IOKit

nonisolated final class DiskReader {
    private var drivers: [io_service_t] = []
    private var samplesSinceDriverRefresh = 0
    private var previousCounters: [UInt64: DriverCounters] = [:]
    private var currentCounters: [UInt64: DriverCounters] = [:]
    private var previousTimestamp: UInt64 = 0
    private var readHistory = RollingHistory()
    private var writeHistory = RollingHistory()
    private var volumeName = "Macintosh HD"
    private var fileSystem: String?
    private var importantAvailable: UInt64?
    private var lastVolumeRefresh: UInt64 = 0

    struct DriverCounters: Equatable {
        var read: UInt64
        var written: UInt64
    }

    deinit {
        IORegistry.release(drivers)
    }

    func read(detailed: Bool, includeIO: Bool = true) -> DiskData {
        var data = DiskData()

        var stat = statvfs()
        if statvfs("/", &stat) == 0 {
            let blockSize = UInt64(stat.f_frsize)
            data.totalBytes = blockSize * UInt64(stat.f_blocks)
            data.freeBytes = blockSize * UInt64(stat.f_bavail)
        }

        let now = monotonicNanoseconds()
        if detailed, now &- lastVolumeRefresh > 30_000_000_000 || lastVolumeRefresh == 0 {
            refreshVolumeDetails()
            lastVolumeRefresh = now
        }
        data.volumeName = volumeName
        data.fileSystem = fileSystem
        data.availableForImportantUsageBytes = importantAvailable

        guard includeIO else {
            previousTimestamp = 0
            data.readHistory = readHistory
            data.writeHistory = writeHistory
            return data
        }

        readIOCounters(into: &currentCounters)
        if previousTimestamp > 0, now > previousTimestamp {
            let seconds = Double(now - previousTimestamp) / 1_000_000_000
            let delta = Self.delta(from: previousCounters, to: currentCounters)
            data.readBytesPerSec = UInt64(Double(delta.read) / seconds)
            data.writeBytesPerSec = UInt64(Double(delta.written) / seconds)
        }
        data.totalReadBytes = currentCounters.values.reduce(0) { $0 &+ $1.read }
        data.totalWrittenBytes = currentCounters.values.reduce(0) { $0 &+ $1.written }
        swap(&previousCounters, &currentCounters)
        previousTimestamp = now

        readHistory.append(Double(data.readBytesPerSec))
        writeHistory.append(Double(data.writeBytesPerSec))
        data.readHistory = readHistory
        data.writeHistory = writeHistory
        return data
    }

    static func delta(from previous: [UInt64: DriverCounters], to current: [UInt64: DriverCounters]) -> DriverCounters {
        var total = DriverCounters(read: 0, written: 0)
        for (id, counters) in current {
            guard let before = previous[id] else { continue }
            if counters.read >= before.read { total.read &+= counters.read - before.read }
            if counters.written >= before.written { total.written &+= counters.written - before.written }
        }
        return total
    }

    private func readIOCounters(into counters: inout [UInt64: DriverCounters]) {
        samplesSinceDriverRefresh += 1
        if drivers.isEmpty || samplesSinceDriverRefresh >= 120 {
            IORegistry.release(drivers)
            drivers = IORegistry.services(matching: "IOBlockStorageDriver")
            samplesSinceDriverRefresh = 0
        }

        counters.removeAll(keepingCapacity: true)
        for driver in drivers {
            guard let stats = IORegistry.dictionary(driver, "Statistics") else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS else { continue }
            counters[id] = DriverCounters(
                read: (stats["Bytes (Read)"] as? NSNumber)?.nonNegativeUInt64 ?? 0,
                written: (stats["Bytes (Write)"] as? NSNumber)?.nonNegativeUInt64 ?? 0
            )
        }
    }

    private func refreshVolumeDetails() {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        if let name = values.volumeLocalizedName, !name.isEmpty {
            volumeName = name
        }
        fileSystem = values.volumeLocalizedFormatDescription
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            importantAvailable = UInt64(important)
        }
    }
}
