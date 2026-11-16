import Darwin
import Foundation

nonisolated final class CPUReader {
    private static let ticksPerCore = 4

    private let hostPort = mach_host_self()
    private var previousLoad = host_cpu_load_info_data_t()
    private var previousCoreTicks: [UInt32] = []
    private var currentCoreTicks: [UInt32] = []
    private var lastUsage: (total: Double, user: Double, system: Double) = (0, 0, 0)
    private var lastCoreUsages: [Double] = []
    private var history = RollingHistory()

    func read(detailed: Bool = true) -> CPUData {
        let usage = readHostUsage()
        history.append(usage.total)

        var data = CPUData()
        data.totalUsage = usage.total
        data.userUsage = usage.user
        data.systemUsage = usage.system
        if detailed {
            data.coreUsages = readCoreUsages()
            data.loadAverage = readLoadAverages()
            let counts = ProcessReader.readSystemCounts(hostPort: hostPort)
            if counts.tasks > 0 {
                data.processCount = counts.tasks
                data.threadCount = counts.threads
            }
        }
        data.history = history
        return data
    }

    private func readHostUsage() -> (total: Double, user: Double, system: Double) {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var current = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &current) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return lastUsage }

        let previous = previousLoad
        let user = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return lastUsage }

        previousLoad = current
        lastUsage = (
            ((user + system + nice) / total).clamped(to: 0...1),
            ((user + nice) / total).clamped(to: 0...1),
            (system / total).clamped(to: 0...1)
        )
        return lastUsage
    }

    private func readCoreUsages() -> [Double] {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount) == KERN_SUCCESS,
              let info else {
            return lastCoreUsages
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let cores = Int(processorCount)
        let stride = Int(CPU_STATE_MAX)
        let width = Self.ticksPerCore
        if currentCoreTicks.count != cores * width {
            currentCoreTicks = [UInt32](repeating: 0, count: cores * width)
        }
        for core in 0..<cores {
            let base = core * stride
            currentCoreTicks[core * width] = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            currentCoreTicks[core * width + 1] = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            currentCoreTicks[core * width + 2] = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            currentCoreTicks[core * width + 3] = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
        }
        if previousCoreTicks.count != currentCoreTicks.count {
            previousCoreTicks = [UInt32](repeating: 0, count: currentCoreTicks.count)
        }

        var usages = [Double](repeating: 0, count: cores)
        var elapsedTicks = 0.0
        for core in 0..<cores {
            let offset = core * width
            let user = Double(currentCoreTicks[offset] &- previousCoreTicks[offset])
            let system = Double(currentCoreTicks[offset + 1] &- previousCoreTicks[offset + 1])
            let idle = Double(currentCoreTicks[offset + 2] &- previousCoreTicks[offset + 2])
            let nice = Double(currentCoreTicks[offset + 3] &- previousCoreTicks[offset + 3])
            let total = user + system + idle + nice
            elapsedTicks += total
            usages[core] = total > 0 ? ((user + system + nice) / total).clamped(to: 0...1) : 0
        }
        guard elapsedTicks > 0 || lastCoreUsages.count != cores else { return lastCoreUsages }

        swap(&previousCoreTicks, &currentCoreTicks)
        lastCoreUsages = usages
        return usages
    }

    private func readLoadAverages() -> LoadAverage {
        var values: (Double, Double, Double) = (0, 0, 0)
        let count = withUnsafeMutablePointer(to: &values) { pointer in
            pointer.withMemoryRebound(to: Double.self, capacity: 3) { getloadavg($0, 3) }
        }
        guard count == 3 else { return LoadAverage() }
        return LoadAverage(one: values.0, five: values.1, fifteen: values.2)
    }

    deinit {
        if hostPort != mach_port_t(MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
    }
}
