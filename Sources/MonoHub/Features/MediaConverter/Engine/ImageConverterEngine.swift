import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import AVFoundation

nonisolated enum ImageConverterEngine {
    enum ImageError: LocalizedError {
        case fileNotFound(URL)
        case unsupportedFormat(String)
        case cannotCreateImageSource
        case cannotCreateImageDestination
        case finalizeFailed
        case externalToolFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return String(format: localized("Source file not found: %@"), url.lastPathComponent)
            case .unsupportedFormat(let fmt):
                return String(format: localized("Unsupported image format: %@"), fmt)
            case .cannotCreateImageSource:
                return localized("Could not read original image data.")
            case .cannotCreateImageDestination:
                return localized("Could not create destination file.")
            case .finalizeFailed:
                return localized("Failed to write optimized image data.")
            case .externalToolFailed(let msg):
                return String(format: localized("Conversion utility failure: %@"), msg)
            }
        }
    }

    static func convert(
        sourceURL: URL,
        destinationURL: URL,
        options: ImageConversionOptions,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        let startTime = Date()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ImageError.fileNotFound(sourceURL)
        }

        let originalSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        let parentDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        onProgress(0.1)

        if options.format == .webp {
            try await convertToWebP(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                options: options,
                onProgress: onProgress
            )
        } else {
            try convertWithImageIO(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                options: options,
                onProgress: onProgress
            )
        }

        onProgress(1.0)

        let convertedSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let elapsed = Date().timeIntervalSince(startTime)

        return ConversionResult(
            originalURL: sourceURL,
            outputURL: destinationURL,
            originalSize: originalSize,
            convertedSize: convertedSize,
            durationSeconds: elapsed
        )
    }

    private static func convertWithImageIO(
        sourceURL: URL,
        destinationURL: URL,
        options: ImageConversionOptions,
        onProgress: @Sendable (Double) -> Void
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ImageError.cannotCreateImageSource
        }

        let typeIdentifier = options.format.utTypeIdentifier as CFString

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, typeIdentifier, 1, nil) else {
            throw ImageError.cannotCreateImageDestination
        }

        onProgress(0.3)

        var imageToAdd: CGImage?

        if let maxDim = options.maxDimension, maxDim > 0 {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxDim,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            imageToAdd = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary)
        }

        if imageToAdd == nil {
            imageToAdd = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let finalCGImage = imageToAdd else {
            throw ImageError.cannotCreateImageSource
        }

        onProgress(0.6)

        var destinationProperties: [CFString: Any] = [:]

        if options.format != .png && options.format != .tiff {
            destinationProperties[kCGImageDestinationLossyCompressionQuality] = options.quality as CFNumber
        }

        if !options.stripEXIF {
            if let originalProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                for (key, val) in originalProps {
                    destinationProperties[key] = val
                }
            }
        }

        CGImageDestinationAddImage(destination, finalCGImage, destinationProperties as CFDictionary)

        onProgress(0.8)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.finalizeFailed
        }
    }

    private static func convertToWebP(
        sourceURL: URL,
        destinationURL: URL,
        options: ImageConversionOptions,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        let possibleCwebpPaths = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp", "/usr/bin/cwebp"]
        let cwebpPath = possibleCwebpPaths.first { FileManager.default.isExecutableFile(atPath: $0) }

        if let cwebp = cwebpPath {
            var args = [
                "-q", "\(max(1, min(100, Int(options.quality * 100))))",
                sourceURL.path,
                "-o", destinationURL.path
            ]
            if options.stripEXIF {
                args.append(contentsOf: ["-metadata", "none"])
            }
            if let maxDim = options.maxDimension, maxDim > 0 {
                args.append(contentsOf: ["-resize", "\(maxDim)", "0"])
            }

            onProgress(0.5)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cwebp)
            process.arguments = args

            let pipe = Pipe()
            process.standardError = pipe

            do {
                try await runCancellableProcess(process)
            } catch {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Erro desconhecido"
                throw ImageError.externalToolFailed("cwebp: \(errorMsg)")
            }
            return
        }

        let possibleFfmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let ffmpeg = possibleFfmpegPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            var args = [
                "-y",
                "-i", sourceURL.path,
                "-q:v", "\(max(1, min(100, Int(options.quality * 100))))"
            ]
            if let maxDim = options.maxDimension, maxDim > 0 {
                args.append(contentsOf: ["-vf", "scale='min(\(maxDim),iw)':-1"])
            }
            args.append(destinationURL.path)

            onProgress(0.5)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = args
            do {
                try await runCancellableProcess(process)
            } catch {
                throw ImageError.externalToolFailed(localized("ffmpeg failed to convert to WebP"))
            }
            return
        }

        var fallbackOptions = options
        fallbackOptions.format = .avif
        try convertWithImageIO(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            options: fallbackOptions,
            onProgress: onProgress
        )
    }

    static func convertVideoToGIF(
        sourceURL: URL,
        destinationURL: URL,
        fps: Double = 12.0,
        quality: Double = 0.85,
        maxDimension: Int? = 960,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        let startTime = Date()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ImageError.fileNotFound(sourceURL)
        }
        let originalSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        let parentDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        onProgress(0.1)

        let possibleFfmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let ffmpeg = possibleFfmpegPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            let maxDim = maxDimension ?? 960
            let fpsInt = max(1, min(30, Int(fps.rounded())))
            let vfFilter = "fps=\(fpsInt),scale='min(\(maxDim),iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y",
                "-i", sourceURL.path,
                "-vf", vfFilter,
                destinationURL.path
            ]
            let pipe = Pipe()
            process.standardError = pipe

            do {
                try await runCancellableProcess(process)
                onProgress(1.0)
                let convertedSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                return ConversionResult(
                    originalURL: sourceURL,
                    outputURL: destinationURL,
                    originalSize: originalSize,
                    convertedSize: convertedSize,
                    durationSeconds: Date().timeIntervalSince(startTime)
                )
            } catch {

            }
        }

        let asset = AVURLAsset(url: sourceURL)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            duration = CMTime(seconds: 1.0, preferredTimescale: 600)
        }
        let totalSeconds = max(0.1, CMTimeGetSeconds(duration))
        let frameInterval = 1.0 / max(1.0, fps)
        let frameCount = max(1, Int((totalSeconds * fps).rounded()))

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw ImageError.cannotCreateImageDestination
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameInterval
            ]
        ]

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let maxDim = maxDimension, maxDim > 0 {
            generator.maximumSize = CGSize(width: maxDim, height: maxDim)
        }

        for i in 0..<frameCount {
            let targetTime = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: 600)
            if let image = try? generator.copyCGImage(at: targetTime, actualTime: nil) {
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            onProgress(0.1 + (Double(i) / Double(frameCount)) * 0.8)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.finalizeFailed
        }

        onProgress(1.0)
        let convertedSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ConversionResult(
            originalURL: sourceURL,
            outputURL: destinationURL,
            originalSize: originalSize,
            convertedSize: convertedSize,
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }

    static func runCancellableProcess(_ process: Process) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ProcessExecution", code: Int(proc.terminationStatus)))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
