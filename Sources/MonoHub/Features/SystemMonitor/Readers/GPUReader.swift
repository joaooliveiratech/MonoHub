import Foundation
import IOKit

nonisolated final class GPUReader {
    private var accelerators: [io_service_t] = []
    private var history = RollingHistory()

    deinit {
        IORegistry.release(accelerators)
    }

    func read() -> GPUData {
        if accelerators.isEmpty {
            accelerators = IORegistry.services(matching: "IOAccelerator")
        }

        var data = GPUData()
        for service in accelerators {
            guard let stats = IORegistry.dictionary(service, "PerformanceStatistics") else { continue }
            data.deviceUtilization = max(data.deviceUtilization, ratio(stats["Device Utilization %"]))
            data.rendererUtilization = max(data.rendererUtilization, ratio(stats["Renderer Utilization %"]))
            data.tilerUtilization = max(data.tilerUtilization, ratio(stats["Tiler Utilization %"]))
            data.inUseMemoryBytes = max(data.inUseMemoryBytes, (stats["In use system memory"] as? NSNumber)?.nonNegativeUInt64 ?? 0)
            data.allocatedMemoryBytes = max(data.allocatedMemoryBytes, (stats["Alloc system memory"] as? NSNumber)?.nonNegativeUInt64 ?? 0)
        }

        history.append(data.deviceUtilization)
        data.history = history
        return data
    }

    private func ratio(_ value: Any?) -> Double {
        guard let number = value as? NSNumber else { return 0 }
        return min(max(number.doubleValue / 100, 0), 1)
    }
}
