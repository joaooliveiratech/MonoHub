import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated enum StartupItemType: String, Sendable, CaseIterable, Identifiable {
    case userAgent = "LaunchAgent de Usuário"
    case systemAgent = "LaunchAgent do Sistema"
    case systemDaemon = "LaunchDaemon do Sistema"
    case loginItem = "Item de Início"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userAgent: return localized("User LaunchAgent")
        case .systemAgent: return localized("System LaunchAgent")
        case .systemDaemon: return localized("System LaunchDaemon")
        case .loginItem: return localized("Login Item")
        }
    }

    var icon: String {
        switch self {
        case .userAgent: return "person.badge.shield.checkmark"
        case .systemAgent: return "gearshape.2"
        case .systemDaemon: return "bolt.shield"
        case .loginItem: return "macwindow.badge.plus"
        }
    }

    var sortPriority: Int {
        switch self {
        case .loginItem: return 0
        case .userAgent: return 1
        case .systemAgent: return 2
        case .systemDaemon: return 3
        }
    }
}

nonisolated struct StartupItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let label: String
    let type: StartupItemType
    let plistURL: URL?
    let executablePath: String?
    let arguments: [String]
    let isEnabled: Bool
    let runAtLoad: Bool
    let isApple: Bool
    let isOrphaned: Bool
    let sizeBytes: Int64
    let bundleIdentifier: String?

    init(
        id: String,
        name: String,
        label: String,
        type: StartupItemType,
        plistURL: URL?,
        executablePath: String?,
        arguments: [String],
        isEnabled: Bool,
        runAtLoad: Bool,
        isApple: Bool,
        isOrphaned: Bool = false,
        sizeBytes: Int64,
        bundleIdentifier: String?
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.type = type
        self.plistURL = plistURL
        self.executablePath = executablePath
        self.arguments = arguments
        self.isEnabled = isEnabled
        self.runAtLoad = runAtLoad
        self.isApple = isApple
        self.isOrphaned = isOrphaned
        self.sizeBytes = sizeBytes
        self.bundleIdentifier = bundleIdentifier
    }

    var requiresAdministrator: Bool {
        type == .systemAgent || type == .systemDaemon
    }

    func icon() -> NSImage {
        if let executablePath, FileManager.default.fileExists(atPath: executablePath) {
            return NSWorkspace.shared.icon(forFile: executablePath)
        }
        if type == .loginItem {
            let candidates = [
                "/Applications/\(name).app",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/\(name).app"
            ]
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
            if let bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSWorkspace.shared.icon(for: .application)
        }
        if let plistURL, FileManager.default.fileExists(atPath: plistURL.path) {
            return NSWorkspace.shared.icon(forFile: plistURL.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
