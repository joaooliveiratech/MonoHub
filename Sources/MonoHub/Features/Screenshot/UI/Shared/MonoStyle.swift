import AppKit
import QuartzCore
import Synchronization

enum MonoStyle {
    static var accent: NSColor { .controlAccentColor }
    static let dimColor = NSColor(white: 0.0, alpha: 0.38)
    static let handleRadius: CGFloat = 4.5

    static func draw(_ string: NSAttributedString, at point: CGPoint, in ctx: CGContext, flipped: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: flipped)
        string.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func handlePoints(around box: CGRect) -> [CGPoint] {
        [
            CGPoint(x: box.minX, y: box.minY),
            CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.minX, y: box.maxY),
            CGPoint(x: box.maxX, y: box.maxY)
        ]
    }

    static func handlesPath(around box: CGRect, radius: CGFloat = handleRadius) -> CGPath {
        let path = CGMutablePath()
        for point in handlePoints(around: box) {
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }

    static func drawHandles(in ctx: CGContext, around box: CGRect, scale: CGFloat = 1.0) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5 * scale), blur: 2 * scale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(handlesPath(around: box, radius: handleRadius * scale))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.0 * scale)
        ctx.addPath(handlesPath(around: box, radius: handleRadius * scale))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    static func symbol(_ name: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium, description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }
}

enum TextMetrics {
    private struct CacheKey: Hashable, Sendable {
        let text: String
        let fontSize: CGFloat
    }

    private static let cacheLimit = 512
    private static let cache = Mutex<[CacheKey: CGSize]>([:])

    static func font(ofSize size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let key = CacheKey(text: text, fontSize: fontSize)
        if let cached = cache.withLock({ $0[key] }) {
            return cached
        }

        let attributed = NSAttributedString(string: text, attributes: [.font: font(ofSize: fontSize)])
        let measured = attributed.size()
        let padded = CGSize(width: max(24, measured.width), height: max(fontSize, measured.height))

        cache.withLock { store in
            if store.count >= cacheLimit {
                store.removeAll(keepingCapacity: true)
            }
            store[key] = padded
        }
        return padded
    }
}
