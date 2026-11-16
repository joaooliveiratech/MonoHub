import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum SettingsBackup {
    enum BackupError: LocalizedError {
        case fileTooLarge
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: return localized("The file is too large to be a valid settings backup.")
            case .unsupportedVersion(let version): return localized("Settings version %d is not supported.", version)
            }
        }
    }

    private static let maxFileSize = 256 * 1024

    static func export(_ preferences: TilePreferencesManager, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences.snapshot())
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func importSettings(into preferences: TilePreferencesManager, from url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxFileSize else { throw BackupError.fileTooLarge }

        let snapshot = try JSONDecoder().decode(PreferencesSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version <= PreferencesSnapshot.currentVersion else {
            throw BackupError.unsupportedVersion(snapshot.version)
        }
        preferences.apply(snapshot)
    }

    static func presentExportPanel(for preferences: TilePreferencesManager) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MonoHub WindowTiling Settings.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try export(preferences, to: url) }
    }

    static func presentImportPanel(for preferences: TilePreferencesManager) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try importSettings(into: preferences, from: url) }
    }

    private static func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
