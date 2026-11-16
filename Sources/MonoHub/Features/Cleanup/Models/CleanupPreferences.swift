import Foundation

@Observable
@MainActor
final class CleanupPreferences {
    static let shared = CleanupPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let moveToTrash = "MonoHub_moveToTrashInsteadOfDelete"
        static let confirmBeforeDeleting = "MonoHub_confirmBeforeDeleting"
        static let largeFileThreshold = "MonoHub_largeFileThresholdBytes"
        static let enableLogging = "MonoHub_enableLocalLogging"
        static let devScanPaths = "MonoHub_devScanPaths"
        static let projectScanMaxDepth = "MonoHub_projectScanMaxDepth"
        static let projectArtifactAgeDays = "MonoHub_projectArtifactAgeDays"
    }

    var moveToTrashInsteadOfDelete: Bool {
        didSet { defaults.set(moveToTrashInsteadOfDelete, forKey: Keys.moveToTrash) }
    }

    var confirmBeforeDeleting: Bool {
        didSet { defaults.set(confirmBeforeDeleting, forKey: Keys.confirmBeforeDeleting) }
    }

    var largeFileThresholdBytes: Double {
        didSet { defaults.set(largeFileThresholdBytes, forKey: Keys.largeFileThreshold) }
    }

    var enableLocalLogging: Bool {
        didSet { defaults.set(enableLocalLogging, forKey: Keys.enableLogging) }
    }

    var devScanPaths: [String] {
        didSet { defaults.set(devScanPaths, forKey: Keys.devScanPaths) }
    }

    var projectScanMaxDepth: Int {
        didSet { defaults.set(projectScanMaxDepth, forKey: Keys.projectScanMaxDepth) }
    }

    var projectArtifactAgeDays: Int {
        didSet { defaults.set(projectArtifactAgeDays, forKey: Keys.projectArtifactAgeDays) }
    }

    private init() {
        self.moveToTrashInsteadOfDelete = defaults.object(forKey: Keys.moveToTrash) == nil ? true : defaults.bool(forKey: Keys.moveToTrash)
        self.confirmBeforeDeleting = defaults.object(forKey: Keys.confirmBeforeDeleting) == nil ? true : defaults.bool(forKey: Keys.confirmBeforeDeleting)

        let storedThreshold = defaults.double(forKey: Keys.largeFileThreshold)
        self.largeFileThresholdBytes = storedThreshold > 0 ? storedThreshold : 104_857_600.0

        self.enableLocalLogging = defaults.object(forKey: Keys.enableLogging) == nil ? true : defaults.bool(forKey: Keys.enableLogging)

        if let storedPaths = defaults.stringArray(forKey: Keys.devScanPaths) {
            self.devScanPaths = storedPaths
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.devScanPaths = ["\(home)/dev", "\(home)/Documents/Projects"]
        }

        let storedDepth = defaults.integer(forKey: Keys.projectScanMaxDepth)
        self.projectScanMaxDepth = storedDepth > 0 ? storedDepth : 4

        self.projectArtifactAgeDays = defaults.integer(forKey: Keys.projectArtifactAgeDays)
    }

    func addDevPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !devScanPaths.contains(trimmed) {
            devScanPaths.append(trimmed)
        }
    }

    func removeDevPath(_ path: String) {
        devScanPaths.removeAll { $0 == path }
    }
}
