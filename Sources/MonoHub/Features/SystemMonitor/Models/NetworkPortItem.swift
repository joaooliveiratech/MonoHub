import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated struct NetworkPortItem: Identifiable, Sendable, Hashable {
    let id: String
    let pid: pid_t
    let processName: String
    let processPath: String?
    let user: String
    let port: Int
    let networkProtocol: String
    let ipVersion: String
    let state: String
    let localAddress: String
    let remoteAddress: String?
    let isWebPort: Bool

    var downloadBytesPerSec: UInt64 = 0
    var uploadBytesPerSec: UInt64 = 0
    var totalBytesDownloaded: UInt64 = 0
    var totalBytesUploaded: UInt64 = 0

    var isListening: Bool {
        state == "LISTEN"
    }

    var hasTraffic: Bool {
        downloadBytesPerSec > 0 || uploadBytesPerSec > 0
    }

    var totalSpeed: UInt64 {
        downloadBytesPerSec &+ uploadBytesPerSec
    }

    var webURL: URL? {
        guard isListening, isWebPort else { return nil }
        let cleanHost = (localAddress.components(separatedBy: ":").first ?? localAddress)
        let host = cleanHost == "*" || cleanHost == "0.0.0.0" || cleanHost == "::" ? "127.0.0.1" : cleanHost
        let scheme = port == 443 || port == 8443 ? "https" : "http"
        return URL(string: "\(scheme)://\(host):\(port)")
    }

    func applyingBandwidth(_ stats: ProcessBandwidth?) -> NetworkPortItem {
        guard let stats else { return self }
        return NetworkPortItem(
            id: id,
            pid: pid,
            processName: processName,
            processPath: processPath,
            user: user,
            port: port,
            networkProtocol: networkProtocol,
            ipVersion: ipVersion,
            state: state,
            localAddress: localAddress,
            remoteAddress: remoteAddress,
            isWebPort: isWebPort,
            downloadBytesPerSec: stats.downloadBytesPerSec,
            uploadBytesPerSec: stats.uploadBytesPerSec,
            totalBytesDownloaded: stats.totalDownloaded,
            totalBytesUploaded: stats.totalUploaded
        )
    }

    func icon() -> NSImage {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        if let processPath, FileManager.default.fileExists(atPath: processPath) {
            return NSWorkspace.shared.icon(forFile: processPath)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
