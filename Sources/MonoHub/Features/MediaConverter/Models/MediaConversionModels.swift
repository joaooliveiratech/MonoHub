import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

nonisolated enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case video = "Vídeo"
    case image = "Imagem"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return localized("Video")
        case .image: return localized("Image")
        }
    }

    var iconName: String {
        switch self {
        case .video: return "film.stack"
        case .image: return "photo.stack"
        }
    }

    var tintColor: Color {
        switch self {
        case .video: return .indigo
        case .image: return .teal
        }
    }
}

nonisolated enum VideoPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case tablet720p = "Tablet 720p Fullscreen"
    case tablet480p = "Tablet 480p SD"
    case universal1080p = "Universal MP4 (1080p)"
    case webOptimized = "Web / Tamanho Mínimo"
    case hevcHighEfficiency = "HEVC / H.265 (Apple Silicon)"
    case audioOnly = "Apenas Áudio (M4A / AAC)"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tablet720p: return localized("Tablet 720p Fullscreen")
        case .tablet480p: return localized("Tablet 480p SD")
        case .universal1080p: return localized("Universal MP4 (1080p)")
        case .webOptimized: return localized("Web / Minimum Size")
        case .hevcHighEfficiency: return localized("HEVC / H.265 (Apple Silicon)")
        case .audioOnly: return localized("Audio Only (M4A / AAC)")
        }
    }

    var subtitle: String {
        switch self {
        case .tablet720p:
            return localized("H.264 720p, AAC 128k, Fast Start • ~85% smaller")
        case .tablet480p:
            return localized("H.264 480p Baseline, AAC 96k, Fast Start • ~92% smaller")
        case .universal1080p:
            return localized("H.264 1080p, AAC 192k • High universal compatibility")
        case .webOptimized:
            return localized("Compact for streaming and quick web uploads")
        case .hevcHighEfficiency:
            return localized("Maximum quality and compression via Apple Silicon Media Engine")
        case .audioOnly:
            return localized("Extracts the audio track directly to M4A / AAC")
        }
    }

    var badgeText: String {
        switch self {
        case .tablet720p: return "720p"
        case .tablet480p: return "480p"
        case .universal1080p: return "1080p"
        case .webOptimized: return localized("Web")
        case .hevcHighEfficiency: return "HEVC"
        case .audioOnly: return localized("Audio")
        }
    }

    var exportPresetName: String {
        switch self {
        case .tablet720p:
            return AVAssetExportPreset1280x720
        case .tablet480p:
            return AVAssetExportPreset640x480
        case .universal1080p:
            return AVAssetExportPreset1920x1080
        case .webOptimized:
            return AVAssetExportPreset1280x720
        case .hevcHighEfficiency:
            return AVAssetExportPresetHEVC1920x1080
        case .audioOnly:
            return AVAssetExportPresetAppleM4A
        }
    }

    var targetExtension: String {
        switch self {
        case .audioOnly: return "m4a"
        default: return "mp4"
        }
    }
}

nonisolated enum ImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case heic = "HEIC (Apple Silicon)"
    case avif = "AVIF (Web Next-Gen)"
    case webp = "WebP (Google Web)"
    case jpeg = "JPEG (Universal)"
    case png = "PNG (Sem Perdas)"
    case tiff = "TIFF (Alta Definição)"
    case gif = "GIF (Animado / Web)"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic: return localized("HEIC (Apple Silicon)")
        case .avif: return localized("AVIF (Web Next-Gen)")
        case .webp: return localized("WebP (Google Web)")
        case .jpeg: return localized("JPEG (Universal)")
        case .png: return localized("PNG (Lossless)")
        case .tiff: return localized("TIFF (High Definition)")
        case .gif: return localized("GIF (Animated / Web)")
        }
    }

    var shortName: String {
        switch self {
        case .heic: return "HEIC"
        case .avif: return "AVIF"
        case .webp: return "WebP"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        }
    }

    var targetExtension: String {
        switch self {
        case .heic: return "heic"
        case .avif: return "avif"
        case .webp: return "webp"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .gif: return "gif"
        }
    }

    var utTypeIdentifier: String {
        switch self {
        case .heic: return "public.heic"
        case .avif: return "public.avif"
        case .webp: return "org.webmproject.webp"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .tiff: return "public.tiff"
        case .gif: return "com.compuserve.gif"
        }
    }

    var subtitle: String {
        switch self {
        case .heic:
            return localized("50-70% smaller than JPEG while retaining color fidelity")
        case .avif:
            return localized("Cutting-edge open standard for lightweight web images")
        case .webp:
            return localized("Lightweight high-density format widely supported")
        case .jpeg:
            return localized("Guaranteed compatibility across any app or system")
        case .png:
            return localized("Lossless compression with alpha channel / transparency support")
        case .tiff:
            return localized("Absolute fidelity without aggressive compression")
        case .gif:
            return localized("Standard animated image for web and messaging")
        }
    }
}

