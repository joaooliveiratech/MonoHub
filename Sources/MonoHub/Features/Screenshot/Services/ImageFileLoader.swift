import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageFileLoader {
    struct LoadedImage: Sendable {
        let image: CGImage
        let scaleFactor: CGFloat
    }

    enum LoadError: Error, Equatable {
        case notAnImage
        case tooLarge
        case decodeFailed
    }

    static let maxPixelCount = 120_000_000
    static let maxFileSize = 256 * 1024 * 1024

    static func fileURLs(fromArguments arguments: some Sequence<String>) -> [URL] {
        arguments
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }
    }

    @concurrent
    static func load(_ url: URL, maxPixelCount: Int = maxPixelCount) async throws -> LoadedImage {
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, values.contentType?.conforms(to: .image) == true else {
            throw LoadError.notAnImage
        }
        guard (values.fileSize ?? 0) <= maxFileSize else { throw LoadError.tooLarge }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetCount(source) > 0 else { throw LoadError.notAnImage }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, width * height <= maxPixelCount else { throw LoadError.tooLarge }

        let decodeOptions = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions) else { throw LoadError.decodeFailed }

        let dpi = properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        return LoadedImage(image: image, scaleFactor: min(3, max(1, (dpi / 72).rounded())))
    }
}
