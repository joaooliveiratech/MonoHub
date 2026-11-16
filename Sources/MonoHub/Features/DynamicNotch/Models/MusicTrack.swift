import AppKit
import Foundation

enum MusicPlayerType: String, Sendable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtube = "YouTube / Web"
    case appleTV = "Apple TV"
    case quickTime = "QuickTime"
    case podcasts = "Podcasts"
    case video = "Video"
    case system = "System Audio"

    var displayName: String {
        switch self {
        case .video: return localized("Video")
        case .system: return localized("System Audio")
        default: return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .appleMusic: return "apple.logo"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .youtube: return "play.rectangle.fill"
        case .appleTV: return "appletv"
        case .quickTime: return "play.tv.fill"
        case .podcasts: return "waveform"
        case .video: return "film.fill"
        case .system: return "speaker.wave.2.fill"
        }
    }

    static func from(bundleIdentifier: String?, appName: String?) -> MusicPlayerType {
        let bid = (bundleIdentifier ?? "").lowercased()
        let name = (appName ?? "").lowercased()

        if bid == "com.apple.music" || name.contains("music") && bid.contains("apple") {
            return .appleMusic
        }
        if bid == "com.spotify.client" || name.contains("spotify") {
            return .spotify
        }
        if bid == "com.apple.podcasts" || name.contains("podcast") {
            return .podcasts
        }
        if bid == "com.apple.tv" || name.contains("apple tv") {
            return .appleTV
        }
        if bid == "com.apple.quicktimeplayerx" || name.contains("quicktime") {
            return .quickTime
        }
        if bid.contains("safari") || bid.contains("chrome") || bid.contains("browser") || bid.contains("firefox") || bid.contains("edge") || bid.contains("opera") || bid.contains("brave") || bid.contains("vivaldi") || bid.contains("orion") {
            return .youtube
        }
        if bid.contains("vlc") || bid.contains("iina") || bid.contains("mpv") || bid.contains("infuse") || bid.contains("movist") {
            return .video
        }
        return .system
    }
}

nonisolated struct MusicTrack: Sendable, Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let isPlaying: Bool
    let playerType: MusicPlayerType
    let appName: String
    let artworkData: Data?

    init(
        title: String = "No Playback",
        artist: String = "Nothing currently playing",
        album: String = "",
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        isPlaying: Bool = false,
        playerType: MusicPlayerType = .system,
        appName: String = "System",
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.playerType = playerType
        self.appName = appName
        self.artworkData = artworkData
    }

    static let empty = MusicTrack(
        title: "No Playback",
        artist: "Nothing currently playing",
        album: "",
        duration: 0,
        elapsed: 0,
        isPlaying: false,
        playerType: .system,
        appName: "System",
        artworkData: nil
    )

    var isEmpty: Bool {
        title.isEmpty || title == "No Playback" || title == "Sem reprodução" || title == localized("No playback")
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var formattedElapsed: String {
        Self.format(elapsed)
    }

    var formattedDuration: String {
        Self.format(duration)
    }

    static func format(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
