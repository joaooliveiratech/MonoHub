import AppKit
import CoreGraphics

nonisolated final class PixelSampler: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<UInt8>
    private let context: CGContext?

    init() {
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        buffer.initialize(repeating: 0, count: 4)
        context = CGContext(
            data: buffer,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    deinit {
        buffer.deallocate()
    }

    func color(in image: CGImage, pixelX: Int, pixelY: Int) -> RGBAColor? {
        guard pixelX >= 0, pixelX < image.width,
              pixelY >= 0, pixelY < image.height,
              let context,
              let cropped = image.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)) else {
            return nil
        }

        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        context.clear(unitRect)
        context.draw(cropped, in: unitRect)

        return RGBAColor(
            r: Double(buffer[0]) / 255.0,
            g: Double(buffer[1]) / 255.0,
            b: Double(buffer[2]) / 255.0,
            a: Double(buffer[3]) / 255.0
        )
    }
}
