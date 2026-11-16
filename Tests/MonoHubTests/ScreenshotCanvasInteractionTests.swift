import AppKit
import CoreGraphics
import Testing
@testable import MonoHub

@Suite("Canvas Interaction")
@MainActor
struct CanvasInteractionTests {
    private final class Recorder: CanvasViewDelegate {
        var selections: [AnnotationElement?] = []
        var requestedTools: [ToolMode] = []
        var finishedTextEntries = 0

        func canvasView(_ canvas: CanvasView, didSelect element: AnnotationElement?) {
            selections.append(element)
        }

        func canvasViewDidFinishTextEntry(_ canvas: CanvasView) {
            finishedTextEntries += 1
        }

        func canvasView(_ canvas: CanvasView, didRequestTool tool: ToolMode) {
            requestedTools.append(tool)
        }
    }

    private func makeCanvas() -> (CanvasView, ScreenshotDocument, Recorder) {
        let ctx = CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let document = ScreenshotDocument(baseImage: ctx.makeImage()!, scaleFactor: 2.0)
        let canvas = CanvasView(document: document)
        let recorder = Recorder()
        canvas.delegate = recorder
        return (canvas, document, recorder)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private func key(_ keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    private func drag(_ canvas: CanvasView, from start: CGPoint, to end: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, modifiers: modifiers))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, modifiers: modifiers))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, modifiers: modifiers))
    }

    @Test("Draws a rectangle with the active colour and selects it")
    func drawsRectangle() throws {
        let (canvas, document, recorder) = makeCanvas()
        canvas.currentTool = .rectangle
        canvas.currentColor = .blue

        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60))

        let element = try #require(document.annotations.first)
        guard case .rectangle(let rect) = element else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(rect.rect == CGRect(x: 20, y: 20, width: 60, height: 40))
        #expect(rect.color == .blue)
        #expect(canvas.selectedAnnotationId == element.id)
        #expect(recorder.selections.last??.id == element.id)
    }

    @Test("Ignores accidental micro drags")
    func ignoresMicroDrag() {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .arrow
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 22, y: 21))
        #expect(document.annotations.isEmpty)
    }

    @Test("Shift constrains rectangles to squares and arrows to 45° steps")
    func shiftConstrainsShapes() throws {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .rectangle
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 70, y: 30), modifiers: .shift)
        guard case .rectangle(let rect) = try #require(document.annotations.last) else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(rect.rect.width == rect.rect.height)

        canvas.currentTool = .arrow
        drag(canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 108), modifiers: .shift)
        guard case .arrow(let arrow) = try #require(document.annotations.last) else {
            Issue.record("Expected an arrow")
            return
        }
        #expect(abs(arrow.end.y - arrow.start.y) < 0.001)
    }

    @Test("Places censors with the chosen intensity")
    func censorUsesIntensity() throws {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .pixelate
        canvas.censorScale = CensorStrength.strong.scale
        drag(canvas, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 90, y: 90))

        guard case .censor(let censor) = try #require(document.annotations.first) else {
            Issue.record("Expected a censor")
            return
        }
        #expect(censor.kind == .pixelate)
        #expect(censor.scale == CensorStrength.strong.scale)
    }

    @Test("Numbers step badges sequentially")
    func countersIncrement() {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .counter
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 50, y: 50)))

        let numbers = document.annotations.compactMap { element -> Int? in
            if case .counter(let counter) = element { return counter.number }
            return nil
        }
        #expect(numbers == [1, 2])
    }

    @Test("Selects, recolours, moves, deletes and undoes through the canvas")
    func editingRoundTrip() throws {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .rectangle
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 90))
        let id = try #require(document.annotations.first?.id)

        canvas.currentTool = .select
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 20, y: 50)))
        #expect(canvas.selectedAnnotationId == id)

        canvas.applyColorToSelection(.green)
        #expect(document.annotation(withId: id)?.color == .green)

        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 30, y: 60)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 30, y: 60)))
        guard case .rectangle(let moved) = try #require(document.annotation(withId: id)) else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(moved.rect.origin == CGPoint(x: 30, y: 30))

        #expect(canvas.validateMenuItem(NSMenuItem(title: "", action: #selector(CanvasView.delete(_:)), keyEquivalent: "")))
        canvas.keyDown(with: key(ShotKeyCode.delete, characters: "\u{7f}"))
        #expect(document.annotations.isEmpty)
        #expect(canvas.selectedAnnotationId == nil)

        canvas.undo(nil)
        #expect(document.annotation(withId: id) != nil)
        canvas.undo(nil)
        #expect(document.annotation(withId: id)?.color == .green)
        canvas.redo(nil)
        #expect(document.annotations.count == 1)
    }

    @Test("Clears the selection when undo removes the selected element")
    func undoClearsStaleSelection() {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .rectangle
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 90))
        #expect(canvas.selectedAnnotationId != nil)

        canvas.undo(nil)
        #expect(document.annotations.isEmpty)
        #expect(canvas.selectedAnnotationId == nil)
    }

    @Test("Routes digit keys to tool changes and validates undo state")
    func digitKeysRequestTools() {
        let (canvas, _, recorder) = makeCanvas()
        canvas.keyDown(with: key(UInt16(ShotKeyCode.toolKeyCodes.first(where: { $0.value == 4 })!.key), characters: "4"))
        #expect(recorder.requestedTools == [.rectangle])

        #expect(!canvas.validateMenuItem(NSMenuItem(title: "", action: #selector(CanvasView.undo(_:)), keyEquivalent: "")))
        #expect(!canvas.validateMenuItem(NSMenuItem(title: "", action: #selector(CanvasView.redo(_:)), keyEquivalent: "")))
    }

    @Test("Keeps the backdrop in sync with the censored base image")
    func backdropFollowsCensors() {
        let (canvas, document, _) = makeCanvas()
        let backdrop = ScreenshotBackdropView(frame: canvas.bounds)
        canvas.backdrop = backdrop
        canvas.documentDidChange()
        #expect(backdrop.image === document.baseImage)

        canvas.currentTool = .blur
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 90))
        #expect(backdrop.image === document.censoredBaseImage)
        #expect(backdrop.image !== document.baseImage)
    }

    @Test("Undo and redo leave annotations alone while inline text is being typed")
    func undoIsBlockedDuringTextEntry() throws {
        let (canvas, document, _) = makeCanvas()
        canvas.currentTool = .arrow
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 90))

        canvas.currentTool = .text
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 50, y: 150)))
        #expect(canvas.hasActiveInlineText)
        #expect(!canvas.validateMenuItem(NSMenuItem(title: "", action: #selector(CanvasView.undo(_:)), keyEquivalent: "")))

        canvas.undo(nil)
        #expect(document.annotations.count == 1)

        canvas.cancelInlineText()
        #expect(!canvas.hasActiveInlineText)
        canvas.undo(nil)
        #expect(document.annotations.isEmpty)
    }
}
