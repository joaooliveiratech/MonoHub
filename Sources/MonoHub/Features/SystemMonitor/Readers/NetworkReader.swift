import Darwin
import Foundation
import SystemConfiguration

nonisolated final class NetworkReader {
    private var previousCounters: [UInt16: InterfaceCounters] = [:]
    private var currentCounters: [UInt16: InterfaceCounters] = [:]
    private var previousTimestamp: UInt64 = 0
    private var sessionIn: UInt64 = 0
    private var sessionOut: UInt64 = 0
    private var peakIn: UInt64 = 0
    private var peakOut: UInt64 = 0
    private var downloadHistory = RollingHistory()
    private var uploadHistory = RollingHistory()
    private var interfaceNames: [UInt16: String] = [:]
    private var displayNames: [String: String] = [:]
    private var addresses = InterfaceAddresses()
    private var lastAddressRefresh: UInt64 = 0
    private var routeBuffer: [UInt8] = []

    struct InterfaceCounters: Equatable {
        var received: UInt64
        var sent: UInt64
    }

    private struct InterfaceAddresses {
        var primary: String?
        var ipv4: String?
        var ipv6: String?
    }

    func read(detailed: Bool, includeAddresses: Bool = true) -> NetworkData {
        let now = monotonicNanoseconds()
        if detailed || includeAddresses {
            if lastAddressRefresh == 0 || now &- lastAddressRefresh > (detailed ? 5_000_000_000 : 30_000_000_000) {
                addresses = readAddresses()
                lastAddressRefresh = now
            }
        }

        var data = NetworkData()
        if readCounters(into: &currentCounters) {
            if previousTimestamp > 0, now > previousTimestamp {
                let seconds = Double(now - previousTimestamp) / 1_000_000_000
                let delta = Self.delta(from: previousCounters, to: currentCounters)
                data.downloadBytesPerSec = UInt64(Double(delta.received) / seconds)
                data.uploadBytesPerSec = UInt64(Double(delta.sent) / seconds)
                sessionIn &+= delta.received
                sessionOut &+= delta.sent
                peakIn = max(peakIn, data.downloadBytesPerSec)
                peakOut = max(peakOut, data.uploadBytesPerSec)
            }
            swap(&previousCounters, &currentCounters)
            previousTimestamp = now
        }

        downloadHistory.append(Double(data.downloadBytesPerSec))
        uploadHistory.append(Double(data.uploadBytesPerSec))

        data.sessionInBytes = sessionIn
        data.sessionOutBytes = sessionOut
        data.peakDownloadBytesPerSec = peakIn
        data.peakUploadBytesPerSec = peakOut
        data.downloadHistory = downloadHistory
        data.uploadHistory = uploadHistory
        data.interfaceName = addresses.primary
        data.localIPv4 = addresses.ipv4
        data.localIPv6 = addresses.ipv6
        if detailed, let primary = addresses.primary {
            data.interfaceDisplayName = displayName(for: primary)
        }
        return data
    }

    static func delta(from previous: [UInt16: InterfaceCounters], to current: [UInt16: InterfaceCounters]) -> InterfaceCounters {
        var total = InterfaceCounters(received: 0, sent: 0)
        for (index, counters) in current {
            guard let before = previous[index] else { continue }
            if counters.received >= before.received { total.received &+= counters.received - before.received }
            if counters.sent >= before.sent { total.sent &+= counters.sent - before.sent }
        }
        return total
    }

    private func readCounters(into counters: inout [UInt16: InterfaceCounters]) -> Bool {
        var mib: (Int32, Int32, Int32, Int32, Int32, Int32) = (CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0)
        // Reuse the previous buffer and only fall back to the sizing round trip when the
        // interface table outgrew it, so the steady state costs a single sysctl per tick.
        var length = routeBuffer.count
        var status: Int32 = -1
        if length > 0 {
            status = routeBuffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &mib) { pointer in
                    pointer.withMemoryRebound(to: Int32.self, capacity: 6) { sysctl($0, 6, raw.baseAddress, &length, nil, 0) }
                }
            }
        }
        if status != 0 {
            length = 0
            let sized = withUnsafeMutablePointer(to: &mib) { pointer in
                pointer.withMemoryRebound(to: Int32.self, capacity: 6) { sysctl($0, 6, nil, &length, nil, 0) }
            }
            guard sized == 0, length > 0 else { return false }
            routeBuffer = [UInt8](repeating: 0, count: length + 4_096)
            length = routeBuffer.count
            status = routeBuffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &mib) { pointer in
                    pointer.withMemoryRebound(to: Int32.self, capacity: 6) { sysctl($0, 6, raw.baseAddress, &length, nil, 0) }
                }
            }
            guard status == 0 else { return false }
        }

        counters.removeAll(keepingCapacity: true)
        return routeBuffer.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = info.ifm_flags
                    if flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, isPhysical(index: info.ifm_index) {
                        counters[info.ifm_index] = InterfaceCounters(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
            return true
        }
    }

    private func isPhysical(index: UInt16) -> Bool {
        let name: String
        if let cached = interfaceNames[index] {
            name = cached
        } else {
            var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
            guard if_indextoname(UInt32(index), &buffer) != nil else { return false }
            name = String(nullTerminated: buffer)
            interfaceNames[index] = name
        }
        return name.hasPrefix("en")
    }

    private func readAddresses() -> InterfaceAddresses {
        var result = InterfaceAddresses()
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(nullTerminated: host)

            if family == AF_INET {
                if result.ipv4 == nil || name == "en0" {
                    result.ipv4 = ip
                    result.primary = name
                }
            } else if !ip.hasPrefix("fe80"), result.ipv6 == nil {
                result.ipv6 = ip.split(separator: "%").first.map(String.init)
                if result.primary == nil { result.primary = name }
            }
        }
        return result
    }

    private func displayName(for bsdName: String) -> String {
        if let cached = displayNames[bsdName] {
            return cached
        }
        var name = bsdName
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
                if let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                    name = localized
                }
                break
            }
        }
        displayNames[bsdName] = name
        return name
    }
}
