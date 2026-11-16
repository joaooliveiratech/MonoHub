import Foundation
import Testing
import CoreGraphics
import ImageIO
@testable import MonoHub

@MainActor
@Suite("Conversor de Mídia (MonoConvert)")
struct MediaConverterTests {

    @Test("Modelos e Perfis de Vídeo correspondem às extensões e presets")
    func videoPresetsConfiguration() {
        #expect(VideoPreset.tablet720p.targetExtension == "mp4")
        #expect(VideoPreset.tablet480p.targetExtension == "mp4")
        #expect(VideoPreset.universal1080p.targetExtension == "mp4")
        #expect(VideoPreset.audioOnly.targetExtension == "m4a")

        #expect(!VideoPreset.tablet720p.exportPresetName.isEmpty)
        #expect(!VideoPreset.tablet480p.exportPresetName.isEmpty)
        #expect(!VideoPreset.universal1080p.exportPresetName.isEmpty)
        #expect(!VideoPreset.audioOnly.exportPresetName.isEmpty)
    }

    @Test("Formatos de Imagem e Identificadores UTType")
    func imageFormatsConfiguration() {
        #expect(ImageFormat.heic.targetExtension == "heic")
        #expect(ImageFormat.avif.targetExtension == "avif")
        #expect(ImageFormat.webp.targetExtension == "webp")
        #expect(ImageFormat.jpeg.targetExtension == "jpg")
        #expect(ImageFormat.png.targetExtension == "png")
        #expect(ImageFormat.tiff.targetExtension == "tiff")

        #expect(ImageFormat.heic.utTypeIdentifier == "public.heic")
        #expect(ImageFormat.avif.utTypeIdentifier == "public.avif")
        #expect(ImageFormat.jpeg.utTypeIdentifier == "public.jpeg")
        #expect(ImageFormat.png.utTypeIdentifier == "public.png")
    }

    @Test("Cálculo de Economia de Espaço (Savings Percentage)")
    func savingsCalculation() {
        let result = ConversionResult(
            originalURL: URL(fileURLWithPath: "/tmp/original.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/converted.mp4"),
            originalSize: 100_000_000, // 100 MB
            convertedSize: 15_000_000,  // 15 MB
            durationSeconds: 2.5
        )

        #expect(result.savedBytes == 85_000_000)
        #expect(result.savingsPercentage == 85.0)
        #expect(result.savingsText == "-85.0%")
    }

    @Test("Detecção de Tipos de Mídia no MediaInspector")
    func mediaInspectorKindDetection() {
        let mp4URL = URL(fileURLWithPath: "/path/video.mp4")
        let movURL = URL(fileURLWithPath: "/path/clip.MOV")
        let mkvURL = URL(fileURLWithPath: "/path/movie.mkv")
        let jpgURL = URL(fileURLWithPath: "/path/photo.JPG")
        let pngURL = URL(fileURLWithPath: "/path/icon.png")
        let heicURL = URL(fileURLWithPath: "/path/shot.heic")
        let txtURL = URL(fileURLWithPath: "/path/readme.txt")

        #expect(MediaInspector.mediaKind(for: mp4URL) == .video)
        #expect(MediaInspector.mediaKind(for: movURL) == .video)
        #expect(MediaInspector.mediaKind(for: mkvURL) == .video)

        #expect(MediaInspector.mediaKind(for: jpgURL) == .image)
        #expect(MediaInspector.mediaKind(for: pngURL) == .image)
        #expect(MediaInspector.mediaKind(for: heicURL) == .image)

        #expect(MediaInspector.mediaKind(for: txtURL) == nil)
        #expect(MediaInspector.isSupported(url: mp4URL))
        #expect(!MediaInspector.isSupported(url: txtURL))
    }

    @Test("Conversão e Compressão Nativa de Imagem para HEIC e JPEG")
    func imageConversionNativeEngine() async throws {
        // Create dummy source image
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("test_input.png")
        let width = 300
        let height = 300
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(sourceURL as CFURL, "public.png" as CFString, 1, nil) else {
            fatalError("Cannot create test image")
        }
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))

        // 1. Convert to HEIC
        let heicOutputURL = tempDir.appendingPathComponent("output.heic")
        let heicOpts = ImageConversionOptions(format: .heic, quality: 0.75, stripEXIF: true)
        let heicResult = try await ImageConverterEngine.convert(
            sourceURL: sourceURL,
            destinationURL: heicOutputURL,
            options: heicOpts
        )

        #expect(FileManager.default.fileExists(atPath: heicOutputURL.path))
        #expect(heicResult.convertedSize > 0)
        #expect(heicResult.originalSize > 0)

        // 2. Convert to JPEG
        let jpegOutputURL = tempDir.appendingPathComponent("output.jpg")
        let jpegOpts = ImageConversionOptions(format: .jpeg, quality: 0.8, stripEXIF: true)
        let jpegResult = try await ImageConverterEngine.convert(
            sourceURL: sourceURL,
            destinationURL: jpegOutputURL,
            options: jpegOpts
        )

        #expect(FileManager.default.fileExists(atPath: jpegOutputURL.path))
        #expect(jpegResult.convertedSize > 0)
    }

    @Test("Fila de Processamento (ConversionQueueManager) e Resolução de Destino")
    func queueManagementAndDestinationResolution() {
        let queue = ConversionQueueManager()
        let sourceURL = URL(fileURLWithPath: "/tmp/sample_video.mov")

        let destURL = queue.resolveDestinationURL(for: sourceURL, targetExtension: "mp4")
        #expect(destURL.lastPathComponent == "sample_video_converted.mp4")
        #expect(destURL.pathExtension == "mp4")

        // Test filtering
        let videoItem = MediaItem(
            fileURL: sourceURL,
            fileSize: 50_000_000,
            kind: .video,
            originalExtension: "mov"
        )
        let imageItem = MediaItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.png"),
            fileSize: 2_000_000,
            kind: .image,
            originalExtension: "png"
        )

        queue.items = [videoItem, imageItem]
        #expect(queue.items.count == 2)

        queue.selectedTab = .videos
        #expect(queue.filteredItems.count == 1)
        #expect(queue.filteredItems.first?.kind == .video)
        #expect(queue.items(for: .videos).count == 1)

        queue.selectedTab = .images
        #expect(queue.filteredItems.count == 1)
        #expect(queue.filteredItems.first?.kind == .image)
        #expect(queue.items(for: .images).count == 1)

        // Remove item
        queue.remove(id: videoItem.id)
        #expect(queue.items.count == 1)
        #expect(queue.items.first?.id == imageItem.id)

        queue.clearAll()
        #expect(queue.items.isEmpty)
    }

    @Test("Integração do Módulo com FeatureManager e SidebarItem")
    func featureManagerIntegration() {
        Localization.language = .portuguese
        #expect(HubFeature.mediaConverter.title == "Conversor de Mídia")
        #expect(HubFeature.mediaConverter.systemImage == "arrow.triangle.2.circlepath")
        #expect(HubFeature.mediaConverter.runsInBackground == false)
        #expect(SidebarItem.mediaConverter.rawValue == "Conversor de Mídia")
        #expect(SidebarItem.mediaConverter.feature == .mediaConverter)
    }
}
