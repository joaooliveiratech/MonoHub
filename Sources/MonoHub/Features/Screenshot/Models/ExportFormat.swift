import Foundation
import UniformTypeIdentifiers

nonisolated enum ExportFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case tiff
    case heic

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .heic: return "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .heic: return .heic
        }
    }

    var isLossy: Bool {
        self == .jpeg || self == .heic
    }

    init?(contentType: UTType) {
        guard let match = Self.allCases.first(where: { contentType.conforms(to: $0.contentType) }) else { return nil }
        self = match
    }

    static func inferred(fromExtension ext: String) -> ExportFormat {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "tif", "tiff": return .tiff
        case "heic", "heif": return .heic
        default: return .png
        }
    }
}
