import Darwin
import Foundation
import IOKit

nonisolated enum IORegistry {
    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func number(_ entry: io_registry_entry_t, _ key: String) -> NSNumber? {
        property(entry, key) as? NSNumber
    }

    static func dictionary(_ entry: io_registry_entry_t, _ key: String) -> [String: Any]? {
        property(entry, key) as? [String: Any]
    }

    static func services(matching className: String) -> [io_service_t] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            result.append(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    static func release(_ services: [io_service_t]) {
        for service in services {
            IOObjectRelease(service)
        }
    }
}

extension NSNumber {
    nonisolated var nonNegativeUInt64: UInt64 {
        let value = int64Value
        return value > 0 ? UInt64(value) : 0
    }
}

nonisolated struct SysctlMIB {
    private let mib: [Int32]
    private let name: String

    init(_ name: String) {
        self.name = name
        var buffer = [Int32](repeating: 0, count: Int(CTL_MAXNAME))
        var length = buffer.count
        if sysctlnametomib(name, &buffer, &length) == 0 {
            mib = Array(buffer.prefix(length))
        } else {
            mib = []
        }
    }

    func read<Value: BitwiseCopyable>(_ initial: Value) -> Value? {
        var value = initial
        var size = MemoryLayout<Value>.size
        let status = withUnsafeMutableBytes(of: &value) { raw -> Int32 in
            if mib.isEmpty {
                return sysctlbyname(name, raw.baseAddress, &size, nil, 0)
            }
            return mib.withUnsafeBufferPointer { buffer in
                sysctl(UnsafeMutablePointer(mutating: buffer.baseAddress), u_int(buffer.count), raw.baseAddress, &size, nil, 0)
            }
        }
        return status == 0 ? value : nil
    }
}

nonisolated func monotonicNanoseconds() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

extension String {
    nonisolated init(nullTerminated buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
