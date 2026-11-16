import Darwin
import Foundation
import IOKit

nonisolated enum CoreCluster: Sendable {
    case efficiency
    case performance
}

nonisolated struct HardwareInfo: Sendable {
    static let shared = HardwareInfo()

    let chipName: String
    let modelIdentifier: String
    let physicalCores: Int
    let logicalCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let totalMemoryBytes: UInt64
    let coreClusters: [CoreCluster]
    let gpuCoreCount: Int?
    let machTimebaseNumer: UInt32
    let machTimebaseDenom: UInt32

    var coresSummary: String {
        if efficiencyCores > 0 {
            return localized("%d performance + %d efficiency", performanceCores, efficiencyCores)
        }
        return localized("%d cores", physicalCores)
    }

    func machTicksToNanoseconds(_ ticks: UInt64) -> UInt64 {
        guard machTimebaseNumer != machTimebaseDenom, machTimebaseDenom > 0 else { return ticks }
        return ticks.multipliedReportingOverflow(by: UInt64(machTimebaseNumer)).partialValue / UInt64(machTimebaseDenom)
    }

    private init() {
        self.chipName = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        self.modelIdentifier = Self.sysctlString("hw.model") ?? "Mac"
        self.physicalCores = Self.sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        self.logicalCores = ProcessInfo.processInfo.processorCount
        self.performanceCores = Self.sysctlInt("hw.perflevel0.physicalcpu") ?? physicalCores
        self.efficiencyCores = Self.sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        self.totalMemoryBytes = Self.sysctlUInt64("hw.memsize") ?? 0
        self.coreClusters = Self.readCoreClusters(logicalCores: logicalCores, efficiencyCores: efficiencyCores)
        self.gpuCoreCount = Self.readGPUCoreCount()

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        self.machTimebaseNumer = timebase.numer
        self.machTimebaseDenom = timebase.denom
    }

    private static func readCoreClusters(logicalCores: Int, efficiencyCores: Int) -> [CoreCluster] {
        var clusters = [CoreCluster?](repeating: nil, count: logicalCores)
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if root != 0 {
            var children = io_iterator_t()
            if IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &children) == KERN_SUCCESS {
                var entry = IOIteratorNext(children)
                while entry != 0 {
                    let cpuID = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Int
                    let typeData = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Data
                    if let cpuID, cpuID >= 0, cpuID < logicalCores, let first = typeData?.first {
                        clusters[cpuID] = first == UInt8(ascii: "E") ? .efficiency : .performance
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(children)
                }
                IOObjectRelease(children)
            }
            IOObjectRelease(root)
        }

        if clusters.allSatisfy({ $0 != nil }) {
            return clusters.compactMap { $0 }
        }
        return (0..<logicalCores).map { $0 < efficiencyCores ? .efficiency : .performance }
    }

    private static func readGPUCoreCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
