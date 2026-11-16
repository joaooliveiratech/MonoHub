import Darwin
import Foundation

nonisolated enum DeletionMode: Sendable, Equatable {
    case moveToTrash
    case deletePermanently

    var confirmationNote: String {
        switch self {
        case .moveToTrash:
            return localized("Items will be moved to the Trash and can be restored.")
        case .deletePermanently:
            return localized("Items will be permanently deleted and cannot be restored.")
        }
    }
}

nonisolated struct CleanupOptions: Sendable, Equatable {
    var deletionMode: DeletionMode
    var logsOperations: Bool

    init(deletionMode: DeletionMode, logsOperations: Bool) {
        self.deletionMode = deletionMode
        self.logsOperations = logsOperations
    }

    @MainActor static var current: CleanupOptions {
        let prefs = CleanupPreferences.shared
        return CleanupOptions(
            deletionMode: prefs.moveToTrashInsteadOfDelete ? .moveToTrash : .deletePermanently,
            logsOperations: prefs.enableLocalLogging
        )
    }

    @MainActor static var requiresConfirmation: Bool {
        let prefs = CleanupPreferences.shared
        return prefs.confirmBeforeDeleting || !prefs.moveToTrashInsteadOfDelete
    }

    func log(action: String, result: ExecutionResult, details: String) {
        guard logsOperations else { return }
        OperationLogger.shared.log(
            action: action,
            itemsCleaned: result.itemsCount,
            bytesFreed: result.bytesFreed,
            details: details
        )
    }
}

nonisolated protocol CleanupListItem: Identifiable, Sendable where ID == UUID {
    var itemURL: URL { get }
    var itemName: String { get }
    var itemSize: Int64 { get }
}

nonisolated struct ScanProgress: Sendable, Equatable {
    var message: String
    var completed: Int
    var total: Int?

    init(message: String, completed: Int = 0, total: Int? = nil) {
        self.message = message
        self.completed = completed
        self.total = total
    }

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

nonisolated final class ProgressReporter: @unchecked Sendable {
    private let interval: UInt64
    private let handler: @Sendable (ScanProgress) -> Void
    private let lock = NSLock()
    private var lastEmission: UInt64 = 0

    init(minimumInterval: Duration = .milliseconds(250), handler: @escaping @Sendable (ScanProgress) -> Void) {
        let components = minimumInterval.components
        self.interval = UInt64(components.seconds) * 1_000_000_000 + UInt64(components.attoseconds / 1_000_000_000)
        self.handler = handler
    }

    static let silent = ProgressReporter { _ in }

    func report(_ progress: @autoclosure () -> ScanProgress, force: Bool = false) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let shouldEmit = force || now &- lastEmission >= interval
        if shouldEmit {
            lastEmission = now
        }
        lock.unlock()
        if shouldEmit {
            handler(progress())
        }
    }
}

nonisolated enum PathSafety {
    private static let bundleIdentifierCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
    )

    static func isSafePathComponent(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        guard name != ".", name != "..", !name.hasPrefix(".") else { return false }
        return !name.contains("/") && !name.contains("\0") && !name.contains(":")
    }

    static func isValidBundleIdentifier(_ identifier: String) -> Bool {
        guard identifier.count >= 3, identifier.count <= 255 else { return false }
        guard identifier.contains("."), !identifier.hasPrefix("."), !identifier.hasSuffix(".") else { return false }
        guard !identifier.contains("..") else { return false }
        return identifier.unicodeScalars.allSatisfy { bundleIdentifierCharacters.contains($0) }
    }

    static func child(named name: String, of directory: URL) -> URL? {
        guard isSafePathComponent(name) else { return nil }
        let parent = directory.standardizedFileURL
        let candidate = parent.appendingPathComponent(name).standardizedFileURL
        guard candidate.deletingLastPathComponent().path == parent.path else { return nil }
        return candidate
    }

    static func isStrictDescendant(_ url: URL, of root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.count > prefix.count && path.hasPrefix(prefix)
    }

    static func isSameOrDescendant(_ url: URL, of root: URL) -> Bool {
        url.standardizedFileURL.path == root.standardizedFileURL.path || isStrictDescendant(url, of: root)
    }

    static func matchesBundleIdentifier(_ name: String, bundleIdentifier: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerIdentifier = bundleIdentifier.lowercased()
        return lowerName == lowerIdentifier || lowerName.hasPrefix(lowerIdentifier + ".")
    }

    static func groupContainerMatches(_ name: String, bundleIdentifier: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerIdentifier = bundleIdentifier.lowercased()
        return lowerName == lowerIdentifier
            || lowerName.hasPrefix(lowerIdentifier + ".")
            || lowerName.hasSuffix("." + lowerIdentifier)
            || lowerName.contains("." + lowerIdentifier + ".")
    }

    static func nameMatches(_ name: String, prefix: String, separators: Set<Character>) -> Bool {
        let lowerName = name.lowercased()
        let lowerPrefix = prefix.lowercased()
        guard lowerName.hasPrefix(lowerPrefix) else { return false }
        guard lowerName.count > lowerPrefix.count else { return true }
        let next = lowerName[lowerName.index(lowerName.startIndex, offsetBy: lowerPrefix.count)]
        return separators.contains(next)
    }

    static func removingNestedDuplicates(_ urls: [URL]) -> [URL] {
        let standardized = Array(Set(urls.map(\.standardizedFileURL))).sorted { $0.path.count < $1.path.count }
        var kept: [URL] = []
        for url in standardized where !kept.contains(where: { isSameOrDescendant(url, of: $0) }) {
            kept.append(url)
        }
        return kept
    }

    static func isAccessibleAndDeletable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let immutableMask = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE) | UInt32(SF_RESTRICTED)
        if (st.st_flags & immutableMask) != 0 {
            return false
        }
        let parentPath = url.standardizedFileURL.deletingLastPathComponent().path
        guard access(parentPath, W_OK | X_OK) == 0 else { return false }

        if (st.st_mode & S_IFMT) == S_IFDIR {
            guard access(path, R_OK | W_OK | X_OK) == 0 else { return false }
            guard let dir = opendir(path) else { return false }
            closedir(dir)
        }
        return true
    }
}

