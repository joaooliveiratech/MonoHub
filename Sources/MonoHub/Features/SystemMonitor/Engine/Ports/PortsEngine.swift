import Darwin
import Foundation
import AppKit

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

            let procPath = getProcessPath(pid: pid)
            let friendlyName = getProcessName(pid: pid, fallback: rawCommand)
            let isWeb = isCommonWebPort(port)

            let id = "\(pid)-\(proto)-\(port)-\(localAddress)-\(state)"
            let item = NetworkPortItem(
                id: id,
                pid: pid,
                processName: friendlyName,
                processPath: procPath,
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

    private static func getProcessName(pid: pid_t, fallback: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        if let path = getProcessPath(pid: pid) {
            let lastComponent = (path as NSString).lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }
        return fallback
    }

    private static func isCommonWebPort(_ port: Int) -> Bool {
        let commonWeb = Set([80, 443, 3000, 3001, 4000, 4200, 5000, 5001, 5173, 5174, 8000, 8080, 8081, 8443, 8888, 9000, 9090])
        return commonWeb.contains(port) || (port >= 3000 && port <= 9999)
    }

    func terminateProcess(pid: pid_t, force: Bool = false) async -> Bool {
        let signal = force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)
        if result != 0 {
            return false
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        return kill(pid, 0) != 0
    }
}
