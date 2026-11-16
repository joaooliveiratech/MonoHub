import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

nonisolated enum MediaInspector {
    static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "ts", "3gp", "m2ts"
    ]

    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "avif", "webp", "tiff", "tif", "bmp", "gif"
    ]

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedVideoExtensions.contains(ext) || supportedImageExtensions.contains(ext)
    }

    static func mediaKind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if supportedVideoExtensions.contains(ext) {
            return .video
        } else if supportedImageExtensions.contains(ext) {
            return .image
        }
        return nil
    }

    static func fileSize(for url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return 0
        }
    }

    static func inspect(url: URL) async -> (kind: MediaKind, format: String, metadata: MediaMetadata, fileSize: Int64)? {
        guard let kind = mediaKind(for: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let size = fileSize(for: url)

        switch kind {
        case .image:
            let meta = inspectImage(url: url)
            return (kind, ext.uppercased(), meta, size)
        case .video:
            let meta = await inspectVideo(url: url)
            return (kind, ext.uppercased(), meta, size)
        }
    }

    private static func inspectImage(url: URL) -> MediaMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return MediaMetadata()
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return MediaMetadata()
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        return MediaMetadata(
            width: width,
            height: height,
            duration: 0,
            videoCodec: "",
            audioCodec: nil,
            frameRate: 0,
            bitRate: 0
        )
    }

    private static func inspectVideo(url: URL) async -> MediaMetadata {
        let asset = AVURLAsset(url: url)
        var durationSeconds: TimeInterval = 0
        var width = 0
        var height = 0
        var frameRate: Double = 0
        var bitRate: Int64 = 0
        var videoCodec = ""
        var audioCodec: String? = nil

        if let duration = try? await asset.load(.duration) {
            durationSeconds = CMTimeGetSeconds(duration)
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video), let track = videoTracks.first {
            if let size = try? await track.load(.naturalSize) {
                width = Int(size.width)
                height = Int(size.height)
            }
            if let fps = try? await track.load(.nominalFrameRate) {
                frameRate = Double(fps)
            }
            if let rate = try? await track.load(.estimatedDataRate) {
                bitRate = Int64(rate)
            }
            if let descriptions = try? await track.load(.formatDescriptions), let desc = descriptions.first {
                let mediaSubtype = CMFormatDescriptionGetMediaSubType(desc)
                videoCodec = fourCCToString(mediaSubtype)
            }
        }

        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), let track = audioTracks.first {
            if let descriptions = try? await track.load(.formatDescriptions), let desc = descriptions.first {
                let mediaSubtype = CMFormatDescriptionGetMediaSubType(desc)
                audioCodec = fourCCToString(mediaSubtype)
            }
        }

        return MediaMetadata(
            width: width,
            height: height,
            duration: durationSeconds,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            frameRate: frameRate,
            bitRate: bitRate
        )
    }

    private static func fourCCToString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
