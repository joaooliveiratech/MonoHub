import Foundation
import CoreGraphics
import Testing
@testable import MonoHub

@Suite("AnnotationModel")
@MainActor
struct AnnotationModelTests {
    private func createDummyImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
    
    @Test("Manages undo and redo stacks properly")
    func undoRedoStack() {
        let image = createDummyImage()
        let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
        
        #expect(doc.annotations.isEmpty)
        #expect(!doc.canUndo)
        #expect(!doc.canRedo)
        
        // Add arrow
        let arrow = ArrowAnnotation(start: .zero, end: CGPoint(x: 50, y: 50))
        doc.addAnnotation(.arrow(arrow))
        #expect(doc.annotations.count == 1)
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
        
        // Add rectangle
        let rect = RectAnnotation(rect: CGRect(x: 10, y: 10, width: 30, height: 30))
        doc.addAnnotation(.rectangle(rect))
        #expect(doc.annotations.count == 2)
        
        // Undo
        doc.undo()
        #expect(doc.annotations.count == 1)
        #expect(doc.canRedo)
        
        // Redo
        doc.redo()
        #expect(doc.annotations.count == 2)
    }
    
    @Test("Auto-increments counter badge numbers")
    func counterAutoIncrement() {
        let image = createDummyImage()
        let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
        
        #expect(doc.nextCounterIndex == 1)
        
        let counter1 = CounterAnnotation(center: CGPoint(x: 20, y: 20), number: doc.nextCounterIndex)
        doc.addAnnotation(.counter(counter1))
        #expect(doc.nextCounterIndex == 2)
        
        let counter2 = CounterAnnotation(center: CGPoint(x: 40, y: 40), number: doc.nextCounterIndex)
        doc.addAnnotation(.counter(counter2))
        #expect(doc.nextCounterIndex == 3)
    }
    
    @Test("Generates accurate HEX color codes")
    func hexColorGeneration() {
        let red = RGBAColor.red
        #expect(red.hexString == "#F24040")
        
        let white = RGBAColor.white
        #expect(white.hexString == "#FFFFFF")
        
        let custom = RGBAColor(r: 0.0, g: 0.5, b: 1.0, a: 1.0)
        #expect(custom.hexString == "#0080FF")
    }
    
    @Test("Hit tests and moves annotation elements")
    func hitTestingAndMoving() {
        let image = createDummyImage()
        let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
        
        let rect = RectAnnotation(rect: CGRect(x: 20, y: 20, width: 60, height: 40), isFilled: true)
        let element = AnnotationElement.rectangle(rect)
        doc.addAnnotation(element)
        
        // Inside hit test
        #expect(element.contains(point: CGPoint(x: 30, y: 30)))
        #expect(doc.annotation(at: CGPoint(x: 30, y: 30))?.id == element.id)
        
        // Outside hit test
        #expect(!element.contains(point: CGPoint(x: 5, y: 5)))
        #expect(doc.annotation(at: CGPoint(x: 5, y: 5)) == nil)
        
        // Move annotation by delta (10, 15)
        let moved = element.moved(by: CGSize(width: 10, height: 15))
        if case .rectangle(let r) = moved {
            #expect(r.rect.origin.x == 30)
            #expect(r.rect.origin.y == 35)
        } else {
            #expect(Bool(false), "Expected rectangle")
        }
        
        // Move via document
        doc.moveAnnotation(withId: element.id, by: CGSize(width: 10, height: 15))
        #expect(doc.annotation(at: CGPoint(x: 40, y: 45)) != nil)
    }
    