nonisolated enum DirectorySize {
    static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    static var defaultConcurrency: Int {
        min(8, max(4, ProcessInfo.processInfo.activeProcessorCount))
    }

    static func hasModification(after cutoff: Date, in directory: URL) -> Bool {
        let cutoffTimestamp = cutoff.timeIntervalSince1970
        let path = directory.standardizedFileURL.path
        let cPath = strdup(path)
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return false
        }
        defer { fts_close(fts) }

        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 2047 == 0 && Task.isCancelled {
                return true
            }
            guard entry.pointee.fts_level > 0 else { continue }
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if let statp = entry.pointee.fts_statp {
                    let mtime = Double(statp.pointee.st_mtimespec.tv_sec)
                        + Double(statp.pointee.st_mtimespec.tv_nsec) * 1e-9
                    if mtime >= cutoffTimestamp {
                        return true
                    }
                }
            default:
                continue
            }
        }
        return false
    }

    static func allocatedSize(of url: URL) -> Int64 {
        let path = url.standardizedFileURL.path
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        let fileType = st.st_mode & S_IFMT
        if fileType == S_IFLNK {
            return 0
        }
        if fileType != S_IFDIR {
            return st.st_blocks > 0 ? Int64(st.st_blocks) * 512 : Int64(st.st_size)
        }

        let cPath = strdup(path)
        defer { free(cPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return 0
        }
        defer { fts_close(fts) }

        var total: Int64 = 0
        var visited = 0
        var seenHardlinkInodes = Set<UInt64>()
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 2047 == 0 && Task.isCancelled {
                return total
            }
            guard Int32(entry.pointee.fts_info) == FTS_F,
                  let statp = entry.pointee.fts_statp else { continue }
            let itemStat = statp.pointee
            if itemStat.st_nlink > 1 {
                guard seenHardlinkInodes.insert(itemStat.st_ino).inserted else { continue }
            }
            total += itemStat.st_blocks > 0 ? Int64(itemStat.st_blocks) * 512 : Int64(itemStat.st_size)
        }
        return total
    }

    static func allocatedSizes(
        of urls: [URL],
        maxConcurrent: Int = DirectorySize.defaultConcurrency,
        onEach: @escaping @Sendable (Int) -> Void = { _ in }
    ) async -> [URL: Int64] {
        guard !urls.isEmpty else { return [:] }
        return await withTaskGroup(of: (URL, Int64).self) { group in
            var results: [URL: Int64] = [:]
            results.reserveCapacity(urls.count)
            var iterator = urls.makeIterator()
            var running = 0

            func enqueueNext() -> Bool {
                guard !Task.isCancelled, let next = iterator.next() else { return false }
                group.addTask { (next, allocatedSize(of: next)) }
                return true
            }

            while running < maxConcurrent, enqueueNext() {
                running += 1
            }
            while let (url, size) = await group.next() {
                results[url] = size
                onEach(results.count)
                if !enqueueNext() {
                    running -= 1
                }
            }
            return results
        }
    }
}

nonisolated struct RemovalTarget: Sendable, Hashable {
    let url: URL
    let displayName: String
    let size: Int64
    let allowedRoots: [URL]

    init(url: URL, displayName: String? = nil, size: Int64, allowedRoots: [URL]) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.size = size
        self.allowedRoots = allowedRoots
    }
}

nonisolated enum RemovalOutcome: Sendable, Equatable {
    case removed
    case missing
    case refused(String)
    case failed(String)
}

nonisolated struct RemovalReport: Sendable {
    var removedURLs: [URL] = []
    var bytesFreed: Int64 = 0
    var errors: [String] = []

    var result: ExecutionResult {
        ExecutionResult(success: errors.isEmpty, itemsCount: removedURLs.count, bytesFreed: bytesFreed, errors: errors)
    }
}

