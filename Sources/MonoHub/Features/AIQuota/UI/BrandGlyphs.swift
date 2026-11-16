import AppKit

@MainActor
enum OfficialBrandIcons {

    static let claude = template(width: 14, height: 14) { context in
        let center = CGPoint(x: 7.0, y: 7.0)
        let rayCount = 12

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineCap(.round)

        for ray in 0..<rayCount {
            let angle = (CGFloat(ray) / CGFloat(rayCount)) * 2.0 * .pi + .pi / 12.0
            let isLong = ray.isMultiple(of: 2)

            context.setLineWidth(isLong ? 1.15 : 1.0)
            context.move(to: CGPoint(
                x: center.x,
                y: center.y
            ))
            context.addLine(to: CGPoint(
                x: center.x + (isLong ? 6.4 : 5.3) * cos(angle),
                y: center.y + (isLong ? 6.4 : 5.3) * sin(angle)
            ))
            context.strokePath()
        }
    }

    static let antigravity = template(width: 14, height: 13) { context in
        let path = CGMutablePath()

        path.move(to: CGPoint(x: 1.5, y: 1.9))
        path.addCurve(
            to: CGPoint(x: 7.0, y: 12.1),
            control1: CGPoint(x: 2.6, y: 6.2),
            control2: CGPoint(x: 4.3, y: 12.1)
        )
        path.addCurve(
            to: CGPoint(x: 12.5, y: 1.9),
            control1: CGPoint(x: 9.7, y: 12.1),
            control2: CGPoint(x: 11.4, y: 6.2)
        )

        path.addQuadCurve(
            to: CGPoint(x: 10.6, y: 1.9),
            control: CGPoint(x: 11.8, y: 0.5)
        )

        path.addCurve(
            to: CGPoint(x: 7.0, y: 5.9),
            control1: CGPoint(x: 10.0, y: 4.0),
            control2: CGPoint(x: 8.7, y: 5.9)
        )
        path.addCurve(
            to: CGPoint(x: 3.4, y: 1.9),
            control1: CGPoint(x: 5.3, y: 5.9),
            control2: CGPoint(x: 4.0, y: 4.0)
        )

        path.addQuadCurve(
            to: CGPoint(x: 1.5, y: 1.9),
            control: CGPoint(x: 2.2, y: 0.5)
        )
        path.closeSubpath()

        context.setFillColor(NSColor.black.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    static let codex = template(width: 13, height: 13) { context in
        let center = CGPoint(x: 6.5, y: 6.5)
        let radius: CGFloat = 5.3

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.95)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        func point(_ angle: CGFloat, _ scale: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * scale * cos(angle), y: center.y + radius * scale * sin(angle))
        }

        for strand in 0..<6 {
            let angle = CGFloat(strand) * .pi / 3.0
            let path = CGMutablePath()
            path.move(to: point(angle - 0.30, 0.22))
            path.addCurve(
                to: point(angle, 0.98),
                control1: point(angle - 0.62, 0.72),
                control2: point(angle - 0.40, 1.02)
            )
            path.addCurve(
                to: point(angle + 0.30, 0.22),
                control1: point(angle + 0.40, 1.02),
                control2: point(angle + 0.62, 0.72)
            )
            context.addPath(path)
            context.strokePath()
        }
    }

