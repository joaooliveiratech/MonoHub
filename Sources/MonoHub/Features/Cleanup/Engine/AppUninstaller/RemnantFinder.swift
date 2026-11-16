import Foundation

nonisolated final class RemnantFinder: Sendable {
    static let shared = RemnantFinder()

    private init() {}

    private static let genericNameBlacklist: Set<String> = [
        "system", "apple", "library", "core", "services", "finder", "safari",
        "security", "framework", "shared", "common", "default", "mac", "macos",
        "helper", "agent", "daemon", "service", "app", "application", "data", "cache",
        "caches", "logs", "preferences", "containers", "google", "microsoft", "adobe"
    ]

    func calculateSize(of url: URL) -> Int64 {
        DirectorySize.allocatedSize(of: url)
    }

    static var homeLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    }

    static var uninstallRoots: [URL] {
        let library = homeLibrary
        let libraryRoots = [
            "Application Support", "Caches", "Preferences", "Saved Application State",
            "Containers", "Group Containers", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Application Scripts"
        ].map { library.appendingPathComponent($0, isDirectory: true) }
        return libraryRoots + [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
        ]
    }

    static func isSafeAppName(_ name: String) -> Bool {
        name.count >= 3
            && PathSafety.isSafePathComponent(name)
            && !genericNameBlacklist.contains(name.lowercased())
    }

    static func usableBundleIdentifier(_ identifier: String) -> String? {
        guard PathSafety.isValidBundleIdentifier(identifier),
              !identifier.lowercased().hasPrefix("com.apple.") else { return nil }
        return identifier
    }

    struct Candidate: Sendable {
        let category: RemnantCategory
        let url: URL
        let match: RemnantMatch
    }

    static func candidates(
        for bundleURL: URL,
        bundleIdentifier: String,
        appName: String,
        library: URL = RemnantFinder.homeLibrary,
        systemLibrary: URL = URL(fileURLWithPath: "/Library", isDirectory: true),
        whitelist: WhitelistManager = .shared
    ) -> [Candidate] {
        let fileManager = FileManager.default
        var results: [Candidate] = [Candidate(category: .appBundle, url: bundleURL.standardizedFileURL, match: .bundleIdentifier)]
        var seen: Set<String> = [bundleURL.standardizedFileURL.path]

        func exists(_ url: URL) -> Bool {
            (try? fileManager.attributesOfItem(atPath: url.path)) != nil
        }

        func add(_ category: RemnantCategory, _ url: URL?, _ match: RemnantMatch) {
            guard let url, exists(url), seen.insert(url.path).inserted else { return }
            guard !whitelist.blocksRemoval(of: url.path) else { return }
            results.append(Candidate(category: category, url: url, match: match))
        }

        func addChild(_ category: RemnantCategory, _ directory: String, _ name: String, _ match: RemnantMatch, in base: URL = library) {
            add(category, PathSafety.child(named: name, of: base.appendingPathComponent(directory, isDirectory: true)), match)
        }

        func addMatching(_ category: RemnantCategory, _ directory: URL, _ match: RemnantMatch, where predicate: (String) -> Bool) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
            for name in names.sorted() where predicate(name) {
                add(category, PathSafety.child(named: name, of: directory), match)
            }
        }

        if let identifier = usableBundleIdentifier(bundleIdentifier) {
            let dotted: Set<Character> = ["."]
            addChild(.applicationSupport, "Application Support", identifier, .bundleIdentifier)
            addChild(.caches, "Caches", identifier, .bundleIdentifier)
            addMatching(.preferences, library.appendingPathComponent("Preferences"), .bundleIdentifier) {
                PathSafety.nameMatches($0, prefix: identifier, separators: dotted)
            }
            addChild(.savedState, "Saved Application State", "\(identifier).savedState", .bundleIdentifier)
            addChild(.containers, "Containers", identifier, .bundleIdentifier)
            addChild(.applicationScripts, "Application Scripts", identifier, .bundleIdentifier)
            addMatching(.groupContainers, library.appendingPathComponent("Group Containers"), .bundleIdentifier) {
                PathSafety.groupContainerMatches($0, bundleIdentifier: identifier)
            }
            addMatching(.httpStorages, library.appendingPathComponent("HTTPStorages"), .bundleIdentifier) {
                PathSafety.nameMatches($0, prefix: identifier, separators: dotted)
            }
            addChild(.webKit, "WebKit", identifier, .bundleIdentifier)
            addChild(.logs, "Logs", identifier, .bundleIdentifier)
            for agents in [
                library.appendingPathComponent("LaunchAgents"),
                systemLibrary.appendingPathComponent("LaunchAgents"),
                systemLibrary.appendingPathComponent("LaunchDaemons")
            ] {
                addMatching(.launchAgents, agents, .bundleIdentifier) {
                    PathSafety.nameMatches($0, prefix: identifier, separators: dotted)
                }
            }
        }

        if isSafeAppName(appName) {
            addChild(.applicationSupport, "Application Support", appName, .appName)
            addChild(.caches, "Caches", appName, .appName)
            addChild(.logs, "Logs", appName, .appName)
            addMatching(.crashReports, library.appendingPathComponent("Logs/DiagnosticReports"), .appName) {
                PathSafety.nameMatches($0, prefix: appName, separators: ["-", "_", "."])
            }
        }

        return results
    }

    @concurrent
    func findRemnants(for bundleURL: URL, bundleIdentifier: String, appName: String) async -> [RemnantItem] {
        let found = Self.candidates(for: bundleURL, bundleIdentifier: bundleIdentifier, appName: appName)
        let sizes = await DirectorySize.allocatedSizes(of: found.map(\.url))
        return found.map { candidate in
            RemnantItem(
                category: candidate.category,
                url: candidate.url,
                size: sizes[candidate.url] ?? 0,
                match: candidate.match,
                isSelected: candidate.match == .bundleIdentifier
            )
        }
    }
}
