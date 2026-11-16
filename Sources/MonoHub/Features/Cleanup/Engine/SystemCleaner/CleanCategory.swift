import Foundation
import SwiftUI

nonisolated enum CleanSafetyLevel: String, Sendable {
    case safe = "100% Seguro"
    case caution = "Requer Re-download"
    case review = "Revisar Antes"

    var title: String {
        switch self {
        case .safe: return localized("100% Safe")
        case .caution: return localized("Requires Re-download")
        case .review: return localized("Review Before")
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .review: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .review: return "questionmark.circle.fill"
        }
    }
}

nonisolated enum CleanCategoryType: String, CaseIterable, Sendable {
    case userCaches = "Caches de Aplicativos"
    case userLogs = "Logs do Sistema e Usuário"
    case crashReports = "Relatórios de Erros e Diagnósticos"
    case browserCaches = "Caches de Navegadores"
    case mailDownloads = "Anexos do Mail"
    case developerTools = "Ferramentas de Desenvolvimento"
    case installerJunk = "Instaladores Antigos (.dmg, .pkg)"
    case tempFiles = "Arquivos Temporários"
    case trash = "Lixeira do macOS"
    case timeMachineSnapshots = "Snapshots Locais do Time Machine"

    var title: String {
        switch self {
        case .userCaches: return localized("Application Caches")
        case .userLogs: return localized("System and User Logs")
        case .crashReports: return localized("Crash and Diagnostic Reports")
        case .browserCaches: return localized("Browser Caches")
        case .mailDownloads: return localized("Mail Downloads (Attachments)")
        case .developerTools: return localized("Developer Tools")
        case .installerJunk: return localized("Old Installers (.dmg, .pkg)")
        case .tempFiles: return localized("Temporary Files")
        case .trash: return localized("macOS Trash")
        case .timeMachineSnapshots: return localized("Time Machine Local Snapshots (APFS)")
        }
    }

    var systemIcon: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .userLogs: return "doc.text.magnifyingglass"
        case .crashReports: return "exclamationmark.triangle"
        case .browserCaches: return "safari"
        case .mailDownloads: return "envelope.badge"
        case .developerTools: return "hammer"
        case .installerJunk: return "shippingbox.circle"
        case .tempFiles: return "clock.arrow.2.circlepath"
        case .trash: return "trash"
        case .timeMachineSnapshots: return "clock.arrow.circlepath"
        }
    }

    var categoryDescription: String {
        switch self {
        case .userCaches: return localized("Application caches that can be regenerated automatically.")
        case .userLogs: return localized("Old execution log files accumulated on the system.")
        case .crashReports: return localized("macOS crash reports and system diagnostics.")
        case .browserCaches: return localized("Cached files from Safari, Chrome, Arc, Brave, Edge, and Firefox.")
        case .mailDownloads: return localized("Local cached attachments downloaded by Apple Mail.")
        case .developerTools: return localized("Xcode DerivedData, Homebrew, npm, pnpm, cargo, go build, and other caches.")
        case .installerJunk: return localized("Installation files (.dmg, .pkg, .iso) left in the Downloads folder.")
        case .tempFiles: return localized("User temporary files unused for more than 24 hours.")
        case .trash: return localized("Discarded files still occupying disk space.")
        case .timeMachineSnapshots: return localized("APFS local snapshots stored on the internal drive, often taking 50–150 GB in “System Data”.")
        }
    }

    var safetyLevel: CleanSafetyLevel {
        switch self {
        case .userCaches: return .safe
        case .userLogs: return .safe
        case .crashReports: return .safe
        case .browserCaches: return .caution
        case .mailDownloads: return .caution
        case .developerTools: return .caution
        case .installerJunk: return .review
        case .tempFiles: return .safe
        case .trash: return .safe
        case .timeMachineSnapshots: return .safe
        }
    }

    var safetyTip: String {
        switch self {
        case .userCaches:
            return localized("Caches are recreated by the app as needed. No personal settings or documents are affected.")
        case .userLogs:
            return localized("Operating system execution logs. Safe for periodic cleanup.")
        case .crashReports:
            return localized("Previous crash reports. They do not affect the stability of any application.")
        case .browserCaches:
            return localized("Frees up gigabytes of website images and data. Cookies, history, and passwords are NOT deleted.")
        case .mailDownloads:
            return localized("Original attachments remain safe in your mail account (iCloud, Gmail, etc.) and can be redownloaded.")
        case .developerTools:
            return localized("Frees DerivedData, package caches, and build artifacts. Future builds may need to redownload dependencies.")
        case .installerJunk:
            return localized("Installation disk images already installed on the system. Check if you need to keep the installer.")
        case .tempFiles:
            return localized("Remnants from past macOS sessions that were not automatically cleared.")
        case .trash:
            return localized("Files moved to the Trash. Items in this category are always permanently deleted.")
        case .timeMachineSnapshots:
            return localized("APFS local snapshots created by Time Machine. Safe to remove; external backups on other drives remain intact.")
        }
    }
}

