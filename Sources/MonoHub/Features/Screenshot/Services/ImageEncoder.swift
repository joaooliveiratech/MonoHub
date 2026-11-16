import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageEncoder {
    enum EncodingError: Error {
        case destinationUnavailable(ExportFormat)
        case finalizeFailed(ExportFormat)
    }

    static func encode(_ image: CGImage, as format: ExportFormat, quality: Double = 1.0) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw EncodingError.destinationUnavailable(format)
        }

        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = min(1.0, max(0.1, quality))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.finalizeFailed(format)
        }
        return data as Data
    }

    @concurrent
    static func encodeInBackground(_ image: CGImage, as format: ExportFormat, quality: Double = 1.0) async throws -> Data {
        try encode(image, as: format, quality: quality)
    }

    @concurrent
    static func write(
        _ image: CGImage,
        as format: ExportFormat,
        quality: Double,
        to url: URL,
        options: Data.WritingOptions = .atomic
    ) async throws {
        try encode(image, as: format, quality: quality).write(to: url, options: options)
    }

    static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext? {
        let space = colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let context = makeContext(width: width, height: height, colorSpace: image.colorSpace) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