nonisolated enum SafeFileRemover {
    static var userTemporaryRoots: [String] {
        [
            FileManager.default.temporaryDirectory.path,
            FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        ]
    }

    static func validate(_ url: URL, allowedRoots: [URL], whitelist: WhitelistManager = .shared) -> String? {
        guard url.isFileURL else { return localized("Invalid path") }
        guard !url.pathComponents.contains("..") else { return localized("Relative paths not allowed") }
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix("/") else { return localized("Invalid path") }
        guard !allowedRoots.isEmpty,
              allowedRoots.contains(where: { PathSafety.isStrictDescendant(standardized, of: $0) }) else {
            return localized("Outside permitted folders for this cleanup")
        }

        let resolvedParent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        let parentIsInsideRoot = allowedRoots.contains { root in
            PathSafety.isSameOrDescendant(resolvedParent, of: root.resolvingSymlinksInPath())
        }
        guard parentIsInsideRoot else { return localized("Path crosses a symbolic link outside the permitted folder") }

        if whitelist.isUserWhitelisted(path: standardized.path) {
            return localized("Protected by exclusion list")
        }
        if whitelist.isSystemProtected(path: standardized.path, exemptingDescendantsOf: userTemporaryRoots) {
            return localized("Protected system path")
        }
        return nil
    }

    static func remove(_ target: RemovalTarget, mode: DeletionMode, whitelist: WhitelistManager = .shared) -> RemovalOutcome {
        if let reason = validate(target.url, allowedRoots: target.allowedRoots, whitelist: whitelist) {
            return .refused(reason)
        }
        let url = target.url.standardizedFileURL
        let fileManager = FileManager.default
        guard (try? fileManager.attributesOfItem(atPath: url.path)) != nil else {
            return .missing
        }
        do {
            switch mode {
            case .moveToTrash:
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            case .deletePermanently:
                try fileManager.removeItem(at: url)
            }
            return .removed
        } catch {
            return .failed(failureMessage(for: error, mode: mode))
        }
    }

    static func failureMessage(for error: any Error, mode: DeletionMode) -> String {
        let nsError = error as NSError
        let isPermission = nsError.code == NSFileWriteNoPermissionError
            || nsError.code == NSFileReadNoPermissionError
            || (nsError.underlyingErrors.first as NSError?).map { $0.code == Int(EPERM) || $0.code == Int(EACCES) } == true
        if isPermission {
            return localized("Permission denied by macOS. Grant Full Disk Access or quit the app using the item.")
        }
        if mode == .moveToTrash {
            return localized("Could not move to Trash (%@). Nothing was deleted.", nsError.localizedDescription)
        }
        return nsError.localizedDescription
    }

    static func removeAll(_ targets: [RemovalTarget], mode: DeletionMode, whitelist: WhitelistManager = .shared) -> RemovalReport {
        let keptURLs = Set(PathSafety.removingNestedDuplicates(targets.map(\.url)))
        var seen = Set<URL>()
        var report = RemovalReport()
        for target in targets {
            let url = target.url.standardizedFileURL
            guard keptURLs.contains(url), seen.insert(url).inserted else { continue }
            switch remove(target, mode: mode, whitelist: whitelist) {
            case .removed:
                report.removedURLs.append(url)
                report.bytesFreed += target.size
            case .missing:
                continue
            case .refused(let reason), .failed(let reason):
                report.errors.append("\(target.displayName): \(reason)")
            }
        }
        return report
    }
}

nonisolated struct ProcessOutput: Sendable {
    let status: Int32
    let output: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }
}

nonisolated enum ProcessRunner {
    @concurrent
    static func run(_ executablePath: String, _ arguments: [String], timeout: Duration = .seconds(60)) async -> ProcessOutput? {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let exit = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let reader = Task.detached(priority: .utility) {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }
        let watchdog = Task.detached(priority: .utility) {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, process.isRunning else { return false }
            process.terminate()
            return true
        }

        var status: Int32 = -1
        for await code in exit {
            status = code
        }
        watchdog.cancel()
        let timedOut = await watchdog.value
        let data = await reader.value
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ProcessOutput(status: status, output: text, timedOut: timedOut)
    }
}

nonisolated enum CleanupExecutor {
    @concurrent
    static func execute(
        _ targets: [RemovalTarget],
        options: CleanupOptions,
        action: String,
        details: @escaping @Sendable (RemovalReport) -> String
    ) async -> RemovalReport {
        let report = SafeFileRemover.removeAll(targets, mode: options.deletionMode)
        if !report.removedURLs.isEmpty || !report.errors.isEmpty {
            options.log(action: action, result: report.result, details: details(report))
        }
        return report
    }
}

extension WhitelistManager {
    nonisolated func blocksRemoval(of path: String) -> Bool {
        isUserWhitelisted(path: path)
            || isSystemProtected(path: path, exemptingDescendantsOf: SafeFileRemover.userTemporaryRoots)
    }
}
