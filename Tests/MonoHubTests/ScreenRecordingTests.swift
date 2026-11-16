import Foundation
import Testing
import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
@testable import MonoHub

@Suite("Gravação Rápida de Tela (GIF / Micro-Vídeo)")
@MainActor
struct ScreenRecordingTests {

    @Test("Modelos de Formato de Gravação e Extensões")
    func recordingFormatModels() {
        #expect(ScreenRecordingFormat.gif.fileExtension == "gif")
        #expect(ScreenRecordingFormat.mp4.fileExtension == "mp4")
        #expect(ScreenRecordingFormat.webm.fileExtension == "webm")

        #expect(ScreenRecordingFormat.gif.displayName == "GIF")
        #expect(ScreenRecordingFormat.mp4.displayName == "MP4")
        #expect(ScreenRecordingFormat.webm.displayName == "WebM")

        #expect(!ScreenRecordingFormat.gif.iconName.isEmpty)
        #expect(!ScreenRecordingFormat.mp4.iconName.isEmpty)
        #expect(!ScreenRecordingFormat.webm.iconName.isEmpty)
    }

    private func createTestVideo(at url: URL, frameCount: Int = 6, width: Int = 160, height: Int = 120) async throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        func makePixelBuffer(color: (CGFloat, CGFloat, CGFloat)) -> CVPixelBuffer {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            let data = CVPixelBufferGetBaseAddress(pb!)!
            let ctx = CGContext(
                data: data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pb!, [])
            return pb!
        }

        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let pb = makePixelBuffer(color: (CGFloat(i) / CGFloat(frameCount), 0.4, 0.7))
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    @Test("Conversão de Vídeo para GIF Otimizado com ImageConverterEngine")
    func convertVideoToGIF() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceVideo = tempDir.appendingPathComponent("sample_video.mp4")
        try await createTestVideo(at: sourceVideo, frameCount: 6)

        let gifOutput = tempDir.appendingPathComponent("sample_animated.gif")
        let result = try await ImageConverterEngine.convertVideoToGIF(
            sourceURL: sourceVideo,
            destinationURL: gifOutput,
            fps: 10,
            quality: 0.85,
            maxDimension: 160
        )

        #expect(FileManager.default.fileExists(atPath: gifOutput.path))
        #expect(result.convertedSize > 0)
        #expect(result.outputURL == gifOutput)

        // Valida que o GIF é um arquivo válido com múltiplos quadros
        guard let source = CGImageSourceCreateWithURL(gifOutput as CFURL, nil) else {
            Issue.record("Falha ao abrir o GIF gerado como CGImageSource")
            return
        }
        #expect(CGImageSourceGetCount(source) >= 2)
    }

    @Test("Conversão de Vídeo para WebM com VideoConverterEngine")
    func convertVideoToWebM() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceVideo = tempDir.appendingPathComponent("sample_video.mp4")
        try await createTestVideo(at: sourceVideo, frameCount: 6)

        let webmOutput = tempDir.appendingPathComponent("sample_web.webm")
        let result = try await VideoConverterEngine.convertToWebM(
            sourceURL: sourceVideo,
            destinationURL: webmOutput
        )

        #expect(FileManager.default.fileExists(atPath: webmOutput.path))
        #expect(result.convertedSize > 0)
        #expect(result.outputURL == webmOutput)
    }

    @Test("PasteboardWriter suporta URLs de arquivo e dados GIF")
    func pasteboardWriterExtensions() {
        let dummyURL = URL(fileURLWithPath: "/tmp/test.gif")
        let writtenURL = PasteboardWriter.write(fileURL: dummyURL)
        #expect(writtenURL)

        let dummyData = "GIF89a".data(using: .utf8)!
        let writtenData = PasteboardWriter.write(gifData: dummyData)
        #expect(writtenData)
    }

    @Test("Novas opções de captura estão no CaptureRequest e possuem atalhos válidos")
    func captureRequestIntegrations() {
        #expect(CaptureRequest.allCases.contains(.scrolling))
        #expect(CaptureRequest.allCases.contains(.screenRecord))

        #expect(CaptureRequest.scrolling.defaultShortcut == .defaultScrolling)
        #expect(CaptureRequest.screenRecord.defaultShortcut == .defaultRecord)

        #expect(CaptureRequest.scrolling.defaultShortcut.isValidGlobalShortcut)
        #expect(CaptureRequest.screenRecord.defaultShortcut.isValidGlobalShortcut)

        #expect(CaptureRequest.scrolling.urlCommand == "scrolling")
        #expect(CaptureRequest.screenRecord.urlCommand == "record")
    }
}
