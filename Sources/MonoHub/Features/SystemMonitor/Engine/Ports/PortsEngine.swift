import Darwin
import Foundation

nonisolated final class PortsEngine: Sendable {
    static let shared = PortsEngine()

    private init() {}

    func scanPorts() async -> [NetworkPortItem] {
        let items = await Task.detached(priority: .userInitiated) {
            Self.runLsof()
        }.value
        return updateBandwidth(for: items)
    }

    func updateBandwidth(for items: [NetworkPortItem]) -> [NetworkPortItem] {
        let snapshot = ProcessBandwidthEngine.shared.latestSnapshot()
        return items.map { item in
            item.applyingBandwidth(snapshot.processes[item.pid])
        }
    }

    func sampleBandwidth() async -> BandwidthSnapshot {
        await ProcessBandwidthEngine.shared.sample()
    }

    func latestBandwidthSnapshot() -> BandwidthSnapshot {
        ProcessBandwidthEngine.shared.latestSnapshot()
    }

    private static func runLsof() -> [NetworkPortItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-iUDP"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return parseLsofOutput(output)
        } catch {
            return []
        }
    }

    static func parseLsofOutput(_ output: String) -> [NetworkPortItem] {
        var items: [NetworkPortItem] = []
        var identityCache: [pid_t: (name: String, path: String?)] = [:]
        var idCounts: [String: Int] = [:]
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("COMMAND") else { continue }

            let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 9 else { continue }

            let rawCommand = tokens[0]
            guard let pid = pid_t(tokens[1]) else { continue }
            let user = tokens[2]
            let ipVersion = tokens[4]
            let proto = tokens[7].uppercased()

            let nameField = tokens[8...].joined(separator: " ")

            var state = proto == "UDP" ? "UDP" : "UNKNOWN"
            var localAddress = ""
            var remoteAddress: String?
            var portNumber: Int?

            if nameField.contains("(LISTEN)") {
                state = "LISTEN"
                let clean = nameField.replacingOccurrences(of: "(LISTEN)", with: "").trimmingCharacters(in: .whitespaces)
                localAddress = extractHost(from: clean)
                portNumber = extractPort(from: clean)
            } else if nameField.contains("(ESTABLISHED)") {
                state = "ESTABLISHED"
                let clean = nameField.replacingOccurrences(of: "(ESTABLISHED)", with: "").trimmingCharacters(in: .whitespaces)
                let parts = clean.components(separatedBy: "->")
                localAddress = parts.first ?? clean
                remoteAddress = parts.count > 1 ? parts[1] : nil
                portNumber = extractPort(from: localAddress)
            } else if proto == "UDP" {
                state = "UDP"
                localAddress = extractHost(from: nameField)
                portNumber = extractPort(from: nameField)
            } else {
                localAddress = extractHost(from: nameField)
                portNumber = extractPort(from: nameField)
            }

            guard let port = portNumber, port > 0 else { continue }

            let identity: (name: String, path: String?)
            if let cached = identityCache[pid] {
                identity = cached
            } else {
                let path = getProcessPath(pid: pid)
                let name = resolveProcessName(path: path, fallback: rawCommand)
                identity = (name, path)
                identityCache[pid] = identity
            }
            let isWeb = isCommonWebPort(port)

            let baseID = "\(pid)-\(proto)-\(port)-\(localAddress)-\(remoteAddress ?? "")-\(state)"
            let occurrence = idCounts[baseID, default: 0]
            idCounts[baseID] = occurrence + 1
            let id = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"

            let item = NetworkPortItem(
                id: id,
                pid: pid,
                processName: identity.name,
                processPath: identity.path,
                user: user,
                port: port,
                networkProtocol: proto,
                ipVersion: ipVersion,
                state: state,
                localAddress: localAddress,
                remoteAddress: remoteAddress,
                isWebPort: isWeb
            )
            items.append(item)
        }

        return items.sorted {
            if $0.isListening != $1.isListening {
                return $0.isListening && !$1.isListening
            }
            if $0.port != $1.port {
                return $0.port < $1.port
            }
            return $0.processName < $1.processName
        }
    }

    private static func extractPort(from address: String) -> Int? {
        guard let colonIndex = address.lastIndex(of: ":") else { return nil }
        let portPart = address[address.index(after: colonIndex)...]
        return Int(portPart)
    }

    private static func extractHost(from address: String) -> String {
        guard let colonIndex = address.lastIndex(of: ":") else { return address }
        return String(address[..<colonIndex])
    }

    private static func getProcessPath(pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let len = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_pidpath(pid, ptr.baseAddress, 4096)
        }
        if len > 0 {
            return String(decoding: buffer.prefix(Int(len)), as: UTF8.self)
        }
        return nil
    }

    private static func resolveProcessName(path: String?, fallback: String) -> String {
        guard let path, !path.isEmpty else { return fallback }
        var name = (path as NSString).lastPathComponent
        if let range = path.range(of: ".app/", options: .caseInsensitive),
           name.isEmpty || name.caseInsensitiveCompare("Electron") == .orderedSame || name.caseInsensitiveCompare("MacOS") == .orderedSame {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let bundleName = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
            if !bundleName.isEmpty {
                name = bundleName
            }
        }
        return name.isEmpty ? fallback : name
    }

    private static let commonWebPorts: Set<Int> = [
        80, 443, 3000, 3001, 4000, 4200, 5000, 5001, 5173, 5174, 8000, 8080, 8081, 8443, 8888, 9000, 9090
    ]

    private static func isCommonWebPort(_ port: Int) -> Bool {
        commonWebPorts.contains(port) || (3000...9999).contains(port)
    }

    func terminateProcess(pid: pid_t, force: Bool = false) async -> Bool {
        let signal = force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)
        if result != 0 {
            return false
        }

        try? await Task.sleep(for: .milliseconds(200))
        return kill(pid, 0) != 0
    }
}
