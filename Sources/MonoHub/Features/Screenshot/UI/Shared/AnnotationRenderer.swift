import AppKit
import CoreGraphics

enum AnnotationRenderer {
    static func draw(_ annotations: [AnnotationElement], in ctx: CGContext) {
        for annotation in annotations {
            switch annotation {
            case .arrow(let arrow): drawArrow(arrow, in: ctx)
            case .rectangle(let rect): drawRectangle(rect, in: ctx)
            case .counter(let counter): drawCounter(counter, in: ctx)
            case .text(let text): drawText(text, in: ctx)
            case .censor: break
            }
        }
    }

    static func drawArrow(_ arrow: ArrowAnnotation, in ctx: CGContext) {
        let deltaX = arrow.end.x - (arrow.controlPoint?.x ?? arrow.start.x)
        let deltaY = arrow.end.y - (arrow.controlPoint?.y ?? arrow.start.y)
        let length = hypot(deltaX, deltaY)
        guard length > 4.0 else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let ux = deltaX / length
        let uy = deltaY / length
        let headLength: CGFloat = max(16.0, arrow.strokeWidth * 4.2)
        let headAngle: CGFloat = .pi / 6.5

        let shaftEnd = CGPoint(
            x: arrow.end.x - ux * (headLength * 0.65),
            y: arrow.end.y - uy * (headLength * 0.65)
        )

        ctx.setStrokeColor(arrow.color.cgColor)
        ctx.setLineWidth(arrow.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let path = CGMutablePath()
        path.move(to: arrow.start)
        if let control = arrow.controlPoint {
            path.addQuadCurve(to: shaftEnd, control: control)
        } else {
            path.addLine(to: shaftEnd)
        }
        ctx.addPath(path)
        ctx.strokePath()

        let angle = atan2(deltaY, deltaX)
        let p1 = CGPoint(
            x: arrow.end.x - headLength * cos(angle - headAngle),
            y: arrow.end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: arrow.end.x - headLength * cos(angle + headAngle),
            y: arrow.end.y - headLength * sin(angle + headAngle)
        )

        let headPath = CGMutablePath()
        headPath.move(to: arrow.end)
        headPath.addLine(to: p1)
        headPath.addLine(to: p2)
        headPath.closeSubpath()

        ctx.setFillColor(arrow.color.cgColor)
        ctx.addPath(headPath)
        ctx.fillPath()
    }

    static func drawRectangle(_ rect: RectAnnotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let path = CGPath(
            roundedRect: rect.rect,
            cornerWidth: rect.cornerRadius,
            cornerHeight: rect.cornerRadius,
            transform: nil
        )
        ctx.addPath(path)

        if rect.isFilled {
            ctx.setFillColor(rect.color.cgColor)
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(rect.color.cgColor)
            ctx.setLineWidth(rect.strokeWidth)
            ctx.strokePath()
        }
    }

    static func drawCounter(_ counter: CounterAnnotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let badgeRect = CGRect(
            x: counter.center.x - counter.radius,
            y: counter.center.y - counter.radius,
            width: counter.radius * 2,
            height: counter.radius * 2
        )
        ctx.setFillColor(counter.color.cgColor)
        ctx.fillEllipse(in: badgeRect)

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: badgeRect)

        let font = NSFont.monospacedDigitSystemFont(ofSize: counter.radius * 1.1, weight: .bold)
        let attributed = NSAttributedString(
            string: "\(counter.number)",
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let textSize = attributed.size()
        let origin = CGPoint(
            x: counter.center.x - textSize.width / 2.0,
            y: counter.center.y - textSize.height / 2.0
        )
        MonoStyle.draw(attributed, at: origin, in: ctx)
    }

    static func drawText(_ text: TextAnnotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let attributed = NSAttributedString(
            string: text.text,
            attributes: [
                .font: TextMetrics.font(ofSize: text.fontSize),
                .foregroundColor: NSColor(cgColor: text.color.cgColor) ?? .red
            ]
        )
        MonoStyle.draw(attributed, at: text.origin, in: ctx)
    }
}
