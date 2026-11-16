import Foundation
import CoreGraphics
import Testing
@testable import MonoHub

@Suite("CaptureRegion")
@MainActor
struct CaptureRegionTests {
    @Test("Normalizes top-left to bottom-right drag")
    func normalizeStandardDrag() {
        let region = CaptureRegion(
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 300, y: 250),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0
        )
        
        #expect(region.normalizedRect.origin.x == 100)
        #expect(region.normalizedRect.origin.y == 100)
        #expect(region.normalizedRect.width == 200)
        #expect(region.normalizedRect.height == 150)
        #expect(region.width == 200)
        #expect(region.height == 150)
        #expect(region.pixelWidth == 400)
        #expect(region.pixelHeight == 300)
        #expect(region.isValid)
    }
    
    @Test("Normalizes reverse drag (bottom-right to top-left)")
    func normalizeReverseDrag() {
        let region = CaptureRegion(
            startPoint: CGPoint(x: 400, y: 300),
            currentPoint: CGPoint(x: 150, y: 100),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0
        )
        
        #expect(region.normalizedRect.origin.x == 150)
        #expect(region.normalizedRect.origin.y == 100)
        #expect(region.normalizedRect.width == 250)
        #expect(region.normalizedRect.height == 200)
    }
    
    @Test("Formats dimension labels correctly")
    func dimensionLabels() {
        let region = CaptureRegion(
            startPoint: CGPoint(x: 0, y: 0),
            currentPoint: CGPoint(x: 800, y: 600),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0
        )
        
        #expect(region.dimensionLabel == "800 × 600 pt")
        #expect(region.pixelDimensionLabel == "1600 × 1200 px")
    }
    
    @Test("Checks validity for micro-selections")
    func validityThreshold() {
        let invalidRegion = CaptureRegion(
            startPoint: CGPoint(x: 50, y: 50),
            currentPoint: CGPoint(x: 51, y: 51),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        #expect(!invalidRegion.isValid)
        
        let validRegion = CaptureRegion(
            startPoint: CGPoint(x: 50, y: 50),
            currentPoint: CGPoint(x: 55, y: 55),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        #expect(validRegion.isValid)
    }
    
    @Test("Calculates pixelCropRect correctly on secondary monitor with local coordinates")
    func secondaryMonitorLocalCrop() {
        let secondaryBounds = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let region = CaptureRegion(
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 500, y: 400),
            displayBounds: secondaryBounds,
            scaleFactor: 2.0
        )
        
        let crop = region.pixelCropRect(imagePixelSize: CGSize(width: 5120, height: 2880))
        #expect(crop.origin.x == 200) // (100 * 2.0)
        #expect(crop.width == 800)   // (400 * 2.0)
        #expect(crop.height == 600)  // (300 * 2.0)
        #expect(crop.origin.y == (1440 - 400) * 2.0) // Y inverted for ScreenCaptureKit
    }
    
    @Test("Does not shift selections past the display origin on a secondary monitor")
    func secondaryMonitorFarSelectionIsNotShifted() {
        let secondaryBounds = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let region = CaptureRegion(
            startPoint: CGPoint(x: 2000, y: 100),
            currentPoint: CGPoint(x: 2400, y: 400),
            displayBounds: secondaryBounds,
            scaleFactor: 2.0
        )

        let crop = region.pixelCropRect(imagePixelSize: CGSize(width: 5120, height: 2880))
        #expect(crop.origin.x == 4000)
        #expect(crop.width == 800)
        #expect(crop.height == 600)
    }

    @Test("Clamps selections that leave the display to the captured image")
    func clampsSelectionToImage() {
        let region = CaptureRegion(
            startPoint: CGPoint(x: -50, y: -40),
            currentPoint: CGPoint(x: 100, y: 60),
            displayBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            scaleFactor: 2.0
        )

        let crop = region.pixelCropRect(imagePixelSize: CGSize(width: 1600, height: 1200))
        #expect(crop.minX == 0)
        #expect(crop.maxY == 1200)
        #expect(crop.width == 200)
        #expect(crop.height == 120)
    }

    @Test("Falls back to a one pixel crop when the selection is fully off screen")
    func offscreenSelectionFallsBack() {
        let region = CaptureRegion(
            startPoint: CGPoint(x: 900, y: 700),
            currentPoint: CGPoint(x: 950, y: 750),
            displayBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            scaleFactor: 2.0
        )

        #expect(region.pixelCropRect(imagePixelSize: CGSize(width: 1600, height: 1200)).size == CGSize(width: 1, height: 1))
    }
}
