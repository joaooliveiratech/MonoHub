import Foundation

nonisolated enum RemnantCategory: String, CaseIterable, Sendable {
    case appBundle = "Aplicativo"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferências"
    case savedState = "Estado Salvo"
    case containers = "Containers Sandbox"
    case groupContainers = "Group Containers"
    case launchAgents = "Launch Agents / Daemons"
    case webKit = "WebKit & Cookies"
    case httpStorages = "HTTP Storages"
    case applicationScripts = "Application Scripts"
    case logs = "Logs de Execução"
    case crashReports = "Relatórios de Erro"
    case other = "Outros Resíduos"

    var title: String {
        switch self {
        case .appBundle: return localized("Application")
        case .applicationSupport: return localized("Application Support")
        case .caches: return localized("Caches")
        case .preferences: return localized("Preferences")
        case .savedState: return localized("Saved State")
        case .containers: return localized("Sandbox Containers")
        case .groupContainers: return localized("Group Containers")
        case .launchAgents: return localized("Launch Agents / Daemons")
        case .webKit: return localized("WebKit & Cookies")
        case .httpStorages: return localized("HTTP Storages")
        case .applicationScripts: return localized("Application Scripts")
        case .logs: return localized("Execution Logs")
        case .crashReports: return localized("Crash Reports")
        case .other: return localized("Other Remnants")
        }
    }

    var systemIcon: String {
        switch self {
        case .appBundle: return "app.badge.checkmark"
        case .applicationSupport: return "folder.badge.gearshape"
        case .caches: return "internaldrive"
        case .preferences: return "slider.horizontal.3"
        case .savedState: return "arrow.counterclockwise.circle"
        case .containers: return "shippingbox"
        case .groupContainers: return "person.2.badge.gearshape"
        case .launchAgents: return "clock.arrow.2.circlepath"
        case .webKit: return "safari"
        case .httpStorages: return "network"
        case .applicationScripts: return "applescript"
        case .logs: return "doc.text.magnifyingglass"
        case .crashReports: return "exclamationmark.triangle"
        case .other: return "doc"
        }
    }

    var detail: String {
        switch self {
        case .appBundle: return localized("Application executable and bundle.")
        case .applicationSupport: return localized("App data, local databases, and settings.")
        case .caches: return localized("Cached files that the app recreates.")
        case .preferences: return localized(".plist files containing saved preferences.")
        case .savedState: return localized("Window positions and previous sessions.")
        case .containers: return localized("Sandbox containing isolated app data.")
        case .groupContainers: return localized("Shared data between extensions from the same developer.")
        case .launchAgents: return localized("Background processes started at login or boot.")
        case .webKit: return localized("Cookies, webpage data, and WebKit cache.")
        case .httpStorages: return localized("Network session storage.")
        case .applicationScripts: return localized("Extension and automation scripts installed by the app.")
        case .logs: return localized("App execution logs.")
        case .crashReports: return localized("Previous crash reports for the app.")
        case .other: return localized("Additional auxiliary files.")
        }
    }
}

nonisolated enum RemnantMatch: String, Sendable, Equatable {
    case bundleIdentifier = "ID do Pacote"
    case appName = "Nome do App"
    case launchAgent = "Launch Agent"

    var title: String {
        switch self {
        case .bundleIdentifier: return localized("Bundle ID")
        case .appName: return localized("App Name")
        case .launchAgent: return localized("Launch Agent")
        }
    }
}

nonisolated struct RemnantItem: CleanupListItem, Equatable {
    let id: UUID
    let category: RemnantCategory
    let url: URL
    let size: Int64
    let match: RemnantMatch
    var isSelected: Bool

    var path: String {
        url.path
    }

    var displayName: String {
        url.lastPathComponent
    }

    var formattedSize: String {
        Formatting.bytes(size)
    }

    var itemURL: URL { url }
    var itemName: String { displayName }
    var itemSize: Int64 { size }

    init(id: UUID = UUID(), category: RemnantCategory, url: URL, size: Int64, match: RemnantMatch = .bundleIdentifier, isSelected: Bool = true) {
        self.id = id
        self.category = category
        self.url = url
        self.size = size
        self.match = match
        self.isSelected = isSelected
    }
}
