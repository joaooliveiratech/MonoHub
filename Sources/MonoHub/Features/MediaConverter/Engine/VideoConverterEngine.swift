import Foundation
import AVFoundation

nonisolated enum VideoConverterEngine {
    enum VideoError: LocalizedError {
        case fileNotFound(URL)
        case cannotCreateExportSession
        case incompatiblePreset(String)
        case exportFailed(String)
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return String(format: localized("Video file not found: %@"), url.lastPathComponent)
            case .cannotCreateExportSession:
                return localized("Could not initialize video export session.")
            case .incompatiblePreset(let p):
                return String(format: localized("The preset '%@' is not compatible with this media tracks."), p)
            case .exportFailed(let reason):
                return String(format: localized("Video conversion failed: %@"), reason)
            case .unsupportedFormat(let fmt):
                return String(format: localized("Video format not natively supported: %@"), fmt)
            }
        }
    }

    static func convert(
        sourceURL: URL,
        destinationURL: URL,
        options: VideoConversionOptions,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        let startTime = Date()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VideoError.fileNotFound(sourceURL)
        }

        let originalSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        let parentDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        onProgress(0.05)

        let ext = sourceURL.pathExtension.lowercased()
        let isNativeContainer = ["mp4", "mov", "m4v"].contains(ext)

        if isNativeContainer {
            do {
                try await convertWithAVFoundation(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    options: options,
                    onProgress: onProgress
                )
            } catch {

                if isFfmpegAvailable() {
                    try await convertWithFfmpeg(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL,
                        options: options,
                        onProgress: onProgress
                    )
                } else {
                    throw error
                }
            }
        } else {

            if isFfmpegAvailable() {
                try await convertWithFfmpeg(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    options: options,
                    onProgress: onProgress
                )
            } else {

                try await convertWithAVFoundation(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    options: options,
                    onProgress: onProgress
                )
            }
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

    private static func convertWithAVFoundation(
        sourceURL: URL,
        destinationURL: URL,
        options: VideoConversionOptions,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let outputFileType: AVFileType = options.preset == .audioOnly ? .m4a : .mp4

        var requestedPreset = options.preset.exportPresetName
        let isCompatible = await AVAssetExportSession.compatibility(ofExportPreset: requestedPreset, with: asset, outputFileType: outputFileType)

        if !isCompatible {
            if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPreset1280x720, with: asset, outputFileType: outputFileType) {
                requestedPreset = AVAssetExportPreset1280x720
            } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetMediumQuality, with: asset, outputFileType: outputFileType) {
                requestedPreset = AVAssetExportPresetMediumQuality
            } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetHighestQuality, with: asset, outputFileType: outputFileType) {
                requestedPreset = AVAssetExportPresetHighestQuality
            } else {
                throw VideoError.incompatiblePreset(options.preset.title)
            }
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: requestedPreset) else {
            throw VideoError.cannotCreateExportSession
        }

        session.shouldOptimizeForNetworkUse = options.fastStart

        do {
            try await session.export(to: destinationURL, as: outputFileType)
            onProgress(1.0)
        } catch {
            throw VideoError.exportFailed(error.localizedDescription)
        }
    }

    private static func isFfmpegAvailable() -> Bool {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func convertWithFfmpeg(
        sourceURL: URL,
        destinationURL: URL,
        options: VideoConversionOptions,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpeg = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw VideoError.exportFailed(localized("ffmpeg not found to transcode this format."))
        }

        var args: [String] = ["-y", "-i", sourceURL.path]

        switch options.preset {
        case .tablet720p:
            args.append(contentsOf: [
                "-c:v", "libx264",
                "-profile:v", "main",
                "-level", "3.1",
                "-pix_fmt", "yuv420p",
                "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2",
                "-crf", "23",
                "-c:a", "aac",
                "-b:a", "128k"
            ])
        case .tablet480p:
            args.append(contentsOf: [
                "-c:v", "libx264",
                "-profile:v", "baseline",
                "-level", "3.0",
                "-pix_fmt", "yuv420p",
                "-vf", "scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2",
                "-crf", "25",
                "-c:a", "aac",
                "-b:a", "96k"
            ])
        case .universal1080p:
            args.append(contentsOf: [
                "-c:v", "libx264",
                "-profile:v", "high",
                "-level", "4.1",
                "-pix_fmt", "yuv420p",
                "-crf", "21",
                "-c:a", "aac",
                "-b:a", "192k"
            ])
        case .webOptimized:
            args.append(contentsOf: [
                "-c:v", "libx264",
                "-crf", "26",
                "-c:a", "aac",
                "-b:a", "128k"
            ])
        case .hevcHighEfficiency:
            args.append(contentsOf: [
                "-c:v", "libx265",
                "-crf", "26",
                "-tag:v", "hvc1",
                "-c:a", "aac",
                "-b:a", "160k"
            ])
        case .audioOnly:
            args.append(contentsOf: [
                "-vn",
                "-c:a", "aac",
                "-b:a", "192k"
            ])
        }

        if options.fastStart && options.preset != .audioOnly {
            args.append(contentsOf: ["-movflags", "+faststart"])
        }

        args.append(destinationURL.path)

        onProgress(0.15)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try await ImageConverterEngine.runCancellableProcess(process)
        } catch {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? localized("ffmpeg error")
            throw VideoError.exportFailed(errorMsg)
        }
    }

    static func convertToWebM(
        sourceURL: URL,
        destinationURL: URL,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        let startTime = Date()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VideoError.fileNotFound(sourceURL)
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y",
                "-i", sourceURL.path,
                "-c:v", "libvpx-vp9",
                "-crf", "32",
                "-b:v", "0",
                "-c:a", "libopus",
                destinationURL.path
            ]
            let pipe = Pipe()
            process.standardError = pipe

            do {
                try await ImageConverterEngine.runCancellableProcess(process)
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

        let tempMP4 = destinationURL.deletingPathExtension().appendingPathExtension("mp4")
        try await convertWithAVFoundation(
            sourceURL: sourceURL,
            destinationURL: tempMP4,
            options: VideoConversionOptions(preset: .webOptimized, fastStart: true),
            onProgress: onProgress
        )
        if tempMP4 != destinationURL {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: tempMP4, to: destinationURL)
        }

        let convertedSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? originalSize
        return ConversionResult(
            originalURL: sourceURL,
            outputURL: destinationURL,
            originalSize: originalSize,
            convertedSize: convertedSize,
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }
}
