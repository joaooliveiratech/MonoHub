import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MonoHub

@Suite("Rendering & Export")
@MainActor
struct RenderingTests {
    private func makeImage(width: Int = 200, height: Int = 120) -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    @Test("Infers the export format from the file extension")
    func exportFormatInference() {
        #expect(ExportFormat.inferred(fromExtension: "png") == .png)
        #expect(ExportFormat.inferred(fromExtension: "JPG") == .jpeg)
        #expect(ExportFormat.inferred(fromExtension: "jpeg") == .jpeg)
        #expect(ExportFormat.inferred(fromExtension: "tif") == .tiff)
        #expect(ExportFormat.inferred(fromExtension: "heic") == .heic)
        #expect(ExportFormat.inferred(fromExtension: "webp") == .png)
        #expect(ExportFormat.jpeg.fileExtension == "jpg")
    }

    @Test("Measures text bounds with real font metrics")
    func textBoundsUseFontMetrics() {
        let short = TextAnnotation(origin: .zero, text: "Oi", fontSize: 18)
        let long = TextAnnotation(origin: .zero, text: "Uma frase bem mais longa", fontSize: 18)

        let shortBox = AnnotationElement.text(short).boundingBox
        let longBox = AnnotationElement.text(long).boundingBox

        #expect(shortBox.width < longBox.width)
        #expect(shortBox.height > 0)

        // Wide glyphs must not be under-measured the way a character count would
        let emoji = AnnotationElement.text(TextAnnotation(origin: .zero, text: "🙂🙂", fontSize: 18))
        #expect(emoji.boundingBox.width > shortBox.width / 2)
        #expect(emoji.contains(point: CGPoint(x: 4, y: 6)))
    }

    @Test("Caps the undo history instead of growing without bound")
    func historyIsCapped() {
        let doc = ScreenshotDocument(baseImage: makeImage(), scaleFactor: 2.0)

        for index in 0..<60 {
            doc.addAnnotation(.counter(CounterAnnotation(center: CGPoint(x: index, y: index), number: index)))
        }
        #expect(doc.annotations.count == 60)

        var undoCount = 0
        while doc.canUndo {
            doc.undo()
            undoCount += 1
        }
        #expect(undoCount == 50)
        #expect(doc.annotations.count == 10)
    }

    @Test("Reuses the censored base image until a censor changes")
    func censoredBaseIsCached() {
        let doc = ScreenshotDocument(baseImage: makeImage(), scaleFactor: 2.0)

        // No censors: the untouched screenshot is handed back as-is
        #expect(doc.censoredBaseImage === doc.baseImage)

        doc.addAnnotation(.arrow(ArrowAnnotation(start: .zero, end: CGPoint(x: 40, y: 40))))
        #expect(doc.censoredBaseImage === doc.baseImage)

        doc.addAnnotation(.censor(CensorAnnotation(rect: CGRect(x: 5, y: 5, width: 30, height: 20), kind: .pixelate)))
        let censored = doc.censoredBaseImage
        #expect(censored !== doc.baseImage)

        // A vector annotation must not invalidate the CoreImage pass
        doc.addAnnotation(.rectangle(RectAnnotation(rect: CGRect(x: 1, y: 1, width: 10, height: 10))))
        #expect(doc.censoredBaseImage === censored)
    }

