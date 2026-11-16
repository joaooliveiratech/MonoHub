import Foundation

nonisolated struct LoadAverage: Sendable, Equatable {
    var one: Double = 0
    var five: Double = 0
    var fifteen: Double = 0
}

nonisolated struct CPUData: Sendable, Equatable {
    var totalUsage: Double = 0
    var userUsage: Double = 0
    var systemUsage: Double = 0
    var coreUsages: [Double] = []
    var loadAverage = LoadAverage()
    var history = RollingHistory()
    var topProcesses: [ProcessItem] = []
    var processCount: Int?
    var threadCount: Int?

    var idleUsage: Double {
        max(0, 1 - totalUsage)
    }

    func averageUsage(for cluster: CoreCluster, clusters: [CoreCluster]) -> Double {
        var total = 0.0
        var count = 0
        for (usage, kind) in zip(coreUsages, clusters) where kind == cluster {
            total += usage
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }
}