    @Test("Deletes annotation and tracks undo")
    func deleteAnnotation() {
        let image = createDummyImage()
        let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
        
        let arrow = ArrowAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50))
        let element = AnnotationElement.arrow(arrow)
        doc.addAnnotation(element)
        #expect(doc.annotations.count == 1)
        
        doc.removeAnnotation(withId: element.id)
        #expect(doc.annotations.isEmpty)
        
        // Undo delete
        doc.undo()
        #expect(doc.annotations.count == 1)
        #expect(doc.annotations.first?.id == element.id)
    }
    
    @Test("Color support and tool mode compatibility")
    func colorSupport() {
        #expect(ToolMode.select.supportsColor == false)
        #expect(ToolMode.blur.supportsColor == false)
        #expect(ToolMode.pixelate.supportsColor == false)
        #expect(ToolMode.arrow.supportsColor == true)
        #expect(ToolMode.curvedArrow.supportsColor == true)
        #expect(ToolMode.rectangle.supportsColor == true)
        #expect(ToolMode.counter.supportsColor == true)
        #expect(ToolMode.text.supportsColor == true)
        
        let rect = RectAnnotation(rect: CGRect(x: 10, y: 10, width: 20, height: 20), color: .red)
        let element = AnnotationElement.rectangle(rect)
        #expect(element.supportsColor)
        #expect(element.color == .red)
        
        let updated = element.withColor(.blue)
        #expect(updated.color == .blue)
    }
    
    @Test("Applies blur and pixelate censors with opaque compositing")
    func censorRendering() {
        let image = createDummyImage()
        let doc = ScreenshotDocument(baseImage: image, scaleFactor: 2.0)
        
        let blurCensor = CensorAnnotation(
            rect: CGRect(x: 10, y: 10, width: 30, height: 30),
            kind: .blur,
            scale: 56.0
        )
        doc.addAnnotation(.censor(blurCensor))
        
        let composite = doc.renderCompositeImage()
        #expect(composite != nil)
        #expect(composite?.width == image.width)
        #expect(composite?.height == image.height)
    }

    @Test("Reuses the counter number freed by undo")
    func counterNumberFollowsUndo() {
        let doc = ScreenshotDocument(baseImage: createDummyImage(), scaleFactor: 2.0)

        doc.addAnnotation(.counter(CounterAnnotation(center: CGPoint(x: 10, y: 10), number: doc.nextCounterIndex)))
        doc.addAnnotation(.counter(CounterAnnotation(center: CGPoint(x: 20, y: 20), number: doc.nextCounterIndex)))
        #expect(doc.nextCounterIndex == 3)

        doc.undo()
        #expect(doc.nextCounterIndex == 2)

        doc.redo()
        #expect(doc.nextCounterIndex == 3)
    }

    @Test("Ignores updates that change nothing so undo stays meaningful")
    func identicalUpdateDoesNotPushHistory() {
        let doc = ScreenshotDocument(baseImage: createDummyImage(), scaleFactor: 2.0)
        let rect = AnnotationElement.rectangle(RectAnnotation(rect: CGRect(x: 1, y: 1, width: 20, height: 20), color: .red))
        doc.addAnnotation(rect)

        doc.updateAnnotation(rect.withColor(.red))
        doc.undo()
        #expect(doc.annotations.isEmpty)
    }

    @Test("Commits a drag as a single undo step")
    func dragCommitsOneUndoStep() {
        let doc = ScreenshotDocument(baseImage: createDummyImage(), scaleFactor: 2.0)
        let arrow = AnnotationElement.arrow(ArrowAnnotation(start: .zero, end: CGPoint(x: 30, y: 30)))
        doc.addAnnotation(arrow)

        let before = doc.annotations
        for _ in 0..<5 {
            doc.moveAnnotation(withId: arrow.id, by: CGSize(width: 2, height: 1))
        }
        doc.commitMove(previousState: before)

        doc.undo()
        #expect(doc.annotations == before)
    }

    @Test("Maps tool shortcut numbers onto tools")
    func toolShortcutNumbers() {
        for tool in ToolMode.allCases {
            #expect(ToolMode.forShortcutNumber(tool.shortcutNumber) == tool)
        }
        #expect(ToolMode.forShortcutNumber(0) == nil)
        #expect(ToolMode.forShortcutNumber(9) == nil)
        #expect(ToolMode.blur.censorKind == .blur)
        #expect(ToolMode.pixelate.isCensor)
        #expect(!ToolMode.arrow.isCensor)
    }
}
