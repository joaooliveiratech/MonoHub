import Foundation

nonisolated struct GPUData: Sendable, Equatable {
    var deviceUtilization: Double = 0
    var rendererUtilization: Double = 0
    var tilerUtilization: Double = 0
    var inUseMemoryBytes: UInt64 = 0
    var allocatedMemoryBytes: UInt64 = 0
    var history = RollingHistory()
    var topProcesses: [ProcessItem] = []
}