    private func stripedImage(width: Int, height: Int, stripe: Int) -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: width, by: stripe * 2) {
            ctx.fill(CGRect(x: x, y: 0, width: stripe, height: height))
        }
        return ctx.makeImage()!
    }

    /// Mean absolute difference between neighbouring pixels: it measures the
    /// fine detail a censor must destroy, without punishing a coarse mosaic for
    /// having differently coloured blocks.
    private func detailEnergy(of image: CGImage, in rect: CGRect) -> Double {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var total = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<(Int(rect.maxX) - 1) {
                let left = Double(bytes[(y * width + x) * 4])
                let right = Double(bytes[(y * width + x + 1) * 4])
                total += abs(right - left)
                count += 1
            }
        }
        return total / Double(count)
    }

    @Test("Destroys fine detail at every censor strength", arguments: [CensorAnnotation.Kind.blur, .pixelate])
    func censorsDestroyDetail(kind: CensorAnnotation.Kind) {
        let image = stripedImage(width: 400, height: 200, stripe: 4)
        // The censored rect covers pixels (40,40)-(160,160); sample well inside it.
        let sample = CGRect(x: 60, y: 60, width: 80, height: 80)
        let original = detailEnergy(of: image, in: sample)
        #expect(original > 50)

        // A mosaic keeps hard block boundaries on purpose, so it is allowed a
        // slightly higher residual than the smooth blur.
        let allowedFraction = kind == .blur ? 20.0 : 15.0

        for strength in CensorStrength.allCases {
            let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
            doc.addAnnotation(.censor(CensorAnnotation(
                rect: CGRect(x: 20, y: 20, width: 60, height: 60),
                kind: kind,
                scale: strength.scale
            )))

            let residual = detailEnergy(of: doc.censoredBaseImage, in: sample)
            #expect(
                residual < original / allowedFraction,
                "\(kind) at \(strength.displayName) left too much detail: \(residual)"
            )
        }
    }

    @Test("Scales censor granularity with the selected strength")
    func censorGranularityGrowsWithStrength() {
        let minSide: CGFloat = 600

        let blocks = CensorStrength.allCases.map {
            ScreenshotDocument.censorBlockSize(scale: $0.scale, scaleFactor: 2.0, minSide: minSide)
        }
        #expect(blocks == blocks.sorted())
        #expect(blocks.first! >= 8)

        let factors = CensorStrength.allCases.map {
            ScreenshotDocument.censorBlurFactor(scale: $0.scale, scaleFactor: 2.0, minSide: minSide)
        }
        #expect(factors == factors.sorted())
        #expect(factors.first! >= 4)

        // Tiny selections must not ask for a block larger than the selection
        let tiny = ScreenshotDocument.censorBlockSize(scale: CensorStrength.strong.scale, scaleFactor: 2.0, minSide: 30)
        #expect(tiny <= 10)
    }

    @Test("Caches the flattened composite until annotations change")
    func compositeIsCached() {
        let doc = ScreenshotDocument(baseImage: makeImage(), scaleFactor: 2.0)

        let first = doc.renderCompositeImage()
        #expect(first != nil)
        #expect(doc.renderCompositeImage() === first)

        doc.addAnnotation(.counter(CounterAnnotation(center: CGPoint(x: 20, y: 20), number: 1)))
        #expect(doc.renderCompositeImage() !== first)
    }

    @Test("Saves image with explicit format even if extension differs")
    func saveWithExplicitFormat() throws {
        let doc = ScreenshotDocument(baseImage: makeImage(width: 50, height: 50), scaleFactor: 1.0)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).data")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try doc.save(to: tempURL, format: .jpeg)
        let data = try Data(contentsOf: tempURL)
        // JPEG magic bytes: 0xFF, 0xD8
        #expect(data.count > 4)
        #expect(data[0] == 0xFF && data[1] == 0xD8)

        let pngURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).data")
        defer { try? FileManager.default.removeItem(at: pngURL) }

        try doc.save(to: pngURL, format: .png)
        let pngData = try Data(contentsOf: pngURL)
        // PNG magic bytes: 0x89, 0x50, 0x4E, 0x47 ('\x89PNG')
        #expect(pngData.count > 8)
        #expect(pngData[0] == 0x89 && pngData[1] == 0x50 && pngData[2] == 0x4E && pngData[3] == 0x47)
    }

    @Test("ScreenshotPreferences updates last used directory properly")
    func preferencesSaveDirectory() {
        let suite = "com.antigravity.monohub.tests.screenshot.rendering"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = ScreenshotPreferences(defaults: defaults)

        prefs.saveLocationMode = .lastUsed
        let testDir = NSTemporaryDirectory()
        prefs.updateLastSaveDirectory(testDir)
        #expect(prefs.lastUsedSaveDirectory == testDir)
        #expect(prefs.effectiveSaveDirectory == testDir)
    }

    @Test("Downscales Retina screenshots when downscaleRetina is enabled")
    func downscaleRetinaExport() throws {
        // Base image: 200x100 at 2x scale = 100x50 logical
        let doc = ScreenshotDocument(baseImage: makeImage(width: 200, height: 100), scaleFactor: 2.0)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try doc.save(to: tempURL, format: .png, downscaleRetina: true)
        let data = try Data(contentsOf: tempURL)
        let imgRep = NSBitmapImageRep(data: data)
        #expect(imgRep != nil)
        #expect(imgRep?.pixelsWide == 100)
        #expect(imgRep?.pixelsHigh == 50)
    }

    @Test("KeyShortcut formats display string properly")
    func keyShortcutDisplay() {
        #expect(KeyShortcut.defaultArea.displayString == "⇧⌘1")
        #expect(KeyShortcut.defaultFullscreen.displayString == "⇧⌘2")
        #expect(KeyShortcut.defaultWindow.displayString == "⇧⌘3")
        #expect(KeyShortcut.defaultOCR.displayString == "⇧⌘O")
    }
}
