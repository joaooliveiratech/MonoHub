import Foundation
import Testing
import CoreGraphics
import AppKit
@testable import MonoHub

@Suite("Captura com Rolagem (Scrolling Capture)")
@MainActor
struct ScrollingCaptureTests {

    private func makeTextImage(offset: Int, xOffset: Int = 10, width: Int = 300, height: Int = 200) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        for i in 0..<30 {
            let str = "Line \(i): Content item \(i * 137)" as NSString
            let y = height - (i * 24 + 20) + offset
            str.draw(at: NSPoint(x: xOffset, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    @Test("Engine inicializa com estado vazio e parâmetros corretos")
    func engineInitialization() {
        let rect = CGRect(x: 50, y: 50, width: 400, height: 300)
        let engine = ScrollingCaptureEngine(targetRect: rect, displayID: 1, scaleFactor: 2.0, maxPixelHeight: 10_000)

        #expect(engine.targetRect == rect)
        #expect(engine.displayID == 1)
        #expect(engine.scaleFactor == 2.0)
        #expect(engine.maxPixelHeight == 10_000)
        #expect(engine.compositeImage == nil)
        #expect(engine.lastFrame == nil)
        #expect(engine.frameCount == 0)
        #expect(engine.currentHeight == 0)
    }

    @Test("Primeiro quadro define a imagem composta base")
    func initialFrameSetsComposite() {
        let engine = ScrollingCaptureEngine(targetRect: CGRect(x: 0, y: 0, width: 300, height: 200), displayID: 1)
        let f0 = makeTextImage(offset: 0)

        let stitched = engine.processFrame(f0)
        #expect(stitched)
        #expect(engine.frameCount == 1)
        #expect(engine.currentHeight == f0.height)
        #expect(engine.compositeImage != nil)
        #expect(engine.lastFrame != nil)
    }

    @Test("Costura quadros sucessivos com aceleração Vision e deslocamento vertical")
    func verticalStitchingWithVision() {
        let engine = ScrollingCaptureEngine(targetRect: CGRect(x: 0, y: 0, width: 300, height: 200), displayID: 1)
        let f0 = makeTextImage(offset: 0)
        let f1 = makeTextImage(offset: 48) // Deslocamento de 48px

        #expect(engine.processFrame(f0))
        let stitched = engine.processFrame(f1)

        #expect(stitched)
        #expect(engine.frameCount == 2)
        #expect(engine.currentHeight > f0.height)
        // O novo tamanho deve corresponder a ~200 + 48 px
        #expect(engine.currentHeight >= 240 && engine.currentHeight <= 260)
    }

    @Test("Rejeita quadros duplicados ou com movimento desprezível (< 2px)")
    func rejectsDuplicateFrames() {
        let engine = ScrollingCaptureEngine(targetRect: CGRect(x: 0, y: 0, width: 300, height: 200), displayID: 1)
        let f0 = makeTextImage(offset: 0)

        engine.processFrame(f0)
        let stitchedDuplicate = engine.processFrame(f0) // Mesmo quadro sem rolagem

        #expect(!stitchedDuplicate)
        #expect(engine.frameCount == 1)
        #expect(engine.currentHeight == f0.height)
    }

    @Test("Rejeita quadros com deriva lateral extrema")
    func rejectsHorizontalDrift() {
        let engine = ScrollingCaptureEngine(targetRect: CGRect(x: 0, y: 0, width: 300, height: 200), displayID: 1)
        let f0 = makeTextImage(offset: 0, xOffset: 10)

        engine.processFrame(f0)

        // Cria imagem com shift horizontal abrupto (deriva lateral acentuada)
        let sidewaysImage = makeTextImage(offset: 30, xOffset: 90)

        let stitched = engine.processFrame(sidewaysImage)
        #expect(!stitched)
        #expect(engine.frameCount == 1)
    }

    @Test("Respeita altura máxima configurada de segurança (clamping)")
    func enforcesMaxPixelHeight() {
        // Define maxPixelHeight baixo para testar interrupção de segurança
        let engine = ScrollingCaptureEngine(
            targetRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            displayID: 1,
            maxPixelHeight: 220
        )
        let f0 = makeTextImage(offset: 0)
        let f1 = makeTextImage(offset: 48)

        engine.processFrame(f0)
        let stitched = engine.processFrame(f1) // 200 + 48 = 248 > 220

        #expect(!stitched)
        #expect(engine.frameCount == 1)
        #expect(engine.currentHeight == 200)
    }

    @Test("Reset limpa todo o estado acumulado")
    func resetClearsState() {
        let engine = ScrollingCaptureEngine(targetRect: CGRect(x: 0, y: 0, width: 300, height: 200), displayID: 1)
        let f0 = makeTextImage(offset: 0)

        engine.processFrame(f0)
        #expect(engine.frameCount == 1)

        engine.reset()
        #expect(engine.compositeImage == nil)
        #expect(engine.lastFrame == nil)
        #expect(engine.frameCount == 0)
        #expect(engine.currentHeight == 0)
    }
}
