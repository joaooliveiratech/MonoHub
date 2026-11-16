import AppKit
import Foundation

nonisolated struct ShelfItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let fileSizeString: String
    let isDirectory: Bool
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        fileSizeString: String? = nil,
        isDirectory: Bool? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.dateAdded = dateAdded

        let isDir = isDirectory ?? ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        self.isDirectory = isDir

        if let sizeStr = fileSizeString {
            self.fileSizeString = sizeStr
        } else if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let bytes = resources.fileSize {
            self.fileSizeString = Formatting.bytes(Int64(bytes))
        } else {
            self.fileSizeString = isDir ? "Pasta" : "Item"
        }
    }
}
