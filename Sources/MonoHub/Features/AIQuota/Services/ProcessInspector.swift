import Darwin
import Foundation

nonisolated enum ProcessInspector {
    struct Match: Sendable {
        let pid: pid_t
        let executableName: String
        let arguments: [String]

        var isCommandLineClient: Bool {
            executableName == "agy" || executableName == "antigravity"
        }

        func value(forFlag flag: String) -> String? {
            for (index, argument) in arguments.enumerated() {
                if argument == flag, index + 1 < arguments.count {
                    return arguments[index + 1]
                }
                if argument.hasPrefix("\(flag)=") {
                    return String(argument.dropFirst(flag.count + 1))
                }
            }
            return nil
        }
    }

    struct CommandLine: Sendable {
        let arguments: [String]
        let environment: [String]

        func environmentValue(_ name: String) -> String? {
            let prefix = "\(name)="
            return environment.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
    }

    static func findLanguageServers() -> [Match] {
        currentPIDs().compactMap(languageServerMatch(pid:))
    }

    static func languageServerMatch(pid: pid_t) -> Match? {
        guard let path = executablePath(of: pid) else { return nil }
        let binaryName = (path as NSString).lastPathComponent.lowercased()
        let isClient = binaryName == "agy" || binaryName == "antigravity"
        guard isClient || path.contains("Antigravity") || path.contains("language_server"),
              let commandLine = commandLine(of: pid) else { return nil }

        let match = Match(pid: pid, executableName: binaryName, arguments: commandLine.arguments)
        if isClient || binaryName.hasPrefix("language_server") {
            return match
        }
        return match.value(forFlag: "--csrf_token") != nil ? match : nil
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func childPIDs(of parent: pid_t) -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), nil, 0)
        guard byteCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.stride + 8)
        let written = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), buffer.baseAddress, Int32(buffer.count))
        }
        guard written > 0 else { return [] }
        return pids.prefix(Int(written) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    static func listeningTCPPorts(of pid: pid_t) -> [Int] {
        let byteCount = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(byteCount) / stride)
        let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, byteCount)
        guard written > 0 else { return [] }

        var ports: Set<Int> = []
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)

        for descriptor in descriptors.prefix(Int(written) / stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                  info.psi.soi_kind == SOCKINFO_TCP else { continue }

            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }

            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
            if (1024...65535).contains(port) {
                ports.insert(port)
            }
        }
        return Array(ports)
    }

    static func commandLine(of pid: pid_t) -> CommandLine? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }

        let argumentCount = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argumentCount > 0 else { return nil }

        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }

        var strings: [String] = []
        while index < size {
            while index < size, buffer[index] == 0 { index += 1 }
            guard index < size else { break }

            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            strings.append(String(decoding: buffer[start..<index], as: UTF8.self))
        }

        let arguments = Array(strings.prefix(argumentCount))
        guard !arguments.isEmpty else { return nil }
        return CommandLine(arguments: arguments, environment: Array(strings.dropFirst(argumentCount)))
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func currentPIDs() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.stride)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, byteCount)
        guard written > 0 else { return [] }

        return pids.prefix(Int(written) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }.reversed()
    }
}