    static let deepseek = template(width: 15, height: 12) { context in
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 1.0, y: 5.6))
        body.addCurve(to: CGPoint(x: 7.6, y: 10.6), control1: CGPoint(x: 1.2, y: 8.9), control2: CGPoint(x: 4.4, y: 10.8))
        body.addCurve(to: CGPoint(x: 12.1, y: 7.6), control1: CGPoint(x: 9.9, y: 10.4), control2: CGPoint(x: 11.3, y: 9.2))
        body.addLine(to: CGPoint(x: 14.2, y: 10.4))
        body.addCurve(to: CGPoint(x: 13.2, y: 5.4), control1: CGPoint(x: 14.6, y: 8.6), control2: CGPoint(x: 14.3, y: 6.6))
        body.addCurve(to: CGPoint(x: 7.2, y: 1.4), control1: CGPoint(x: 12.2, y: 2.9), control2: CGPoint(x: 9.9, y: 1.4))
        body.addCurve(to: CGPoint(x: 1.0, y: 5.6), control1: CGPoint(x: 3.8, y: 1.4), control2: CGPoint(x: 1.0, y: 2.9))
        body.closeSubpath()
        body.addEllipse(in: CGRect(x: 3.3, y: 5.7, width: 1.5, height: 1.5))

        context.setFillColor(NSColor.black.cgColor)
        context.addPath(body)
        context.fillPath(using: .evenOdd)
    }

    static let kimi = template(width: 13, height: 13) { context in
        let glyph = CGMutablePath()
        glyph.addRoundedRect(in: CGRect(x: 1.6, y: 1.2, width: 2.5, height: 10.4), cornerWidth: 0.9, cornerHeight: 0.9)
        glyph.move(to: CGPoint(x: 4.1, y: 5.4))
        glyph.addLine(to: CGPoint(x: 8.2, y: 10.6))
        glyph.addLine(to: CGPoint(x: 11.2, y: 10.6))
        glyph.addLine(to: CGPoint(x: 6.6, y: 5.0))
        glyph.addLine(to: CGPoint(x: 11.4, y: 1.2))
        glyph.addLine(to: CGPoint(x: 8.2, y: 1.2))
        glyph.addLine(to: CGPoint(x: 4.1, y: 4.6))
        glyph.closeSubpath()
        glyph.addEllipse(in: CGRect(x: 9.6, y: 9.4, width: 2.6, height: 2.6))

        context.setFillColor(NSColor.black.cgColor)
        context.addPath(glyph)
        context.fillPath()
    }

    static let zai = template(width: 13, height: 13) { context in
        let glyph = CGMutablePath()
        glyph.move(to: CGPoint(x: 1.8, y: 11.6))
        glyph.addLine(to: CGPoint(x: 11.4, y: 11.6))
        glyph.addLine(to: CGPoint(x: 11.4, y: 9.6))
        glyph.addLine(to: CGPoint(x: 5.0, y: 3.4))
        glyph.addLine(to: CGPoint(x: 11.4, y: 3.4))
        glyph.addLine(to: CGPoint(x: 11.4, y: 1.4))
        glyph.addLine(to: CGPoint(x: 1.6, y: 1.4))
        glyph.addLine(to: CGPoint(x: 1.6, y: 3.4))
        glyph.addLine(to: CGPoint(x: 8.0, y: 9.6))
        glyph.addLine(to: CGPoint(x: 1.8, y: 9.6))
        glyph.closeSubpath()

        context.setFillColor(NSColor.black.cgColor)
        context.addPath(glyph)
        context.fillPath()
    }

    static let copilot = template(width: 14, height: 14) { context in
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 1.5, y: 3.0, width: 11.0, height: 8.0), cornerWidth: 2.5, cornerHeight: 2.5)
        path.move(to: CGPoint(x: 4.5, y: 11.0))
        path.addLine(to: CGPoint(x: 3.0, y: 13.0))
        path.move(to: CGPoint(x: 9.5, y: 11.0))
        path.addLine(to: CGPoint(x: 11.0, y: 13.0))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        context.addPath(path)
        context.strokePath()

        let visor = CGMutablePath()
        visor.addRoundedRect(in: CGRect(x: 3.5, y: 5.5, width: 7.0, height: 3.0), cornerWidth: 1.0, cornerHeight: 1.0)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(visor)
        context.fillPath()
    }

    static let cursor = template(width: 14, height: 14) { context in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2.0, y: 12.5))
        path.addLine(to: CGPoint(x: 2.0, y: 2.0))
        path.addLine(to: CGPoint(x: 9.5, y: 8.5))
        path.addLine(to: CGPoint(x: 5.8, y: 8.8))
        path.addLine(to: CGPoint(x: 8.2, y: 13.0))
        path.addLine(to: CGPoint(x: 6.2, y: 14.0))
        path.addLine(to: CGPoint(x: 4.0, y: 9.5))
        path.closeSubpath()
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    static let openrouter = template(width: 14, height: 14) { context in
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.1)
        context.strokeEllipse(in: CGRect(x: 2.0, y: 2.0, width: 10.0, height: 10.0))
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: 5.5, y: 5.5, width: 3.0, height: 3.0))
        context.fillEllipse(in: CGRect(x: 8.5, y: 8.5, width: 2.2, height: 2.2))
        context.fillEllipse(in: CGRect(x: 3.3, y: 8.5, width: 2.2, height: 2.2))
    }

    static let grok = template(width: 14, height: 14) { context in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2.0, y: 12.0))
        path.addLine(to: CGPoint(x: 12.0, y: 2.0))
        path.move(to: CGPoint(x: 12.0, y: 12.0))
        path.addLine(to: CGPoint(x: 7.5, y: 7.5))
        path.move(to: CGPoint(x: 6.5, y: 6.5))
        path.addLine(to: CGPoint(x: 2.0, y: 2.0))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.square)
        context.addPath(path)
        context.strokePath()
    }

    static let supergrok = template(width: 14, height: 14) { context in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2.0, y: 12.0))
        path.addLine(to: CGPoint(x: 12.0, y: 2.0))
        path.move(to: CGPoint(x: 12.0, y: 12.0))
        path.addLine(to: CGPoint(x: 2.0, y: 2.0))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.addPath(path)
        context.strokePath()

        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: 5.0, y: 5.0, width: 4.0, height: 4.0))
    }

    static let commandcode = template(width: 14, height: 14) { context in
        let prompt = CGMutablePath()
        prompt.move(to: CGPoint(x: 2.0, y: 10.5))
        prompt.addLine(to: CGPoint(x: 6.0, y: 7.0))
        prompt.addLine(to: CGPoint(x: 2.0, y: 3.5))
        prompt.move(to: CGPoint(x: 8.0, y: 3.5))
        prompt.addLine(to: CGPoint(x: 12.0, y: 3.5))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.addPath(prompt)
        context.strokePath()
    }

    static let nous = template(width: 14, height: 14) { context in
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 2.0, y: 4.0, width: 4.5, height: 6.5))
        path.addEllipse(in: CGRect(x: 7.5, y: 4.0, width: 4.5, height: 6.5))
        path.move(to: CGPoint(x: 4.0, y: 7.0))
        path.addLine(to: CGPoint(x: 10.0, y: 7.0))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.1)
        context.addPath(path)
        context.strokePath()
    }

    static let anthropicApi = template(width: 14, height: 14) { context in
        let key = CGMutablePath()
        key.addEllipse(in: CGRect(x: 2.0, y: 6.0, width: 5.0, height: 5.0))
        key.move(to: CGPoint(x: 6.5, y: 8.5))
        key.addLine(to: CGPoint(x: 12.0, y: 8.5))
        key.addLine(to: CGPoint(x: 12.0, y: 6.0))
        key.move(to: CGPoint(x: 10.0, y: 8.5))
        key.addLine(to: CGPoint(x: 10.0, y: 6.5))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        context.addPath(key)
        context.strokePath()
    }

    static let deepinfra = sfTemplate(systemName: "server.rack")
    static let minimax = sfTemplate(systemName: "waveform.path.ecg")
    static let ollama = sfTemplate(systemName: "cpu")
    static let kilo = sfTemplate(systemName: "scalemass")
    static let novita = sfTemplate(systemName: "sparkles")
    static let moonshot = sfTemplate(systemName: "moon.stars")
    static let orcarouter = sfTemplate(systemName: "arrow.triangle.branch")
    static let modelstudio = sfTemplate(systemName: "cube")
    static let opencodeGo = sfTemplate(systemName: "bolt.horizontal")
    static let kiro = sfTemplate(systemName: "shield")

    private static func sfTemplate(systemName: String, pointSize: CGFloat = 12) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let img = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        img.isTemplate = true
        return img
    }

    private static func template(
        width: CGFloat,
        height: CGFloat,
        draw: @escaping @Sendable (CGContext) -> Void
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { dstRect in
            guard let context = NSGraphicsContext.current?.cgContext,
                  width > 0, height > 0 else { return false }
            context.saveGState()
            context.translateBy(x: dstRect.minX, y: dstRect.minY)
            context.scaleBy(x: dstRect.width / width, y: dstRect.height / height)
            draw(context)
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
