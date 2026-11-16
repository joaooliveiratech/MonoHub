import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MonoHub

@Suite("Image File Loader")
@MainActor
struct ImageFileLoaderTests {
    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("monoshot-\(UUID().uuidString).\(ext)")
    }

    private func writePNG(width: Int, height: Int, dpi: Double, to url: URL) throws {
        let ctx = try #require(ImageEncoder.makeContext(width: width, height: height))
        let image = try #require(ctx.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("Derives the Retina scale from the image resolution")
    func retinaScaleFromDPI() async throws {
        let url = temporaryURL("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 40, height: 20, dpi: 144, to: url)

        let loaded = try await ImageFileLoader.load(url)
        #expect(loaded.image.width == 40)
        #expect(loaded.scaleFactor == 2)
    }

    @Test("Rejects files that are not images")
    func rejectsNonImages() async throws {
        let url = temporaryURL("txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)

        await #expect(throws: ImageFileLoader.LoadError.self) {
            try await ImageFileLoader.load(url)
        }
    }

    @Test("Rejects decompression bombs before decoding them")
    func rejectsOversizedImages() async throws {
        let url = temporaryURL("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 100, height: 100, dpi: 72, to: url)

        await #expect(throws: ImageFileLoader.LoadError.tooLarge) {
            try await ImageFileLoader.load(url, maxPixelCount: 9_999)
        }
    }

    @Test("Keeps only existing files from command line arguments")
    func filtersArguments() throws {
        let url = temporaryURL("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        let urls = ImageFileLoader.fileURLs(fromArguments: ["-NSDocumentRevisionsDebugMode", url.path, "/nonexistent/file.png", NSTemporaryDirectory()])
        #expect(urls == [url.standardizedFileURL])
    }
}
