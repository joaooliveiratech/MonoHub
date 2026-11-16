import Foundation

nonisolated struct NetworkData: Sendable, Equatable {
    var downloadBytesPerSec: UInt64 = 0
    var uploadBytesPerSec: UInt64 = 0
    var sessionInBytes: UInt64 = 0
    var sessionOutBytes: UInt64 = 0
    var interfaceName: String?
    var interfaceDisplayName: String?
    var localIPv4: String?
    var localIPv6: String?
    var downloadHistory = RollingHistory()
    var uploadHistory = RollingHistory()
    var peakDownloadBytesPerSec: UInt64 = 0
    var peakUploadBytesPerSec: UInt64 = 0

    var isConnected: Bool {
        localIPv4 != nil || localIPv6 != nil
    }
}
