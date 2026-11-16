import Foundation

nonisolated enum ScreenRecordingFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case gif = "gif"
    case mp4 = "mp4"
    case webm = "webm"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .gif: return "gif"
        case .mp4: return "mp4"
        case .webm: return "webm"
        }
    }

    var displayName: String {
        switch self {
        case .gif: return "GIF"
        case .mp4: return "MP4"
        case .webm: return "WebM"
        }
    }

    var iconName: String {
        switch self {
        case .gif: return "photo.stack"
        case .mp4: return "film"
        case .webm: return "globe"
        }
    }
}