nonisolated struct CleanMember: Sendable, Equatable, Hashable {
    let url: URL
    let size: Int64
}

nonisolated struct CleanSubItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let friendlyName: String?
    let isAppRunning: Bool
    let customIcon: String?
    let url: URL
    let members: [CleanMember]
    let size: Int64
    var isSelected: Bool

    var displayName: String {
        if let friendlyName, !friendlyName.isEmpty, friendlyName.lowercased() != name.lowercased() {
            return "\(friendlyName) (\(name))"
        }
        return name
    }

    var formattedSize: String {
        Formatting.bytes(size)
    }

    var isCluster: Bool {
        members.count > 1
    }

    func removing(_ removed: Set<URL>) -> CleanSubItem? {
        let remaining = members.filter { !removed.contains($0.url.standardizedFileURL) }
        guard !remaining.isEmpty else { return nil }
        guard remaining.count != members.count else { return self }
        let countSuffix = " (\(members.count))"
        let updatedName = name.hasSuffix(countSuffix)
            ? String(name.dropLast(countSuffix.count)) + " (\(remaining.count))"
            : name
        return CleanSubItem(
            id: id,
            name: updatedName,
            friendlyName: friendlyName,
            isAppRunning: isAppRunning,
            customIcon: customIcon,
            url: remaining[0].url,
            members: remaining,
            size: remaining.reduce(0) { $0 + $1.size },
            isSelected: isSelected
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        friendlyName: String? = nil,
        isAppRunning: Bool = false,
        customIcon: String? = nil,
        url: URL,
        members: [CleanMember]? = nil,
        size: Int64,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.friendlyName = friendlyName
        self.isAppRunning = isAppRunning
        self.customIcon = customIcon
        self.url = url
        self.members = members ?? [CleanMember(url: url, size: size)]
        self.size = size
        self.isSelected = isSelected
    }
}

nonisolated struct CleanCategoryGroup: Identifiable, Sendable {
    let id: UUID
    let type: CleanCategoryType
    var items: [CleanSubItem]
    var isSelected: Bool

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var selectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }

    var totalCount: Int {
        items.count
    }

    var selectedCount: Int {
        items.filter { $0.isSelected }.count
    }

    var isAllSelected: Bool {
        !items.isEmpty && items.allSatisfy { $0.isSelected }
    }

    var isPartiallySelected: Bool {
        !items.isEmpty && !isAllSelected && items.contains { $0.isSelected }
    }

    var hasAnySelected: Bool {
        items.contains { $0.isSelected }
    }

    init(id: UUID = UUID(), type: CleanCategoryType, items: [CleanSubItem] = [], isSelected: Bool = false) {
        self.id = id
        self.type = type
        self.items = isSelected ? items : items.map { item in
            var copy = item
            copy.isSelected = false
            return copy
        }
        self.isSelected = isSelected
    }
}
