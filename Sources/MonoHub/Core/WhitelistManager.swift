import Foundation

nonisolated final class WhitelistManager: @unchecked Sendable {
    static let shared = WhitelistManager(
        configDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/monohub", isDirectory: true)
    )

    private let configDirectory: URL
    private let whitelistFileURL: URL
    private let lock = NSLock()

    private var customEntries: Set<String> = []
    private var expandedEntries: [String] = []

    private let exactProtectedPaths: Set<String>
    private let systemProtectedPrefixes: [String]

    init(configDirectory: URL, homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.configDirectory = configDirectory
        self.whitelistFileURL = configDirectory.appendingPathComponent("whitelist")
        let home = homeDirectory

        self.exactProtectedPaths = [
            "/", "/Users", "/Applications", "/Library", "/Volumes", home,
            "\(home)/Library",
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Preferences",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Developer",
            "\(home)/Applications",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Pictures",
            "\(home)/.Trash",
            "\(home)/.config"
        ]

        self.systemProtectedPrefixes = [

            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/var",
            "/etc",
            "/cores",
            "/opt",
            "/Library/Apple",
            "/Library/SystemExtensions",
            "/Library/Extensions",
            "/Library/KernelExtensions",
            "/Library/StagedExtensions",
            "/Library/Preferences/SystemConfiguration",
            "/Library/Security",
            "/Library/Keychains",

            "/Applications/Safari.app",
            "/Applications/Finder.app",
            "/Applications/MonoHub.app",
            "/System/Applications",
            "/Applications/Utilities",

            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.aws",
            "\(home)/.kube",
            "\(home)/.config/monohub",
            "\(home)/Library/Keychains",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/CloudStorage",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/HomeKit",
            "\(home)/Library/Accounts",
            "\(home)/Library/IdentityServices",
            "\(home)/Library/Cookies",
            "\(home)/Library/Passes",
            "\(home)/Library/Logs/MonoHub",
            "\(home)/Pictures/Photos Library.photoslibrary"
        ]

        loadEntries()
    }

    func loadEntries() {
        let entries: Set<String>
        if let content = try? String(contentsOf: whitelistFileURL, encoding: .utf8) {
            entries = Set(
                content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            )
        } else {
            entries = []
        }
        lock.lock()
        apply(entries)
        lock.unlock()
    }

    private func apply(_ entries: Set<String>) {
        customEntries = entries
        expandedEntries = entries.map { Self.normalize(NSString(string: $0).expandingTildeInPath) }
    }

    private func saveEntries(_ entries: Set<String>) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let content = entries.sorted().joined(separator: "\n") + "\n"
            try content.write(to: whitelistFileURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: whitelistFileURL.path)
        } catch {
            return
        }
    }

    func allEntries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return customEntries.sorted()
    }

    func add(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return }
        lock.lock()
        var entries = customEntries
        entries.insert(trimmed)
        apply(entries)
        lock.unlock()
        saveEntries(entries)
    }

    func remove(path: String) {
        lock.lock()
        var entries = customEntries
        entries.remove(path)
        apply(entries)
        lock.unlock()
        saveEntries(entries)
    }

    private static func normalize(_ path: String) -> String {
        var standardized = (path as NSString).standardizingPath
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    private static func isSameOrDescendant(_ candidate: String, of prefix: String) -> Bool {
        candidate == prefix || candidate.hasPrefix(prefix == "/" ? "/" : prefix + "/")
    }

    private func candidates(for path: String) -> [String] {
        let standardized = Self.normalize(path)
        let resolved = Self.normalize(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        return standardized == resolved ? [standardized] : [standardized, resolved]
    }

    func isUserWhitelisted(path: String) -> Bool {
        lock.lock()
        let entries = expandedEntries
        lock.unlock()
        guard !entries.isEmpty else { return false }
        return candidates(for: path).contains { candidate in
            entries.contains { Self.isSameOrDescendant(candidate, of: $0) }
        }
    }

    func isSystemProtected(path: String, exemptingDescendantsOf exemptRoots: [String] = []) -> Bool {
        let normalizedExemptRoots = exemptRoots.map(Self.normalize)
        return candidates(for: path).contains { candidate in
            if exactProtectedPaths.contains(candidate) {
                return true
            }
            let isExempt = normalizedExemptRoots.contains { root in
                candidate.hasPrefix(root + "/")
            }
            if isExempt {
                return false
            }
            return systemProtectedPrefixes.contains { Self.isSameOrDescendant(candidate, of: $0) }
        }
    }

    func isWhitelisted(path: String) -> Bool {
        isSystemProtected(path: path) || isUserWhitelisted(path: path)
    }
}
