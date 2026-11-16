import AppKit
import Foundation

nonisolated enum SystemCleanEngine {
    nonisolated struct Location: Sendable {
        let label: String
        let url: URL
        let root: URL
    }

    private static let systemCacheBlacklist: Set<String> = [
        "com.apple.bird", "com.apple.clouddocs", "cloudkit", "com.apple.spotlight",
        "com.apple.nsurlsessiond", "com.apple.findmy", "com.apple.addressbook",
        "com.apple.homekit", "com.apple.passbook", "com.apple.corehandwriting",
        "com.apple.commerce", "com.apple.softwareupdate", "com.apple.identityservicesd",
        "com.apple.keychainsharingd", "com.apple.akd", "com.apple.mobilesync",
        "temporaryitems", "com.antigravity.monohub",
        "amsdatamigratortool", "arfilecache", "audiounitcache", "clouddocs",
        "desktop pictures", "familycircle", "familycircled", "gamekit",
        "geoservices", "icdd", "knowledge", "lsmimagecache", "metadata",
        "passkit", "privacypreservingmeasurement", "sentrycrash",
        "sirientitycache", "sirittsservice", "trickplay",
        "monohub", "monoaibar", "monopod", "monoshot", "monostats", "monotab", "monotile", "mononotch"
    ]

    private static let systemCachePrefixBlacklist: [String] = [
        "com.apple.", "com.icloud.", "com.antigravity.",
        "com.1password", "com.agilebits", "com.bitwarden", "org.keepassxc"
    ]

    private static let logsSkipList: Set<String> = [
        "baseband", "bluetooth", "clouddocs", "crashreporter", "diagnosticreports",
        "discrecording", "facetime", "familycircled", "fileprovider", "fsck_apfs.log",
        "hfs_convert.log", "homekit", "identityservices", "localizationswitcherd",
        "locationd", "mail", "messages", "mobilesync", "smsmigrator", "spotlight",
        "sync", "talagent.log",
        "monohub", "monoaibar", "monopod", "monoshot", "monostats", "monotab", "monotile", "mononotch"
    ]
    static let temporaryMinimumAge: TimeInterval = 24 * 3600
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
    private static let looseTemporaryThreshold: Int64 = 10_240
    private static let maximumListedTemporaryEntries = 50

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library", isDirectory: true) }
    static var caches: URL { library.appendingPathComponent("Caches", isDirectory: true) }
    static var logs: URL { library.appendingPathComponent("Logs", isDirectory: true) }
    static var diagnosticReports: URL { logs.appendingPathComponent("DiagnosticReports", isDirectory: true) }
    static var downloads: URL { home.appendingPathComponent("Downloads", isDirectory: true) }
    static var userTrash: URL { home.appendingPathComponent(".Trash", isDirectory: true) }

    static var temporaryRoots: [URL] {
        [
            FileManager.default.temporaryDirectory.standardizedFileURL,
            caches.appendingPathComponent("TemporaryItems", isDirectory: true)
        ]
    }

    static var trashRoots: [URL] {
        var roots = [userTrash]
        let uid = getuid()
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for volume in volumes where PathSafety.isSafePathComponent(volume) {
                let trash = URL(fileURLWithPath: "/Volumes", isDirectory: true)
                    .appendingPathComponent(volume, isDirectory: true)
                    .appendingPathComponent(".Trashes/\(uid)", isDirectory: true)
                if FileManager.default.fileExists(atPath: trash.path) {
                    roots.append(trash)
                }
            }
        }
        return roots
    }

    static var browserLocations: [Location] {
        let safariContainer = library.appendingPathComponent("Containers/com.apple.Safari/Data/Library", isDirectory: true)
        return [
            Location(label: "Safari", url: caches.appendingPathComponent("com.apple.Safari"), root: caches),
            Location(label: "Safari (Container)", url: safariContainer.appendingPathComponent("Caches"), root: safariContainer),
            Location(label: "Safari Technology Preview", url: caches.appendingPathComponent("com.apple.SafariTechnologyPreview"), root: caches),
            Location(label: "Google Chrome", url: caches.appendingPathComponent("Google/Chrome"), root: caches),
            Location(label: "Brave", url: caches.appendingPathComponent("BraveSoftware/Brave-Browser"), root: caches),
            Location(label: "Arc", url: caches.appendingPathComponent("company.thebrowser.Browser"), root: caches),
            Location(label: "Helium", url: caches.appendingPathComponent("net.imput.helium"), root: caches),
            Location(label: "Zen Browser", url: caches.appendingPathComponent("zen"), root: caches),
            Location(label: "Zen Browser (Bundle)", url: caches.appendingPathComponent("app.zen-browser.zen"), root: caches),
            Location(label: "DuckDuckGo", url: caches.appendingPathComponent("com.duckduckgo.macos.browser"), root: caches),
            Location(label: "Orion", url: caches.appendingPathComponent("company.kagi.orion"), root: caches),
            Location(label: "Microsoft Edge", url: caches.appendingPathComponent("Microsoft Edge"), root: caches),
            Location(label: "Firefox", url: caches.appendingPathComponent("Firefox"), root: caches),
            Location(label: "Chromium", url: caches.appendingPathComponent("Chromium"), root: caches),
            Location(label: "Opera", url: caches.appendingPathComponent("com.operasoftware.Opera"), root: caches),
            Location(label: "Vivaldi", url: caches.appendingPathComponent("Vivaldi"), root: caches)
        ]
    }

    static var mailLocations: [Location] {
        let mailContainer = library.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true)
        let legacyMail = library.appendingPathComponent("Mail Downloads", isDirectory: true)
        let mailRoot = library.appendingPathComponent("Containers/com.apple.mail/Data/Library", isDirectory: true)
        return [
            Location(label: "Mail Downloads", url: mailContainer, root: mailRoot),
            Location(label: "Mail Downloads (~/Library)", url: legacyMail, root: library)
        ]
    }

    static var developerLocations: [Location] {
        let xcode = library.appendingPathComponent("Developer/Xcode", isDirectory: true)
        let developer = library.appendingPathComponent("Developer", isDirectory: true)
        let pnpm = library.appendingPathComponent("pnpm", isDirectory: true)
        let nuget = home.appendingPathComponent(".nuget", isDirectory: true)
        let npm = home.appendingPathComponent(".npm", isDirectory: true)
        let cargo = home.appendingPathComponent(".cargo/registry", isDirectory: true)
        let dotCache = home.appendingPathComponent(".cache", isDirectory: true)
        let gradle = home.appendingPathComponent(".gradle", isDirectory: true)
        let android = home.appendingPathComponent(".android", isDirectory: true)
        let bun = home.appendingPathComponent(".bun", isDirectory: true)
        return [
            Location(label: "Xcode DerivedData", url: xcode.appendingPathComponent("DerivedData"), root: xcode),
            Location(label: "iOS DeviceSupport", url: xcode.appendingPathComponent("iOS DeviceSupport"), root: xcode),
            Location(label: "Xcode CoreSimulator", url: developer.appendingPathComponent("CoreSimulator/Caches"), root: developer),
            Location(label: "Xcode Caches", url: caches.appendingPathComponent("com.apple.dt.Xcode"), root: caches),
            Location(label: "Homebrew", url: caches.appendingPathComponent("Homebrew"), root: caches),
            Location(label: "SwiftPM", url: caches.appendingPathComponent("org.swift.swiftpm"), root: caches),
            Location(label: "JetBrains", url: caches.appendingPathComponent("JetBrains"), root: caches),
            Location(label: "Yarn", url: caches.appendingPathComponent("Yarn"), root: caches),
            Location(label: "pip", url: caches.appendingPathComponent("pip"), root: caches),
            Location(label: "CocoaPods", url: caches.appendingPathComponent("CocoaPods"), root: caches),
            Location(label: "Go build", url: caches.appendingPathComponent("go-build"), root: caches),
            Location(label: "Go build (~/.cache)", url: dotCache.appendingPathComponent("go-build"), root: dotCache),
            Location(label: "pnpm store", url: pnpm.appendingPathComponent("store"), root: pnpm),
            Location(label: "NuGet", url: nuget.appendingPathComponent("packages"), root: nuget),
            Location(label: "npm", url: npm.appendingPathComponent("_cacache"), root: npm),
            Location(label: "Cargo registry", url: cargo.appendingPathComponent("cache"), root: cargo),
            Location(label: "Gradle", url: gradle.appendingPathComponent("caches"), root: gradle),
            Location(label: "Android cache", url: android.appendingPathComponent("cache"), root: android),
            Location(label: "Android build-cache", url: android.appendingPathComponent("build-cache"), root: android),
            Location(label: "Bun cache", url: bun.appendingPathComponent("install/cache"), root: bun),
            Location(label: "sccache (Rust/C++)", url: caches.appendingPathComponent("Mozilla.sccache"), root: caches)
        ]
    }

    static var userCacheSkipList: Set<String> {
        let cachesPath = caches.standardizedFileURL.path + "/"
        let owned = (browserLocations + developerLocations).compactMap { location -> String? in
            let path = location.url.standardizedFileURL.path
            guard path.hasPrefix(cachesPath) else { return nil }
            return path.dropFirst(cachesPath.count).split(separator: "/").first.map { $0.lowercased() }
        }
        return systemCacheBlacklist.union(owned)
    }

    static func allowedRoots(for type: CleanCategoryType) -> [URL] {
        switch type {
        case .userCaches: return [caches]
        case .userLogs: return [logs]
        case .crashReports: return [diagnosticReports]
        case .browserCaches: return Array(Set(browserLocations.map(\.root)))
        case .mailDownloads: return Array(Set(mailLocations.map(\.root)))
        case .developerTools: return Array(Set(developerLocations.map(\.root)))
        case .installerJunk: return [downloads]
        case .tempFiles: return temporaryRoots
        case .trash: return trashRoots
        case .timeMachineSnapshots: return [URL(fileURLWithPath: "/")]
        }
    }

    private struct Candidate: Sendable {
        let type: CleanCategoryType
        let name: String
        let url: URL
    }

    static func cleanableChildren(of directory: URL, skipping skipList: Set<String> = []) -> [URL] {
        children(of: directory, skipping: skipList)
    }

    private static func children(of directory: URL, skipping skipList: Set<String> = []) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { name in
            let lowered = name.lowercased()
            guard !name.hasPrefix("."), !skipList.contains(lowered) else { return nil }
            guard !systemCachePrefixBlacklist.contains(where: lowered.hasPrefix) else { return nil }
            guard let url = PathSafety.child(named: name, of: directory) else { return nil }
            guard PathSafety.isAccessibleAndDeletable(url) else { return nil }
            return url
        }
    }

    private static func existing(_ locations: [Location], type: CleanCategoryType) -> [Candidate] {
        locations.compactMap { location in
            guard FileManager.default.fileExists(atPath: location.url.path) else { return nil }
            guard PathSafety.isAccessibleAndDeletable(location.url) else { return nil }
            return Candidate(type: type, name: location.label, url: location.url)
        }
    }

    static func temporaryCandidates(in roots: [URL], now: Date = Date()) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileResourceTypeKey]
        let cutoff = now.addingTimeInterval(-temporaryMinimumAge)
        var results: [URL] = []
        for root in roots {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in contents {
                let name = item.lastPathComponent.lowercased()
                guard !name.hasPrefix("com.apple."), !name.hasPrefix("monohub") else { continue }
                guard let values = try? item.resourceValues(forKeys: keys) else { continue }
                let type = values.fileResourceType
                guard type == .regular || type == .directory else { continue }
                guard let modified = values.contentModificationDate, modified < cutoff else { continue }
                if type == .directory, DirectorySize.hasModification(after: cutoff, in: item) { continue }
                results.append(item.standardizedFileURL)
            }
        }
        return results
    }

    private enum TemporaryClusterKind: CaseIterable {
        case monoDownload
        case dotnetPipes
        case tempSessions

        var localizedTitle: String {
            switch self {
            case .monoDownload: return localized("MonoDownload test folders")
            case .dotnetPipes: return localized(".NET/CLR pipes and sockets")
            case .tempSessions: return localized("Temporary sessions")
            }
        }

        func matches(_ name: String) -> Bool {
            switch self {
            case .monoDownload:
                return name.hasPrefix("monodownload-test-")
            case .dotnetPipes:
                return name.hasPrefix("clr-debug-pipe-") || name.hasPrefix("dotnet-diagnostic-")
            case .tempSessions:
                return name.hasPrefix("TemporaryDirectory.")
            }
        }
    }

    static func clusterTemporaryEntries(_ entries: [CleanMember]) -> [CleanSubItem] {
        var clusters: [TemporaryClusterKind: [CleanMember]] = [:]
        var remaining: [CleanMember] = []
        for entry in entries where entry.size > 0 {
            let name = entry.url.lastPathComponent
            if let kind = TemporaryClusterKind.allCases.first(where: { $0.matches(name) }) {
                clusters[kind, default: []].append(entry)
            } else {
                remaining.append(entry)
            }
        }

        var results: [CleanSubItem] = clusters.map { kind, members in
            makeCluster(name: "\(kind.localizedTitle) (\(members.count))", members: members)
        }

        let prominent = remaining.filter { $0.size >= looseTemporaryThreshold }.sorted { $0.size > $1.size }
        for entry in prominent.prefix(maximumListedTemporaryEntries) {
            results.append(CleanSubItem(name: entry.url.lastPathComponent, url: entry.url, size: entry.size))
        }
        let miscellaneous = Array(prominent.dropFirst(maximumListedTemporaryEntries))
            + remaining.filter { $0.size < looseTemporaryThreshold }
        if !miscellaneous.isEmpty {
            results.append(makeCluster(name: localized("Other temporary items (%d)", miscellaneous.count), members: miscellaneous))
        }
        return results.sorted { $0.size > $1.size }
    }

    private static func makeCluster(name: String, members: [CleanMember]) -> CleanSubItem {
        let sorted = members.sorted { $0.size > $1.size }
        return CleanSubItem(
            name: name,
            url: sorted[0].url,
            members: sorted,
            size: sorted.reduce(0) { $0 + $1.size }
        )
    }

    private static func directTrashItems() -> [URL]? {
        var items: [URL] = []
        var failed = false
        for root in trashRoots {
            do {
                let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
                items.append(contentsOf: names.compactMap { name in
                    name.hasPrefix(".") ? nil : PathSafety.child(named: name, of: root)
                })
            } catch {
                if root == userTrash { failed = true }
            }
        }
        return failed ? nil : items
    }

    private static let finderListTrashScript = """
    tell application "Finder"
        set output to {}
        repeat with anItem in (every item of trash)
            try
                set itemSize to size of anItem
                if itemSize is missing value then set itemSize to 0
                set end of output to ((itemSize as string) & tab & (POSIX path of (anItem as alias)))
            end try
        end repeat
        set AppleScript's text item delimiters to linefeed
        return output as text
    end tell
    """

    private static let finderEmptyTrashScript = """
    tell application "Finder" to empty trash
    """

    static func parseFinderTrashListing(_ text: String) -> [CleanMember] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let size = Int64(Double(parts[0].replacingOccurrences(of: ",", with: ".")) ?? 0)
            var path = String(parts[1])
            while path.count > 1 && path.hasSuffix("/") {
                path.removeLast()
            }
            guard path.hasPrefix("/") else { return nil }
            return CleanMember(url: URL(fileURLWithPath: path).standardizedFileURL, size: size)
        }
    }

    private static func finderTrashItems() async -> [CleanMember] {
        guard let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", finderListTrashScript], timeout: .seconds(30)),
              output.succeeded else { return [] }
        return parseFinderTrashListing(output.output)
    }

    static func parseSnapshotList(_ output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("Snapshots for"),
                  !trimmed.hasPrefix("NOTE:"),
                  !trimmed.contains(":") else { return nil }
            return trimmed
        }
    }

    static func snapshotDate(from name: String) -> String? {
        if let range = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) {
            return String(name[range])
        }
        let trimmed = name
            .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func formatSnapshotDate(_ dateString: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd-HHmmss"
        guard let date = parser.date(from: dateString) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func scanTimeMachineSnapshots() async -> [CleanSubItem] {
        guard let result = await ProcessRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: .seconds(15)),
              result.succeeded else {
            return []
        }
        let snapshotNames = parseSnapshotList(result.output)
        guard !snapshotNames.isEmpty else { return [] }

        let rootURL = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        var totalPurgeable: Int64 = 0
        if let values = try? rootURL.resourceValues(forKeys: keys),
           let important = values.volumeAvailableCapacityForImportantUsage,
           let available = values.volumeAvailableCapacity {
            totalPurgeable = max(0, important - Int64(available))
        }

        let perSnapshotSize = max(totalPurgeable / Int64(snapshotNames.count), 0)

        return snapshotNames.map { name in
            let date = snapshotDate(from: name)
            let formatted = date.flatMap { formatSnapshotDate($0) }
            let friendly = formatted != nil ? "\(localized("Snapshot")) · \(formatted!)" : nil
            let pseudoURL = URL(fileURLWithPath: "/Volumes/.timemachine/\(name)")
            return CleanSubItem(
                name: name,
                friendlyName: friendly,
                customIcon: "clock.arrow.circlepath",
                url: pseudoURL,
                size: perSnapshotSize
            )
        }
    }

    static func deleteSnapshots(_ items: [CleanSubItem]) async -> RemovalReport {
        var report = RemovalReport()
        guard !items.isEmpty else { return report }

        var failedForElevation: [(CleanSubItem, String)] = []

        for item in items {
            guard let date = snapshotDate(from: item.name) else {
                report.errors.append(localized("Invalid snapshot date: %@", item.name))
                continue
            }

            if let output = await ProcessRunner.run("/usr/bin/tmutil", ["deletelocalsnapshots", date], timeout: .seconds(60)),
               output.succeeded {
                report.removedURLs.append(item.url)
                report.bytesFreed += item.size
            } else {
                failedForElevation.append((item, date))
            }
        }

        if !failedForElevation.isEmpty {
            let dates = failedForElevation.map(\.1)
            let commands = dates.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: " && ")
            let adminScript = "do shell script \"\(commands)\" with administrator privileges"
            if let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", adminScript], timeout: .seconds(180)),
               output.succeeded {
                for (item, _) in failedForElevation {
                    report.removedURLs.append(item.url)
                    report.bytesFreed += item.size
                }
            } else {
                let msg = localized("Failed to delete Time Machine snapshots with administrator privileges.")
                report.errors.append(msg)
            }
        }

        return report
    }

    @concurrent
    static func scanCategories(progress: ProgressReporter = .silent) async -> [CleanCategoryGroup] {
        progress.report(ScanProgress(message: localized("Scanning caches, logs, and temporary files…")), force: true)

        let runningSnapshots = await MainActor.run { AppScanner.runningApplications() }
        let installedApps = await AppScanner.scanInstalledApps(running: runningSnapshots)
        var appNameByIdentifier: [String: String] = [:]
        var runningBundleIds = Set<String>()
        var runningNames = Set<String>()
        for app in installedApps {
            let lowerId = app.bundleIdentifier.lowercased()
            if !lowerId.isEmpty {
                appNameByIdentifier[lowerId] = app.name
            }
            if app.isRunning {
                if !lowerId.isEmpty { runningBundleIds.insert(lowerId) }
                runningNames.insert(app.name.lowercased())
            }
        }
        for running in runningSnapshots {
            let id = running.bundleIdentifier.lowercased()
            if !id.isEmpty {
                runningBundleIds.insert(id)
            }
            let name = running.localizedName.lowercased()
            if !name.isEmpty {
                runningNames.insert(name)
            }
        }

        var candidates: [Candidate] = []
        candidates += children(of: caches, skipping: userCacheSkipList).map { Candidate(type: .userCaches, name: $0.lastPathComponent, url: $0) }
        candidates += children(of: logs, skipping: logsSkipList).map { Candidate(type: .userLogs, name: $0.lastPathComponent, url: $0) }
        candidates += children(of: diagnosticReports).map { Candidate(type: .crashReports, name: $0.lastPathComponent, url: $0) }
        candidates += existing(browserLocations, type: .browserCaches)
        candidates += existing(mailLocations, type: .mailDownloads)
        candidates += existing(developerLocations, type: .developerTools)
        candidates += children(of: downloads)
            .filter { Self.installerExtensions.contains($0.pathExtension.lowercased()) }
            .map { Candidate(type: .installerJunk, name: $0.lastPathComponent, url: $0) }

        let whitelist = WhitelistManager.shared
        candidates.removeAll { whitelist.blocksRemoval(of: $0.url.path) }

        let temporary = temporaryCandidates(in: temporaryRoots).filter { !whitelist.isUserWhitelisted(path: $0.path) }

        var finderTrash: [CleanMember] = []
        var trashURLs: [URL] = []
        if let direct = directTrashItems() {
            trashURLs = direct
        } else {
            progress.report(ScanProgress(message: localized("Checking Trash via Finder…")), force: true)
            finderTrash = await finderTrashItems()
        }
        if Task.isCancelled { return [] }

        let urlsToMeasure = candidates.map(\.url) + temporary + trashURLs
        let total = urlsToMeasure.count
        let sizes = await DirectorySize.allocatedSizes(of: urlsToMeasure) { done in
            progress.report(ScanProgress(message: localized("Calculating sizes…"), completed: done, total: total))
        }
        if Task.isCancelled { return [] }

        var itemsByType: [CleanCategoryType: [CleanSubItem]] = [:]
        for candidate in candidates {
            let size = sizes[candidate.url] ?? 0
            let minimum: Int64 = candidate.type == .installerJunk ? 1 : 1024
            guard size >= minimum else { continue }
            let lowerCandidateName = candidate.name.lowercased()
            let baseIdentifier = lowerCandidateName.hasSuffix(".shipit")
                ? String(lowerCandidateName.dropLast(".shipit".count))
                : lowerCandidateName
            let friendly = appNameByIdentifier[lowerCandidateName] ?? appNameByIdentifier[baseIdentifier]
            let isRunning = runningBundleIds.contains(lowerCandidateName)
                || runningBundleIds.contains(baseIdentifier)
                || runningNames.contains(lowerCandidateName)
                || (friendly != nil && runningNames.contains(friendly!.lowercased()))
            itemsByType[candidate.type, default: []].append(
                CleanSubItem(
                    name: candidate.name,
                    friendlyName: friendly,
                    isAppRunning: isRunning,
                    url: candidate.url,
                    size: size
                )
            )
        }

        itemsByType[.tempFiles] = clusterTemporaryEntries(temporary.map { CleanMember(url: $0, size: sizes[$0] ?? 0) })

        let trashMembers = trashURLs.map { CleanMember(url: $0, size: sizes[$0] ?? 0) } + finderTrash
        itemsByType[.trash] = trashMembers
            .filter { !whitelist.isUserWhitelisted(path: $0.url.path) }
            .map { CleanSubItem(name: $0.url.lastPathComponent, url: $0.url, size: $0.size) }

        progress.report(ScanProgress(message: localized("Scanning Time Machine local snapshots…")), force: true)
        let snapshots = await scanTimeMachineSnapshots()
        itemsByType[.timeMachineSnapshots] = snapshots

        return CleanCategoryType.allCases.map { type in
            CleanCategoryGroup(type: type, items: (itemsByType[type] ?? []).sorted { $0.size > $1.size })
        }
    }

    static func removalTargets(for type: CleanCategoryType, items: [CleanSubItem]) -> [RemovalTarget] {
        let roots = allowedRoots(for: type)
        return items.flatMap { item in
            item.members.map { member in
                RemovalTarget(
                    url: member.url,
                    displayName: item.isCluster ? "\(item.name) · \(member.url.lastPathComponent)" : item.name,
                    size: member.size,
                    allowedRoots: roots
                )
            }
        }
    }

    @concurrent
    static func clean(
        selections: [(CleanCategoryType, [CleanSubItem])],
        emptiesWholeTrash: Bool,
        options: CleanupOptions
    ) async -> RemovalReport {
        var report = RemovalReport()

        let regularTargets = selections
            .filter { $0.0 != .trash && $0.0 != .timeMachineSnapshots }
            .flatMap { removalTargets(for: $0.0, items: $0.1) }
        let regular = SafeFileRemover.removeAll(regularTargets, mode: options.deletionMode)
        report.removedURLs += regular.removedURLs
        report.bytesFreed += regular.bytesFreed
        report.errors += regular.errors

        let trashTargets = selections
            .filter { $0.0 == .trash }
            .flatMap { removalTargets(for: $0.0, items: $0.1) }
        if !trashTargets.isEmpty {
            var trash = SafeFileRemover.removeAll(trashTargets, mode: .deletePermanently)
            if !trash.errors.isEmpty && emptiesWholeTrash,
               let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", finderEmptyTrashScript], timeout: .seconds(120)),
               output.succeeded {
                let removed = Set(trash.removedURLs)
                let remaining = trashTargets.filter { !removed.contains($0.url.standardizedFileURL) }
                trash.removedURLs += remaining.map(\.url)
                trash.bytesFreed += remaining.reduce(0) { $0 + $1.size }
                trash.errors.removeAll()
            }
            report.removedURLs += trash.removedURLs
            report.bytesFreed += trash.bytesFreed
            report.errors += trash.errors
        }

        let snapshotSelections = selections
            .filter { $0.0 == .timeMachineSnapshots }
            .flatMap { $0.1 }
        if !snapshotSelections.isEmpty {
            let snapshotReport = await deleteSnapshots(snapshotSelections)
            report.removedURLs += snapshotReport.removedURLs
            report.bytesFreed += snapshotReport.bytesFreed
            report.errors += snapshotReport.errors
        }

        if !report.removedURLs.isEmpty || !report.errors.isEmpty {
            let categories = selections.map(\.0.title).joined(separator: ", ")
            options.log(
                action: localized("System Clean"),
                result: report.result,
                details: localized("Removed %d items (%@)", report.removedURLs.count, categories)
            )
        }
        return report
    }
}
