import Foundation

nonisolated enum MaintenanceStatus: String, Sendable {
    case idle = "Pronto"
    case running = "Executando…"
    case completed = "Concluído"
    case failed = "Falha"

    var title: String {
        switch self {
        case .idle: return localized("Ready")
        case .running: return localized("Running…")
        case .completed: return localized("Done")
        case .failed: return localized("Failed")
        }
    }
}

nonisolated struct MaintenanceTask: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let whenToUse: String
    let category: String
    let systemIcon: String
    let requiresAdministrator: Bool
    var status: MaintenanceStatus
    var outputMessage: String

    init(
        id: String,
        title: String,
        description: String,
        whenToUse: String,
        category: String,
        systemIcon: String,
        requiresAdministrator: Bool = false,
        status: MaintenanceStatus = .idle,
        outputMessage: String = ""
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.whenToUse = whenToUse
        self.category = category
        self.systemIcon = systemIcon
        self.requiresAdministrator = requiresAdministrator
        self.status = status
        self.outputMessage = outputMessage
    }
}
