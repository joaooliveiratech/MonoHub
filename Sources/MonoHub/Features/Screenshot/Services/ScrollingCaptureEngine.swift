import Foundation
import CoreGraphics
import Vision

@MainActor
protocol ScrollingCaptureEngineDelegate: AnyObject {
    func scrollingEngineDidUpdate(height: Int, frameCount: Int, previewImage: CGImage?)
    func scrollingEngineDidReachMaxHeight()
}

final class ScrollingCaptureEngine: @unchecked Sendable {
    weak var delegate: (any ScrollingCaptureEngineDelegate)?

    let targetRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat
    let maxPixelHeight: Int

    private(set) var compositeImage: CGImage?
    private(set) var lastFrame: CGImage?
    private(set) var frameCount: Int = 0
    private(set) var currentHeight: Int = 0

    init(
        targetRect: CGRect,
        displayID: CGDirectDisplayID,
        scaleFactor: CGFloat = 2.0,
        maxPixelHeight: Int = 32_000
    ) {
        self.targetRect = targetRect
        self.displayID = displayID
        self.scaleFactor = max(1.0, scaleFactor)
        self.maxPixelHeight = maxPixelHeight
    }

    @discardableResult
    func processFrame(_ newFrame: CGImage) -> Bool {
        guard let currentLast = lastFrame, let currentComp = compositeImage else {
            compositeImage = newFrame
            lastFrame = newFrame
            frameCount = 1
            currentHeight = newFrame.height
            Task { @MainActor in
                self.delegate?.scrollingEngineDidUpdate(
                    height: self.currentHeight,
                    frameCount: self.frameCount,
                    previewImage: self.compositeImage
                )
            }
            return true
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: newFrame, options: [:])
        let handler = VNImageRequestHandler(cgImage: currentLast, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }

        guard let observation = request.results?.first else {
            return false
        }

        let transform = observation.alignmentTransform

        if abs(transform.tx) > max(20.0, CGFloat(newFrame.width) * 0.08) {
            return false
        }

        let scrollDistance = -transform.ty
        guard scrollDistance >= 2.0 else {

            return false
        }

        guard scrollDistance < CGFloat(newFrame.height) * 0.92 else {
            return false
        }

        let dy = Int(scrollDistance.rounded())
        let newTotalHeight = currentComp.height + dy

        if newTotalHeight > maxPixelHeight {
            Task { @MainActor in
                self.delegate?.scrollingEngineDidReachMaxHeight()
            }
            return false
        }

        let width = currentComp.width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: newTotalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        ctx.draw(currentComp, in: CGRect(x: 0, y: dy, width: width, height: currentComp.height))

        ctx.draw(newFrame, in: CGRect(x: 0, y: 0, width: width, height: newFrame.height))

        guard let updatedComposite = ctx.makeImage() else {
            return false
        }

        self.compositeImage = updatedComposite
        self.lastFrame = newFrame
        self.frameCount += 1
        self.currentHeight = newTotalHeight

        Task { @MainActor in
            self.delegate?.scrollingEngineDidUpdate(
                height: self.currentHeight,
                frameCount: self.frameCount,
                previewImage: self.compositeImage
            )
        }
        return true
    }

    func reset() {
        compositeImage = nil
        lastFrame = nil
        frameCount = 0
        currentHeight = 0
    }
}