nonisolated struct VideoConversionOptions: Codable, Sendable, Equatable {
    var preset: VideoPreset = .tablet720p
    var fastStart: Bool = true

    init(preset: VideoPreset = .tablet720p, fastStart: Bool = true) {
        self.preset = preset
        self.fastStart = fastStart
    }
}

nonisolated enum MaxDimensionPreset: String, CaseIterable, Identifiable, Sendable {
    case original = "Tamanho original"
    case hd1080 = "1080p (1920 px)"
    case qhd2k = "2K (2560 px)"
    case uhd4k = "4K (3840 px)"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return localized("Original size")
        case .hd1080: return localized("1080p (1920 px)")
        case .qhd2k: return localized("2K (2560 px)")
        case .uhd4k: return localized("4K (3840 px)")
        }
    }

    var pixelLimit: Int? {
        switch self {
        case .original: return nil
        case .hd1080: return 1920
        case .qhd2k: return 2560
        case .uhd4k: return 3840
        }
    }
}

nonisolated struct ImageConversionOptions: Codable, Sendable, Equatable {
    var format: ImageFormat = .heic
    var quality: Double = 0.82
    var stripEXIF: Bool = true
    var maxDimension: Int? = nil

    init(
        format: ImageFormat = .heic,
        quality: Double = 0.82,
        stripEXIF: Bool = true,
        maxDimension: Int? = nil
    ) {
        self.format = format
        self.quality = quality
        self.stripEXIF = stripEXIF
        self.maxDimension = maxDimension
    }
}

nonisolated struct MediaMetadata: Sendable, Equatable {
    var width: Int = 0
    var height: Int = 0
    var duration: TimeInterval = 0
    var videoCodec: String = ""
    var audioCodec: String? = nil
    var frameRate: Double = 0
    var bitRate: Int64 = 0

    init(
        width: Int = 0,
        height: Int = 0,
        duration: TimeInterval = 0,
        videoCodec: String = "",
        audioCodec: String? = nil,
        frameRate: Double = 0,
        bitRate: Int64 = 0
    ) {
        self.width = width
        self.height = height
        self.duration = duration
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.frameRate = frameRate
        self.bitRate = bitRate
    }

    var resolutionDescription: String {
        if width > 0 && height > 0 {
            return "\(width) × \(height)"
        }
        return ""
    }

    var durationDescription: String {
        guard duration > 0 else { return "" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

nonisolated struct ConversionResult: Sendable, Equatable {
    let originalURL: URL
    let outputURL: URL
    let originalSize: Int64
    let convertedSize: Int64
    let durationSeconds: Double

    init(
        originalURL: URL,
        outputURL: URL,
        originalSize: Int64,
        convertedSize: Int64,
        durationSeconds: Double
    ) {
        self.originalURL = originalURL
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.convertedSize = convertedSize
        self.durationSeconds = durationSeconds
    }

    var savedBytes: Int64 {
        max(0, originalSize - convertedSize)
    }

    var savingsPercentage: Double {
        guard originalSize > 0 else { return 0 }
        let diff = Double(originalSize - convertedSize)
        return (diff / Double(originalSize)) * 100.0
    }

    var savingsText: String {
        let pct = savingsPercentage
        if pct > 0 {
            return String(format: "-%.1f%%", pct)
        } else if pct < 0 {
            return String(format: "+%.1f%%", abs(pct))
        } else {
            return "0%"
        }
    }
}

nonisolated enum ItemConversionStatus: Sendable, Equatable {
    case pending
    case converting(progress: Double)
    case completed(ConversionResult)
    case failed(String)
    case cancelled
}

@Observable
final class MediaItem: Identifiable, @unchecked Sendable {
    let id: UUID
    let fileURL: URL
    var fileName: String
    var fileSize: Int64
    var kind: MediaKind
    var originalExtension: String
    var metadata: MediaMetadata?
    var videoOptions: VideoConversionOptions
    var imageOptions: ImageConversionOptions
    var status: ItemConversionStatus
    var isCustomized: Bool

    init(
        fileURL: URL,
        fileSize: Int64,
        kind: MediaKind,
        originalExtension: String,
        metadata: MediaMetadata? = nil,
        videoOptions: VideoConversionOptions = VideoConversionOptions(),
        imageOptions: ImageConversionOptions = ImageConversionOptions(),
        isCustomized: Bool = false
    ) {
        self.id = UUID()
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.fileSize = fileSize
        self.kind = kind
        self.originalExtension = originalExtension.lowercased()
        self.metadata = metadata
        self.videoOptions = videoOptions
        self.imageOptions = imageOptions
        self.status = .pending
        self.isCustomized = isCustomized
    }
}
