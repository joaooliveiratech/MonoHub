import Darwin
import Foundation

nonisolated final class RAMReader {
    private let hostPort = mach_host_self()
    private let totalMemoryBytes = HardwareInfo.shared.totalMemoryBytes
    private let pageSize: UInt64
    private let swapMIB = SysctlMIB("vm.swapusage")
    private let pressureMIB = SysctlMIB("kern.memorystatus_vm_pressure_level")
    private let levelMIB = SysctlMIB("kern.memorystatus_level")
    private var history = RollingHistory()

    init() {
        var size: vm_size_t = 0
        host_page_size(hostPort, &size)
        pageSize = size > 0 ? UInt64(size) : 16_384
    }

    func read() -> RAMData {
        var data = RAMData()
        data.totalBytes = totalMemoryBytes

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return data }

        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        data.appBytes = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize
        data.wiredBytes = UInt64(stats.wire_count) * pageSize
        data.compressedBytes = UInt64(stats.compressor_page_count) * pageSize
        data.cachedBytes = (UInt64(stats.external_page_count) + purgeablePages) * pageSize
        let accounted = data.usedBytes + data.cachedBytes
        data.freeBytes = totalMemoryBytes > accounted ? totalMemoryBytes - accounted : 0

        if let swap = swapMIB.read(xsw_usage()) {
            data.swapUsedBytes = UInt64(swap.xsu_used)
            data.swapTotalBytes = UInt64(swap.xsu_total)
        }
        if let level = pressureMIB.read(Int32(0)) {
            data.pressureLevel = level >= 4 ? .critical : (level >= 2 ? .warning : .normal)
        }
        if let available = levelMIB.read(Int32(0)) {
            data.pressure = min(max(1 - Double(available) / 100, 0), 1)
        }

        history.append(data.usedPercent)
        data.history = history
        return data
    }

    deinit {
        if hostPort != mach_port_t(MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
    }
}
