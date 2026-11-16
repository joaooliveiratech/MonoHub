import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import MonoHub

@Suite("Export & Privacy")
@MainActor
struct ExportPrivacyTests {
    private func noisyImage(width: Int = 160, height: Int = 120, colorSpace: CGColorSpace? = nil) -> CGImage {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        var generator = SystemRandomNumberGenerator()
        for y in 0..<height {
            for x in 0..<width {
                ctx.setFillColor(CGColor(
                    red: .random(in: 0...1, using: &generator),
                    green: .random(in: 0...1, using: &generator),
                    blue: .random(in: 0...1, using: &generator),
                    alpha: 1
                ))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    @Test("Honours the quality setting for every lossy format", arguments: [ExportFormat.jpeg, .heic])
    func lossyQualityIsApplied(format: ExportFormat) throws {
        let image = noisyImage()
        let low = try ImageEncoder.encode(image, as: format, quality: 0.3)
        let high = try ImageEncoder.encode(image, as: format, quality: 1.0)
        #expect(low.count < high.count)
    }

    @Test("Writes the container each format promises", arguments: ExportFormat.allCases)
    func encodedContainerMatchesFormat(format: ExportFormat) throws {
        let data = try ImageEncoder.encode(noisyImage(width: 32, height: 32), as: format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        #expect(UTType(type)?.conforms(to: format.contentType) == true)
    }

    @Test("Exports carry no EXIF, GPS or TIFF device metadata", arguments: ExportFormat.allCases)
    func exportsHaveNoIdentifyingMetadata(format: ExportFormat) throws {
        let data = try ImageEncoder.encode(noisyImage(width: 32, height: 32), as: format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let identifyingExifKeys = [
            kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifUserComment,
            kCGImagePropertyExifLensModel, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifCameraOwnerName
        ]
        #expect(identifyingExifKeys.allSatisfy { exif[$0] == nil })

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff[kCGImagePropertyTIFFSoftware] == nil)
    }

    @Test("Keeps the Display P3 colour space through the composite")
    func compositePreservesWideColor() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let doc = ScreenshotDocument(baseImage: noisyImage(width: 40, height: 40, colorSpace: p3), scaleFactor: 2.0)
        doc.addAnnotation(.rectangle(RectAnnotation(rect: CGRect(x: 2, y: 2, width: 10, height: 10))))
        doc.addAnnotation(.censor(CensorAnnotation(rect: CGRect(x: 4, y: 4, width: 10, height: 10), kind: .pixelate)))

        let composite = try #require(doc.renderCompositeImage())
        #expect(composite.colorSpace?.name == CGColorSpace.displayP3)
        #expect(doc.censoredBaseImage.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test("Resizes to the requested pixel size")
    func resizeProducesRequestedSize() throws {
        let resized = try #require(ImageEncoder.resized(noisyImage(width: 200, height: 100), to: CGSize(width: 50, height: 25)))
        #expect(resized.width == 50)
        #expect(resized.height == 25)
        #expect(ImageEncoder.resized(noisyImage(width: 4, height: 4), to: .zero) == nil)
    }

    @Test("Writes files in the background without leaving partial output")
    func backgroundWriteProducesFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("monoshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try await ImageEncoder.write(noisyImage(width: 20, height: 20), as: .png, quality: 1, to: url)
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
        #expect(rep.pixelsWide == 20)
    }

    @Test("Maps save panel content types back to export formats")
    func contentTypeMapping() {
        for format in ExportFormat.allCases {
            #expect(ExportFormat(contentType: format.contentType) == format)
        }
        #expect(ExportFormat(contentType: .pdf) == nil)
        #expect(ExportFormat.jpeg.isLossy && ExportFormat.heic.isLossy)
        #expect(!ExportFormat.png.isLossy && !ExportFormat.tiff.isLossy)
    }

    @Test("Marks recognised text as concealed so clipboard managers skip it")
    func concealedTextMarker() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MonoHubScreenshotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteboardWriter.write(text: "hunter2", concealed: true, to: pasteboard)
        #expect(pasteboard.types?.contains(PasteboardWriter.concealedType) == true)
        #expect(pasteboard.string(forType: .string) == "hunter2")

        PasteboardWriter.write(text: "#FFFFFF", concealed: false, to: pasteboard)
        #expect(pasteboard.types?.contains(PasteboardWriter.concealedType) == false)
    }

    @Test("Names saved files after the capture time")
    func defaultFileName() {
        let original = Localization.language
        defer { Localization.language = original }

        let date = Date(timeIntervalSince1970: 0)
        Localization.language = .english
        let english = ShotText.defaultFileStem(for: date)
        #expect(english.hasPrefix("Screenshot "))
        #expect(english.contains(" at "))
        #expect(!english.contains("/") && !english.contains(":"))

        Localization.language = .portuguese
        #expect(ShotText.defaultFileStem(for: date).hasPrefix("Captura de Tela "))
        #expect(ShotText.defaultFileStem(for: date).contains(" às "))
    }

    @Test("Censors grayscale images instead of silently keeping the original pixels", arguments: [CensorAnnotation.Kind.blur, .pixelate])
    func censorsGrayscaleImages(kind: CensorAnnotation.Kind) throws {
        let gray = CGColorSpaceCreateDeviceGray()
        let ctx = try #require(CGContext(
            data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
            space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        for x in stride(from: 0, to: 120, by: 4) {
            ctx.setFillColor(gray: x % 8 == 0 ? 0 : 1, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 4, height: 120))
        }
        let doc = ScreenshotDocument(baseImage: try #require(ctx.makeImage()), scaleFactor: 1.0)
        doc.addAnnotation(.censor(CensorAnnotation(rect: CGRect(x: 10, y: 10, width: 100, height: 100), kind: kind)))

        #expect(doc.censoredBaseImage !== doc.baseImage)
        #expect(doc.censoredBaseImage.colorSpace?.model == .rgb)
    }
}
