import AppKit
import Foundation

nonisolated struct AIQuotaBarColumn: Hashable, Sendable {
    let provider: ProviderType
    let label: String
    let value: String
    let ratio: Double
    let tint: UsageTint
}

@MainActor
enum AIQuotaMenuBarRenderer {
    private static let columnGap: CGFloat = 9
    private static let edgePadding: CGFloat = 1
    private static var imageCache: [CacheKey: NSImage] = [:]

    private struct CacheKey: Hashable {
        let mode: MenuBarDisplayMode
        let columns: [AIQuotaBarColumn]
        let height: CGFloat
    }

    private struct Metrics {
        let height: CGFloat
        let ringDiameter: CGFloat
        let ringLine: CGFloat
        let ringGlyph: CGFloat
        let stackedGlyph: CGFloat
        let valueFont: NSFont
        let stackedValueFont: NSFont
        let stackedLabelFont: NSFont
        let spacing: CGFloat
        let lineGap: CGFloat

        init(height: CGFloat) {
            self.height = height
            let growth = height / MenuBarRenderer.baseHeight - 1
            ringDiameter = (min(height - 4, 18) * 2).rounded() / 2
            ringLine = 1.75
            ringGlyph = (ringDiameter * 0.56 * 2).rounded() / 2
            stackedGlyph = ((11 + growth * 4) * 2).rounded() / 2
            valueFont = .monospacedDigitSystemFont(ofSize: (12 + growth * 2).rounded(), weight: .medium)
            stackedValueFont = .monospacedDigitSystemFont(ofSize: (10 + growth * 2).rounded(), weight: .semibold)
            stackedLabelFont = .systemFont(ofSize: (7.5 + growth * 1.5), weight: .semibold)
            spacing = 4
            lineGap = 1.5 + growth * 2
        }
    }

    static func currentColumns() -> [AIQuotaBarColumn] {
        let prefs = QuotaPreferencesManager.shared
        let quota = QuotaManager.shared
        let threshold = prefs.warningThreshold

        return prefs.enabledProviders.map { provider in
            let status = quota.status(for: provider)
            let percent = status.primaryUsagePercent ?? (status.hasReading ? status.peakUsagePercent : 0)
            let tint: UsageTint
            if !prefs.alertColors {
                tint = .normal
            } else if status.state.isError || percent >= 90 {
                tint = .critical
            } else if percent >= threshold {
                tint = .warning
            } else {
                tint = .normal
            }
            return AIQuotaBarColumn(
                provider: provider,
                label: provider.shortCode.uppercased(),
                value: quota.usageText(for: provider),
                ratio: percent.rounded() / 100.0,
                tint: tint
            )
        }
    }

    static func purgeCaches() {
        imageCache.removeAll()
    }

