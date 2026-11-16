import Foundation

nonisolated struct OperationRecord: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let action: String
    let itemsCleaned: Int
    let bytesFreed: Int64
    let details: String

    init(id: UUID = UUID(), date: Date = Date(), action: String, itemsCleaned: Int, bytesFreed: Int64, details: String) {
        self.id = id
        self.date = date
        self.action = action
        self.itemsCleaned = itemsCleaned
        self.bytesFreed = bytesFreed
        self.details = details
    }
}

nonisolated final class OperationLogger: @unchecked Sendable {
    static let shared = OperationLogger(
        directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MonoHub", isDirectory: true)
    )

    static let maximumFileBytes: UInt64 = 1_048_576
    static let maximumFetchedRecords = 1_000

    let logDirectory: URL
    let logFileURL: URL
    private let rotatedFileURL: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.logDirectory = directory
        self.logFileURL = directory.appendingPathComponent("operations.log")
        self.rotatedFileURL = directory.appendingPathComponent("operations.log.1")
    }

    static func sanitize(_ field: String) -> String {
        field.replacing(/[\t\r\n]+/, with: " ")
    }

    static func encode(date: Date, action: String, itemsCleaned: Int, bytesFreed: Int64, details: String) -> String {
        let stamp = date.formatted(.iso8601)
        return "\(stamp)\t\(sanitize(action))\t\(itemsCleaned)\t\(bytesFreed)\t\(sanitize(details))\n"
    }

    static func decode(line: Substring) -> OperationRecord? {
        let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5 else { return nil }
        let date = (try? Date(String(parts[0]), strategy: .iso8601)) ?? .distantPast
        return OperationRecord(
            date: date,
            action: String(parts[1]),
            itemsCleaned: Int(parts[2]) ?? 0,
            bytesFreed: Int64(parts[3]) ?? 0,
            details: String(parts[4])
        )
    }

    func log(action: String, itemsCleaned: Int, bytesFreed: Int64, details: String) {
        let line = Self.encode(date: Date(), action: action, itemsCleaned: itemsCleaned, bytesFreed: bytesFreed, details: details)
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            rotateIfNeeded(fileManager: fileManager)
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rotateIfNeeded(fileManager: FileManager) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size >= Self.maximumFileBytes else { return }
        try? fileManager.removeItem(at: rotatedFileURL)
        try? fileManager.moveItem(at: logFileURL, to: rotatedFileURL)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotatedFileURL.path)
    }

    func fetchRecords(limit: Int = OperationLogger.maximumFetchedRecords) -> [OperationRecord] {
        lock.lock()
        let content = try? String(contentsOf: logFileURL, encoding: .utf8)
        lock.unlock()

        guard let content else { return [] }
        let records = content.split(separator: "\n").suffix(limit).compactMap(Self.decode(line:))
        return records.reversed()
    }

    func clearLogs() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: logFileURL)
        try? FileManager.default.removeItem(at: rotatedFileURL)
    }
}
