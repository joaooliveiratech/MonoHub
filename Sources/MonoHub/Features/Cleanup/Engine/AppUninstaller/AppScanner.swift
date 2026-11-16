import AppKit
import Darwin
import Foundation

nonisolated struct RunningAppSnapshot: Sendable {
    let bundleIdentifier: String
    let bundlePath: String
    let localizedName: String

    init(bundleIdentifier: String, bundlePath: String, localizedName: String = "") {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.localizedName = localizedName
    }
}

nonisolated enum AppScanner {
    private struct CachedBundleSize: Sendable {
        let modificationTime: Int
        let size: Int64
    }

    private static let sizeCacheLock = NSLock()
    nonisolated(unsafe) private static var bundleSizeCache: [String: CachedBundleSize] = [:]

    private static func bundleModificationTime(_ url: URL) -> Int {
        var st = stat()
        guard lstat(url.standardizedFileURL.path, &st) == 0 else { return 0 }
        return st.st_mtimespec.tv_sec
    }

    static func cachedSize(for bundleURL: URL) -> Int64? {
        let path = bundleURL.standardizedFileURL.path
        let mtime = bundleModificationTime(bundleURL)
        sizeCacheLock.lock()
        defer { sizeCacheLock.unlock() }
        guard let entry = bundleSizeCache[path], entry.modificationTime == mtime else {
            return nil
        }
        return entry.size
    }

    private static func storeCachedSize(_ size: Int64, for bundleURL: URL) {
        let path = bundleURL.standardizedFileURL.path
        let mtime = bundleModificationTime(bundleURL)
        sizeCacheLock.lock()
        bundleSizeCache[path] = CachedBundleSize(modificationTime: mtime, size: size)
        sizeCacheLock.unlock()
    }

    static func quickInstalledAppsCount() -> Int {
        let fileManager = FileManager.default
        var count = 0
        for directory in applicationDirectories {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) {
                count += contents.lazy.filter { $0.hasSuffix(".app") }.count
            }
        }
        return count
    }

    static var applicationDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true)
        ]
    }

    @MainActor
    static func runningApplications() -> [RunningAppSnapshot] {
        NSWorkspace.shared.runningApplications.map {
            RunningAppSnapshot(
                bundleIdentifier: $0.bundleIdentifier ?? "",
                bundlePath: $0.bundleURL?.standardizedFileURL.path ?? "",
                localizedName: $0.localizedName ?? ""
            )
        }
    }

    private static func appBundles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var bundles: [URL] = []
        for url in contents {
            if url.pathExtension == "app" {
                bundles.append(url)
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let nested = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            bundles.append(contentsOf: nested.filter { $0.pathExtension == "app" })
        }
        return bundles
    }

    @concurrent
    static func scanInstalledApps(running: [RunningAppSnapshot]) async -> [AppItem] {
        let fileManager = FileManager.default
        let runningIdentifiers = Set(running.map(\.bundleIdentifier).filter { !$0.isEmpty })
        let runningPaths = Set(running.map(\.bundlePath).filter { !$0.isEmpty })
        var seenPaths = Set<String>()
        var items: [AppItem] = []

        for directory in applicationDirectories {
            for url in appBundles(in: directory, fileManager: fileManager) {
                if Task.isCancelled { return [] }
                let standardized = url.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else { continue }
                let info = Bundle(url: standardized)?.infoDictionary
                let identifier = (info?["CFBundleIdentifier"] as? String) ?? ""
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? standardized.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String)
                    ?? (info?["CFBundleVersion"] as? String)
                    ?? "—"
                items.append(AppItem(
                    name: name,
                    bundleIdentifier: identifier,
                    bundleURL: standardized,
                    version: version,
                    isSystemApp: standardized.path.hasPrefix("/System/"),
                    isRunning: runningPaths.contains(standardized.path) || (!identifier.isEmpty && runningIdentifiers.contains(identifier))
                ))
            }
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @concurrent
    static func computeBundleSizes(
        for apps: [AppItem],
        maxConcurrent: Int = 4,
        flushInterval: Duration = .milliseconds(300),
        onBatch: @escaping @Sendable ([UUID: Int64]) async -> Void
    ) async {
        var cachedBatch: [UUID: Int64] = [:]
        var uncachedApps: [AppItem] = []
        for app in apps {
            if let cached = cachedSize(for: app.bundleURL) {
                cachedBatch[app.id] = cached
            } else {
                uncachedApps.append(app)
            }
        }
        if !cachedBatch.isEmpty && !Task.isCancelled {
            await onBatch(cachedBatch)
        }
        guard !uncachedApps.isEmpty, !Task.isCancelled else { return }

        await withTaskGroup(of: (UUID, Int64).self) { group in
            var iterator = uncachedApps.makeIterator()
            var pending: [UUID: Int64] = [:]
            let clock = ContinuousClock()
            var lastFlush = clock.now

            func enqueueNext() {
                guard !Task.isCancelled, let app = iterator.next() else { return }
                let url = app.bundleURL
                group.addTask(priority: .utility) {
                    if let cached = cachedSize(for: url) {
                        return (app.id, cached)
                    }
                    let computed = DirectorySize.allocatedSize(of: url)
                    if !Task.isCancelled {
                        storeCachedSize(computed, for: url)
                    }
                    return (app.id, computed)
                }
            }

            for _ in 0..<maxConcurrent {
                enqueueNext()
            }
            while let (id, size) = await group.next() {
                pending[id] = size
                if clock.now - lastFlush >= flushInterval {
                    await onBatch(pending)
                    pending.removeAll(keepingCapacity: true)
                    lastFlush = clock.now
                }
                enqueueNext()
            }
            if !pending.isEmpty && !Task.isCancelled {
                await onBatch(pending)
            }
        }
    }
}
