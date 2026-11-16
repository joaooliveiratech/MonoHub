import Foundation

nonisolated struct ProjectArtifact: CleanupListItem, Equatable {
    let id: UUID
    let projectName: String
    let artifactType: String
    let path: URL
    let size: Int64
    let lastModified: Date
    var isSelected: Bool

    var isRecent: Bool {
        abs(lastModified.timeIntervalSinceNow) < (48 * 3600)
    }

    var formattedSize: String {
        Formatting.bytes(size)
    }

    var formattedDate: String {
        Formatting.relativeDate(lastModified)
    }

    var itemURL: URL { path }
    var itemName: String { "\(projectName)/\(artifactType)" }
    var itemSize: Int64 { size }

    init(
        id: UUID = UUID(),
        projectName: String,
        artifactType: String,
        path: URL,
        size: Int64,
        lastModified: Date = Date(),
        isSelected: Bool = false
    ) {
        self.id = id
        self.projectName = projectName
        self.artifactType = artifactType
        self.path = path
        self.size = size
        self.lastModified = lastModified
        self.isSelected = isSelected
    }
}
