import Foundation

nonisolated final class DevEnvEngine: Sendable {
    static let shared = DevEnvEngine()

    private init() {}

    private struct RawCandidate: Sendable {
        let name: String
        let category: DevEnvCategory
        let url: URL
        let detail: String
        let isSafeCache: Bool
        let lastModified: Date?
    }

    func scanItems(progress: (@Sendable (Double, String) -> Void)? = nil) async -> [DevEnvItem] {
        await Task.detached(priority: .userInitiated) {
            progress?(0.1, localized("Discovering developer toolchains…"))

            let candidates = Self.collectCandidates()
            guard !candidates.isEmpty else { return [] }

            progress?(0.4, localized("Calculating sizes for %d environments…", candidates.count))

            let urls = candidates.map(\.url)
            let sizes = await DirectorySize.allocatedSizes(of: urls) { done in
                let frac = 0.4 + 0.5 * (Double(done) / Double(max(urls.count, 1)))
                progress?(frac, localized("Calculating sizes (%d/%d)…", done, urls.count))
            }

            progress?(0.95, localized("Organizing developer environments…"))

            var items: [DevEnvItem] = []
            for candidate in candidates {
                let size = sizes[candidate.url] ?? 0
                guard size > 1024 else { continue }

                items.append(DevEnvItem(
                    id: candidate.url.path,
                    name: candidate.name,
                    category: candidate.category,
                    url: candidate.url,
                    sizeBytes: size,
                    lastModified: candidate.lastModified,
                    detail: candidate.detail,
                    isSafeCache: candidate.isSafeCache,
                    isSelected: false
                ))
            }

            return items.sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }

    private static func collectCandidates() -> [RawCandidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let dotCache = home.appendingPathComponent(".cache", isDirectory: true)
        let fm = FileManager.default

        var candidates: [RawCandidate] = []

        let xcodeDir = library.appendingPathComponent("Developer/Xcode", isDirectory: true)
        let derivedData = xcodeDir.appendingPathComponent("DerivedData", isDirectory: true)
        if let projects = try? fm.contentsOfDirectory(at: derivedData, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for project in projects where !project.lastPathComponent.hasPrefix(".") {
                let modDate = (try? project.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let cleanName = project.lastPathComponent.components(separatedBy: "-").first ?? project.lastPathComponent
                candidates.append(RawCandidate(
                    name: "DerivedData: \(cleanName)",
                    category: .xcode,
                    url: project,
                    detail: localized("Xcode build cache"),
                    isSafeCache: true,
                    lastModified: modDate
                ))
            }
        }

        let deviceSupport = xcodeDir.appendingPathComponent("iOS DeviceSupport", isDirectory: true)
        if let devices = try? fm.contentsOfDirectory(at: deviceSupport, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for dev in devices where !dev.lastPathComponent.hasPrefix(".") {
                let modDate = (try? dev.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                candidates.append(RawCandidate(
                    name: "DeviceSupport: \(dev.lastPathComponent)",
                    category: .xcode,
                    url: dev,
                    detail: localized("Physical device symbols"),
                    isSafeCache: true,
                    lastModified: modDate
                ))
            }
        }

        let archives = xcodeDir.appendingPathComponent("Archives", isDirectory: true)
        if fm.fileExists(atPath: archives.path) {
            candidates.append(RawCandidate(
                name: localized("Xcode Archives"),
                category: .xcode,
                url: archives,
                detail: localized("Compiled build archives"),
                isSafeCache: false,
                lastModified: nil
            ))
        }

        let simulators = library.appendingPathComponent("Developer/CoreSimulator/Devices", isDirectory: true)
        if fm.fileExists(atPath: simulators.path) {
            candidates.append(RawCandidate(
                name: localized("iOS Simulator Instances"),
                category: .xcode,
                url: simulators,
                detail: localized("Simulator runtime disk images"),
                isSafeCache: false,
                lastModified: nil
            ))
        }

        let cocoapodsCache = caches.appendingPathComponent("CocoaPods", isDirectory: true)
        if fm.fileExists(atPath: cocoapodsCache.path) {
            candidates.append(RawCandidate(
                name: localized("CocoaPods Cache"),
                category: .xcode,
                url: cocoapodsCache,
                detail: localized("CocoaPods package and spec cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let nvmDir = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let nvmVersions = try? fm.contentsOfDirectory(at: nvmDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for ver in nvmVersions where !ver.lastPathComponent.hasPrefix(".") {
                candidates.append(RawCandidate(
                    name: "Node \(ver.lastPathComponent) (nvm)",
                    category: .node,
                    url: ver,
                    detail: localized("Installed Node.js runtime"),
                    isSafeCache: false,
                    lastModified: nil
                ))
            }
        }

        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        if fm.fileExists(atPath: npmCache.path) {
            candidates.append(RawCandidate(
                name: localized("npm Global Cache"),
                category: .node,
                url: npmCache,
                detail: localized("Package download cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let pnpmStore = library.appendingPathComponent("pnpm/store", isDirectory: true)
        if fm.fileExists(atPath: pnpmStore.path) {
            candidates.append(RawCandidate(
                name: localized("pnpm Global Store"),
                category: .node,
                url: pnpmStore,
                detail: localized("Shared package store"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let yarnCache = caches.appendingPathComponent("Yarn", isDirectory: true)
        if fm.fileExists(atPath: yarnCache.path) {
            candidates.append(RawCandidate(
                name: localized("Yarn Cache"),
                category: .node,
                url: yarnCache,
                detail: localized("Yarn package cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let bunCache = home.appendingPathComponent(".bun/install/cache", isDirectory: true)
        if fm.fileExists(atPath: bunCache.path) {
            candidates.append(RawCandidate(
                name: localized("Bun Cache"),
                category: .node,
                url: bunCache,
                detail: localized("Bun package cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let pyenvDir = home.appendingPathComponent(".pyenv/versions", isDirectory: true)
        if let pyVersions = try? fm.contentsOfDirectory(at: pyenvDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for ver in pyVersions where !ver.lastPathComponent.hasPrefix(".") {
                candidates.append(RawCandidate(
                    name: "Python \(ver.lastPathComponent) (pyenv)",
                    category: .python,
                    url: ver,
                    detail: localized("Installed Python runtime"),
                    isSafeCache: false,
                    lastModified: nil
                ))
            }
        }

        let pipCache = caches.appendingPathComponent("pip", isDirectory: true)
        if fm.fileExists(atPath: pipCache.path) {
            candidates.append(RawCandidate(
                name: localized("pip Cache"),
                category: .python,
                url: pipCache,
                detail: localized("Python wheel and package cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let uvCache = dotCache.appendingPathComponent("uv", isDirectory: true)
        if fm.fileExists(atPath: uvCache.path) {
            candidates.append(RawCandidate(
                name: localized("uv Cache"),
                category: .python,
                url: uvCache,
                detail: localized("uv package and wheel cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let hfCache = dotCache.appendingPathComponent("huggingface/hub", isDirectory: true)
        if fm.fileExists(atPath: hfCache.path) {
            candidates.append(RawCandidate(
                name: localized("Hugging Face Model Cache"),
                category: .python,
                url: hfCache,
                detail: localized("Downloaded weights and models"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let brewCache = caches.appendingPathComponent("Homebrew", isDirectory: true)
        if fm.fileExists(atPath: brewCache.path) {
            candidates.append(RawCandidate(
                name: localized("Homebrew Downloads Cache"),
                category: .homebrew,
                url: brewCache,
                detail: localized("Downloaded bottles and tarballs"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let cargoCache = home.appendingPathComponent(".cargo/registry/cache", isDirectory: true)
        if fm.fileExists(atPath: cargoCache.path) {
            candidates.append(RawCandidate(
                name: localized("Cargo Registry Cache"),
                category: .rustGo,
                url: cargoCache,
                detail: localized("Rust crate download cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let goBuildCache = caches.appendingPathComponent("go-build", isDirectory: true)
        if fm.fileExists(atPath: goBuildCache.path) {
            candidates.append(RawCandidate(
                name: localized("Go Build Cache"),
                category: .rustGo,
                url: goBuildCache,
                detail: localized("Go compiled packages cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let gradleCache = home.appendingPathComponent(".gradle/caches", isDirectory: true)
        if fm.fileExists(atPath: gradleCache.path) {
            candidates.append(RawCandidate(
                name: localized("Gradle Cache"),
                category: .rustGo,
                url: gradleCache,
                detail: localized("Gradle dependencies and artifact cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let swiftpmCache = caches.appendingPathComponent("org.swift.swiftpm", isDirectory: true)
        if fm.fileExists(atPath: swiftpmCache.path) {
            candidates.append(RawCandidate(
                name: localized("SwiftPM Cache"),
                category: .xcode,
                url: swiftpmCache,
                detail: localized("Swift Package Manager cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let dockerVM = library.appendingPathComponent("Containers/com.docker.docker/Data/vms", isDirectory: true)
        if fm.fileExists(atPath: dockerVM.path) {
            candidates.append(RawCandidate(
                name: localized("Docker Virtual Machine Disks"),
                category: .containers,
                url: dockerVM,
                detail: localized("Docker Desktop VM storage"),
                isSafeCache: false,
                lastModified: nil
            ))
        }

        let androidCache = home.appendingPathComponent(".android/build-cache", isDirectory: true)
        if fm.fileExists(atPath: androidCache.path) {
            candidates.append(RawCandidate(
                name: localized("Android Build Cache"),
                category: .containers,
                url: androidCache,
                detail: localized("Android SDK build cache"),
                isSafeCache: true,
                lastModified: nil
            ))
        }

        let whitelist = WhitelistManager.shared
        return candidates.filter { candidate in
            !whitelist.blocksRemoval(of: candidate.url.path)
                && PathSafety.isAccessibleAndDeletable(candidate.url)
        }
    }

    func removeItems(_ items: [DevEnvItem], options: CleanupOptions? = nil) async -> RemovalReport {
        let resolvedOptions: CleanupOptions
        if let options {
            resolvedOptions = options
        } else {
            resolvedOptions = await MainActor.run { CleanupOptions.current }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets = items.map { item in
            RemovalTarget(
                url: item.url,
                displayName: item.name,
                size: item.sizeBytes,
                allowedRoots: [home]
            )
        }
        return await CleanupExecutor.execute(
            targets,
            options: resolvedOptions,
            action: localized("Cleaned developer environments")
        ) { report in
            localized("Removed %d items", report.removedURLs.count)
        }
    }
}
