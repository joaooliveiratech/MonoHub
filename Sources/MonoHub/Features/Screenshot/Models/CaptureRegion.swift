import Foundation
import CoreGraphics

struct CaptureRegion: Sendable, Equatable {
    var startPoint: CGPoint
    var currentPoint: CGPoint
    var displayBounds: CGRect
    var scaleFactor: CGFloat

    init(startPoint: CGPoint, currentPoint: CGPoint, displayBounds: CGRect, scaleFactor: CGFloat = 2.0) {
        self.startPoint = startPoint
        self.currentPoint = currentPoint
        self.displayBounds = displayBounds
        self.scaleFactor = max(1.0, scaleFactor)
    }

    var normalizedRect: CGRect {
        CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    var width: CGFloat { normalizedRect.width }
    var height: CGFloat { normalizedRect.height }
    var pixelWidth: Int { Int((width * scaleFactor).rounded()) }
    var pixelHeight: Int { Int((height * scaleFactor).rounded()) }

    var isValid: Bool {
        width >= 2 && height >= 2
    }

    var dimensionLabel: String {
        "\(Int(width)) × \(Int(height)) pt"
    }

    var pixelDimensionLabel: String {
        "\(pixelWidth) × \(pixelHeight) px"
    }

    func pixelCropRect(imagePixelSize: CGSize) -> CGRect {
        let selection = normalizedRect.intersection(CGRect(origin: .zero, size: displayBounds.size))
        guard !selection.isNull, !selection.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let topLeftY = displayBounds.height - selection.maxY
        let pixelRect = CGRect(
            x: selection.minX * scaleFactor,
            y: topLeftY * scaleFactor,
            width: selection.width * scaleFactor,
            height: selection.height * scaleFactor
        ).integral

        let imageRect = CGRect(origin: .zero, size: imagePixelSize)
        let clamped = pixelRect.intersection(imageRect)
        return clamped.isNull || clamped.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : clamped
    }
}