    static func image(mode: MenuBarDisplayMode, columns: [AIQuotaBarColumn]) -> NSImage {
        let height = MenuBarRenderer.height
        let key = CacheKey(mode: mode, columns: columns, height: height)
        if let cached = imageCache[key] {
            return cached
        }
        if imageCache.count >= 64 {
            imageCache.removeAll(keepingCapacity: true)
        }

        let metrics = Metrics(height: height)
        let widths = columns.map { width(of: $0, mode: mode, metrics) }
        let total = max(ceil(widths.reduce(0, +) + columnGap * CGFloat(max(columns.count - 1, 0)) + edgePadding * 2), 1)
        let isMonochrome = columns.allSatisfy { $0.tint == .normal }

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x = edgePadding
            for (column, width) in zip(columns, widths) {
                draw(column, mode: mode, x: x, width: width, monochrome: isMonochrome, metrics)
                x += width + columnGap
            }
            return true
        }
        image.isTemplate = isMonochrome
        image.accessibilityDescription = columns.map { "\($0.provider.displayName) \($0.value)" }.joined(separator: ", ")
        imageCache[key] = image
        return image
    }

    private static func width(of column: AIQuotaBarColumn, mode: MenuBarDisplayMode, _ m: Metrics) -> CGFloat {
        switch mode {
        case .ringValue:
            return m.ringDiameter + m.spacing + textWidth(column.value, m.valueFont)
        case .ringOnly:
            return m.ringDiameter
        case .iconStacked:
            return max(m.stackedGlyph, textWidth(column.value, m.stackedValueFont))
        case .labelStacked:
            return max(textWidth(column.label, m.stackedLabelFont) + 0.4 * CGFloat(column.label.count), textWidth(column.value, m.stackedValueFont))
        }
    }

    private static func draw(_ column: AIQuotaBarColumn, mode: MenuBarDisplayMode, x: CGFloat, width: CGFloat, monochrome: Bool, _ m: Metrics) {
        let ink: NSColor = monochrome ? .black : color(for: column.tint, fallback: .labelColor)
        let primary: NSColor = monochrome ? .black : .labelColor

        switch mode {
        case .ringValue:
            drawRing(column, at: NSPoint(x: x, y: (m.height - m.ringDiameter) / 2), ink: ink, primary: primary, m)
            drawText(column.value, font: m.valueFont, color: ink, x: x + m.ringDiameter + m.spacing, centeredIn: m.height)
        case .ringOnly:
            drawRing(column, at: NSPoint(x: x, y: (m.height - m.ringDiameter) / 2), ink: ink, primary: primary, m)
        case .iconStacked:
            let valueHeight = m.stackedValueFont.capHeight
            let bottom = snap((m.height - (m.stackedGlyph + m.lineGap + valueHeight)) / 2)
            let box = NSRect(x: x + (width - m.stackedGlyph) / 2, y: bottom + valueHeight + m.lineGap, width: m.stackedGlyph, height: m.stackedGlyph)
            drawGlyph(of: column.provider, in: box, color: ink)
            drawText(column.value, font: m.stackedValueFont, color: ink, x: x, width: width, baseline: bottom)
        case .labelStacked:
            let valueHeight = m.stackedValueFont.capHeight
            let labelHeight = m.stackedLabelFont.capHeight
            let gap = m.lineGap + 1
            let bottom = snap((m.height - (labelHeight + gap + valueHeight)) / 2)
            let labelColor: NSColor = monochrome ? .black : .secondaryLabelColor
            drawText(column.label, font: m.stackedLabelFont, color: labelColor, x: x, width: width, baseline: bottom + valueHeight + gap, kern: 0.4)
            drawText(column.value, font: m.stackedValueFont, color: ink, x: x, width: width, baseline: bottom)
        }
    }

    private static func drawRing(_ column: AIQuotaBarColumn, at origin: NSPoint, ink: NSColor, primary: NSColor, _ m: Metrics) {
        let outer = NSRect(origin: origin, size: NSSize(width: m.ringDiameter, height: m.ringDiameter))
        let rect = outer.insetBy(dx: m.ringLine / 2, dy: m.ringLine / 2)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = m.ringLine
        primary.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let ratio = min(max(column.ratio, 0), 1)
        if ratio > 0 {
            let sweep = max(ratio, 0.04) * 360
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
            arc.lineWidth = m.ringLine
            arc.lineCapStyle = .round
            ink.setStroke()
            arc.stroke()
        }

        let side = m.ringGlyph
        let box = NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        drawGlyph(of: column.provider, in: box, color: column.tint == .normal ? primary : ink)
    }

    private static func drawGlyph(of provider: ProviderType, in box: NSRect, color: NSColor) {
        let icon = provider.brandIcon
        let native = icon.size
        guard native.width > 0, native.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(box.width / native.width, box.height / native.height)
        let size = NSSize(width: (native.width * scale * 2).rounded() / 2, height: (native.height * scale * 2).rounded() / 2)
        let target = NSRect(
            x: snap(box.midX - size.width / 2),
            y: snap(box.midY - size.height / 2),
            width: size.width,
            height: size.height
        )
        context.saveGState()
        context.beginTransparencyLayer(in: target, auxiliaryInfo: nil)
        icon.draw(in: target)
        color.setFill()
        target.fill(using: .sourceAtop)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, centeredIn height: CGFloat) {
        let baseline = snap((height - font.capHeight) / 2)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        attributed.draw(at: NSPoint(x: x, y: baseline + font.descender))
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, width: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: x + (width - size.width) / 2, y: baseline + font.descender))
    }

    private static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    private static func color(for tint: UsageTint, fallback: NSColor) -> NSColor {
        switch tint {
        case .warning, .lowPower: return .systemOrange
        case .critical: return .systemRed
        case .charging: return .systemGreen
        case .normal: return fallback
        }
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}
