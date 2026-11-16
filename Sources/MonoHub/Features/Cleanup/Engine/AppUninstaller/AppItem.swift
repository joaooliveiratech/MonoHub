import Foundation

nonisolated struct AppItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let bundleIdentifier: String
    let bundleURL: URL
    let version: String
    let isSystemApp: Bool
    let isProtected: Bool
    var isRunning: Bool

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        bundleURL: URL,
        version: String = "1.0",
        isSystemApp: Bool = false,
        isRunning: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.version = version
        self.isSystemApp = isSystemApp
        self.isRunning = isRunning
        self.isProtected = isSystemApp
            || bundleIdentifier.lowercased().hasPrefix("com.apple.")
            || bundleIdentifier == Bundle.main.bundleIdentifier
            || WhitelistManager.shared.isWhitelisted(path: bundleURL.path)
    }
}
