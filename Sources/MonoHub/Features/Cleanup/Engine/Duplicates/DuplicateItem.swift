import Foundation
import CoreGraphics

nonisolated enum DuplicatesScanMode: String, Sendable, CaseIterable, Identifiable {
    case exactHash = "Arquivos Idênticos (Hash)"
    case similarPhotos = "Fotos Similares (Vision)"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exactHash: return localized("Exact Files (Hash)")
        case .similarPhotos: return localized("Similar Photos (Vision)")
        }
    }

    var icon: String {
        switch self {
        case .exactHash: return "doc.on.doc"
        case .similarPhotos: return "photo.on.rectangle.angled"
        }
    }
}

nonisolated enum DuplicateSelectionStrategy: String, Sendable, CaseIterable, Identifiable {
    case keepOldest = "Manter Mais Antigos"
    case keepNewest = "Manter Mais Recentes"
    case keepShortestPath = "Manter Caminho Mais Curto"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepOldest: return localized("Keep Oldest")
        case .keepNewest: return localized("Keep Newest")
        case .keepShortestPath: return localized("Keep Shortest Path")
        }
    }
}

nonisolated struct DuplicateItem: Identifiable, Sendable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let path: String
    let size: Int64
    let modifiedDate: Date
    let hash: String
    let imageDimensions: CGSize?
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        path: String,
        size: Int64,
        modifiedDate: Date,
        hash: String,
        imageDimensions: CGSize? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
        self.hash = hash
        self.imageDimensions = imageDimensions
        self.isSelected = isSelected
    }
}

nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let hash: String
    var items: [DuplicateItem]
    let sizePerItem: Int64
    let isVisualSimilarity: Bool

    var totalSize: Int64 {
        sizePerItem * Int64(items.count)
    }

    var recoverableSize: Int64 {
        sizePerItem * Int64(max(items.count - 1, 0))
    }

    var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    var selectedBytes: Int64 {
        sizePerItem * Int64(selectedCount)
    }
}
