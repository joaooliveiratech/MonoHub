import AppKit
import CoreText
import Foundation

nonisolated enum UsageTint: Hashable, Sendable {
    case normal
    case warning
    case critical
    case charging
    case lowPower

    static func forUsage(_ ratio: Double, dynamic: Bool) -> UsageTint {
        guard dynamic else { return .normal }
        if ratio >= 0.9 { return .critical }
        if ratio >= 0.7 { return .warning }
        return .normal
    }

    static func forThermal(_ state: ProcessInfo.ThermalState, dynamic: Bool) -> UsageTint {
        guard dynamic else { return .normal }
        switch state {
        case .nominal: return .normal
        case .fair: return .warning
        case .serious, .critical: return .critical
        @unknown default: return .normal
        }
    }
}

nonisolated enum PowerIndicator: Hashable, Sendable {
    case none
    case charging
    case pluggedIn

    init(isCharging: Bool, isConnected: Bool) {
        if isCharging {
            self = .charging
        } else {
            self = isConnected ? .pluggedIn : .none
        }
    }

    var symbolName: String? {
        switch self {
        case .none: return nil
        case .charging: return "bolt.fill"
        case .pluggedIn: return "powerplug.portrait.fill"
        }
    }

    var accessibilitySuffix: String {
        switch self {
        case .none: return ""
        case .charging: return localized(", charging")
        case .pluggedIn: return localized(", connected to power")
        }
    }
}

nonisolated struct BatteryGlyphState: Hashable, Sendable {
    let percent: Int
    let isCharging: Bool
    let isConnected: Bool
    let isLowPowerMode: Bool
    let dynamicColors: Bool

    var indicator: PowerIndicator {
        PowerIndicator(isCharging: isCharging, isConnected: isConnected)
    }

    var fillTint: UsageTint {
        if isCharging { return .charging }
        if isLowPowerMode { return .lowPower }
        if dynamicColors, !isConnected, percent <= 20 { return .critical }
        return .normal
    }
}

nonisolated enum MenuBarContent: Hashable, Sendable {
    case gaugeWithLabel(label: String, value: String, ratio: Double, tint: UsageTint)
    case gaugeWithValue(value: String, ratio: Double, tint: UsageTint)
    case symbolWithValue(symbol: String, value: String, tint: UsageTint)
    case symbolStacked(symbol: String, value: String, tint: UsageTint)
    case labelWithValue(label: String, value: String, tint: UsageTint)
    case stacked(label: String, value: String, tint: UsageTint, prominent: Bool, labelSymbol: String?)
    case network(download: String, upload: String, downloadActive: Bool, uploadActive: Bool)
    case networkCompact(value: String, isDownload: Bool, isActive: Bool)
    case battery(BatteryGlyphState)
    case batteryWithPercent(BatteryGlyphState, value: String)
    case batteryInside(BatteryGlyphState)
    case batteryStacked(BatteryGlyphState, value: String)

    var isMonochrome: Bool {
        switch self {
        case let .gaugeWithLabel(_, _, _, tint), let .gaugeWithValue(_, _, tint), let .symbolWithValue(_, _, tint),
             let .symbolStacked(_, _, tint), let .labelWithValue(_, _, tint), let .stacked(_, _, tint, _, _):
            return tint == .normal
        case .network, .networkCompact:
            return true
        case let .battery(state), let .batteryWithPercent(state, _), let .batteryInside(state), let .batteryStacked(state, _):
            return state.fillTint == .normal
        }
    }

    var accessibilityLabel: String {
        switch self {
        case let .gaugeWithLabel(label, value, _, _), let .labelWithValue(label, value, _), let .stacked(label, value, _, _, _):
            return "\(label) \(value)"
        case let .gaugeWithValue(value, _, _), let .symbolWithValue(_, value, _), let .symbolStacked(_, value, _):
            return value
        case let .network(download, upload, _, _):
            return localized("Download %@/s, upload %@/s", download, upload)
        case let .networkCompact(value, isDownload, _):
            return localized(isDownload ? "Download %@/s" : "Upload %@/s", value)
        case let .battery(state), let .batteryInside(state), let .batteryWithPercent(state, _), let .batteryStacked(state, _):
            return localized("Battery %d%%", state.percent) + state.indicator.accessibilitySuffix
        }
    }
}

@MainActor
enum MenuBarRenderer {
    static let baseHeight: CGFloat = 22
    static let maximumHeight: CGFloat = 26
    static let itemPadding: CGFloat = 2

    private(set) static var height: CGFloat = baseHeight
    private static var metrics = Metrics(height: baseHeight)
    private static var symbolCache: [SymbolKey: NSImage] = [:]
    private static var widthCache: [WidthKey: CGFloat] = [:]
    private static var glyphCache: [ObjectIdentifier: NSRect] = [:]
    private static var imageCache: [MenuBarContent: NSImage] = [:]
    private static var networkImageCache: [MenuBarContent: NSImage] = [:]

    private struct SymbolKey: Hashable {
        let name: String
        let pointSize: CGFloat
        let weight: CGFloat
        let color: NSColor
    }

    private struct WidthKey: Hashable {
        let text: String
        let font: NSFont
    }

    private struct Metrics {
        let height: CGFloat
        let valueFont: NSFont
        let labelFont: NSFont
        let stackedLabelFont: NSFont
        let stackedValueFont: NSFont
        let stackedProminentFont: NSFont
        let symbolValueFont: NSFont
        let networkFont: NSFont
        let insideFont: NSFont
        let insideFontSmall: NSFont
        let symbolPointSize: CGFloat
        let symbolSlot: CGFloat
        let stackedSymbolPointSize: CGFloat
        let stackedTopHeight: CGFloat
        let gauge: NSSize
        let batteryBody: NSSize
        let batteryInsideBody: NSSize
        let batteryCap: NSSize
        let batteryStackedBody: NSSize
        let batteryStackedCap: NSSize
        let spacing: CGFloat
        let lineGap: CGFloat
        let indicatorWidth: CGFloat

        init(height: CGFloat) {
            self.height = height
            let growth = height / MenuBarRenderer.baseHeight - 1
            func text(_ size: CGFloat) -> CGFloat { (size * (1 + growth * 0.45) * 2).rounded() / 2 }
            func stackedText(_ size: CGFloat) -> CGFloat { (size * (1 + growth * 0.85) * 2).rounded() / 2 }
            func glyph(_ size: CGFloat) -> CGFloat { (size * (1 + growth * 0.75) * 2).rounded() / 2 }

            valueFont = .monospacedDigitSystemFont(ofSize: text(12), weight: .medium)
            labelFont = .systemFont(ofSize: text(10.5), weight: .semibold)
            stackedLabelFont = .systemFont(ofSize: stackedText(7.5), weight: .semibold)
            stackedValueFont = .monospacedDigitSystemFont(ofSize: stackedText(10), weight: .semibold)
            stackedProminentFont = .monospacedDigitSystemFont(ofSize: stackedText(11), weight: .bold)
            symbolValueFont = .monospacedDigitSystemFont(ofSize: stackedText(10), weight: .semibold)
            networkFont = .monospacedDigitSystemFont(ofSize: stackedText(9), weight: .semibold)
            insideFont = .monospacedDigitSystemFont(ofSize: glyph(9.5), weight: .bold)
            insideFontSmall = .monospacedDigitSystemFont(ofSize: glyph(8.5), weight: .bold)
            symbolPointSize = glyph(12.5)
            symbolSlot = glyph(15)
            stackedSymbolPointSize = stackedText(12)
            stackedTopHeight = stackedText(10.5)
            gauge = NSSize(width: 4, height: glyph(14))
            batteryBody = NSSize(width: glyph(26), height: glyph(13))
            batteryInsideBody = NSSize(width: glyph(28), height: glyph(13.5))
            batteryCap = NSSize(width: glyph(1.75), height: glyph(4.5))
            batteryStackedBody = NSSize(width: stackedText(19), height: stackedText(9))
            batteryStackedCap = NSSize(width: 1.5, height: stackedText(3.5))
            spacing = glyph(4)
            lineGap = 1.5 + growth * 2
            indicatorWidth = glyph(9)
        }

        var stackedColumnWidth: CGFloat {
            max(symbolSlot, MenuBarRenderer.valueWidth("00%", symbolValueFont))
        }
    }

    private struct StackedBlock {
        let bottom: CGFloat
        let top: CGFloat
    }

    private static func stackedBlock(topHeight: CGFloat, bottomHeight: CGFloat, gap: CGFloat, _ m: Metrics) -> StackedBlock {
        let bottom = snap((m.height - (topHeight + gap + bottomHeight)) / 2)
        return StackedBlock(bottom: bottom, top: bottom + bottomHeight + gap)
    }

    static func purgeCaches() {
        symbolCache.removeAll()
        glyphCache.removeAll()
        widthCache.removeAll()
        imageCache.removeAll()
        networkImageCache.removeAll()
    }

    static func updateAvailableHeight(_ available: CGFloat) -> Bool {
        let target = min(max(available.rounded(.down), baseHeight), maximumHeight)
        guard target != height else { return false }
        height = target
        metrics = Metrics(height: target)
        widthCache.removeAll()
        imageCache.removeAll()
        networkImageCache.removeAll()
        return true
    }

    static func image(for content: MenuBarContent) -> NSImage {
        let isNetworkContent: Bool
        switch content {
        case .network, .networkCompact:
            isNetworkContent = true
            if let cached = networkImageCache[content] {
                return cached
            }
            if networkImageCache.count >= 64 {
                networkImageCache.removeAll(keepingCapacity: true)
            }
        default:
            isNetworkContent = false
            if let cached = imageCache[content] {
                return cached
            }
            if imageCache.count >= 256 {
                imageCache.removeAll(keepingCapacity: true)
            }
        }
        let metrics = metrics
        let width = max(ceil(width(for: content, metrics)), 1)
        let image = NSImage(size: NSSize(width: width, height: metrics.height), flipped: false) { rect in
            draw(content, in: rect, metrics)
            return true
        }
        image.isTemplate = content.isMonochrome
        image.accessibilityDescription = content.accessibilityLabel
        if isNetworkContent {
            networkImageCache[content] = image
        } else {
            imageCache[content] = image
        }
        return image
    }

    private static func width(for content: MenuBarContent, _ m: Metrics) -> CGFloat {
        switch content {
        case let .gaugeWithLabel(label, value, _, _):
            return m.gauge.width + m.spacing + textWidth(label, m.labelFont) + 3 + valueWidth(value, m.valueFont)
        case let .gaugeWithValue(value, _, _):
            return m.gauge.width + m.spacing + valueWidth(value, m.valueFont)
        case let .symbolWithValue(_, value, _):
            return m.symbolSlot + m.spacing + valueWidth(value, m.valueFont)
        case let .labelWithValue(label, value, _):
            return textWidth(label, m.labelFont) + 3 + valueWidth(value, m.valueFont)
        case let .symbolStacked(_, value, _):
            return max(valueWidth(value, m.symbolValueFont), m.stackedColumnWidth)
        case let .batteryStacked(_, value):
            return max(valueWidth(value, m.symbolValueFont), m.batteryStackedBody.width + m.batteryStackedCap.width + 1, m.stackedColumnWidth)
        case let .stacked(label, value, _, prominent, symbol):
            let labelWidth = textWidth(label, m.stackedLabelFont) + (symbol == nil ? 0 : m.stackedLabelFont.pointSize + 1)
            return max(labelWidth, valueWidth(value, prominent ? m.stackedProminentFont : m.stackedValueFont), m.stackedColumnWidth)
        case .network:
            return m.networkFont.pointSize + valueWidth("999K", m.networkFont)
        case .networkCompact:
            return m.symbolSlot * 0.7 + valueWidth("999K", m.valueFont)
        case .battery:
            return m.batteryBody.width + m.batteryCap.width + 1.5
        case let .batteryWithPercent(_, value):
            return valueWidth(value, m.valueFont) + m.spacing + m.batteryBody.width + m.batteryCap.width + 1.5
        case let .batteryInside(state):
            return m.batteryInsideBody.width + m.batteryCap.width + 1.5 + (state.indicator == .none ? 0 : m.indicatorWidth)
        }
    }

    private static func draw(_ content: MenuBarContent, in rect: NSRect, _ m: Metrics) {
        switch content {
        case let .gaugeWithLabel(label, value, ratio, tint):
            drawGauge(ratio: ratio, tint: tint, x: 0, m)
            var x = m.gauge.width + m.spacing
            x += drawText(label, font: m.labelFont, color: .secondaryLabelColor, x: x, baselineFont: m.valueFont, m)
            drawText(value, font: m.valueFont, color: textColor(for: tint), x: x + 3, m)
        case let .gaugeWithValue(value, ratio, tint):
            drawGauge(ratio: ratio, tint: tint, x: 0, m)
            drawText(value, font: m.valueFont, color: textColor(for: tint), x: m.gauge.width + m.spacing, m)
        case let .symbolWithValue(symbol, value, tint):
            let box = NSRect(x: 0, y: (m.height - m.symbolSlot) / 2, width: m.symbolSlot, height: m.symbolSlot)
            drawSymbol(symbol, pointSize: m.symbolPointSize, weight: .medium, color: tint == .normal ? .labelColor : color(for: tint), fitting: box)
            drawText(value, font: m.valueFont, color: textColor(for: tint), x: m.symbolSlot + m.spacing, m)
        case let .labelWithValue(label, value, tint):
            let x = drawText(label, font: m.labelFont, color: .secondaryLabelColor, x: 0, baselineFont: m.valueFont, m)
            drawText(value, font: m.valueFont, color: textColor(for: tint), x: x + 3, m)
        case let .symbolStacked(symbol, value, tint):
            let block = stackedBlock(topHeight: m.stackedTopHeight, bottomHeight: m.symbolValueFont.capHeight, gap: m.lineGap, m)
            let box = NSRect(x: (rect.width - m.symbolSlot) / 2, y: block.top, width: m.symbolSlot, height: m.stackedTopHeight)
            drawSymbol(symbol, pointSize: m.stackedSymbolPointSize, weight: .medium, color: tint == .normal ? .labelColor : color(for: tint), fitting: box)
            drawCentered(value, font: m.symbolValueFont, color: textColor(for: tint), baseline: block.bottom, in: rect)
        case let .batteryStacked(state, value):
            let block = stackedBlock(topHeight: m.stackedTopHeight, bottomHeight: m.symbolValueFont.capHeight, gap: m.lineGap, m)
            let glyphWidth = m.batteryStackedBody.width + m.batteryStackedCap.width + 1
            let origin = NSPoint(
                x: snap((rect.width - glyphWidth) / 2),
                y: snap(block.top + (m.stackedTopHeight - m.batteryStackedBody.height) / 2)
            )
            drawBattery(state, body: m.batteryStackedBody, cap: m.batteryStackedCap, origin: origin, insideText: nil, m)
            drawCentered(value, font: m.symbolValueFont, color: state.fillTint == .critical ? .systemRed : .labelColor, baseline: block.bottom, in: rect)
        case let .stacked(label, value, tint, prominent, symbol):
            drawStacked(label: label, value: value, tint: tint, prominent: prominent, symbol: symbol, in: rect, m)
        case let .network(download, upload, downloadActive, uploadActive):
            drawNetwork(download: download, upload: upload, downloadActive: downloadActive, uploadActive: uploadActive, in: rect, m)
        case let .networkCompact(value, isDownload, isActive):
            let slot = m.symbolSlot * 0.7
            drawSymbol(isDownload ? "arrow.down" : "arrow.up", pointSize: m.symbolPointSize * 0.75, weight: .bold,
                       color: isActive ? .labelColor : .tertiaryLabelColor,
                       fitting: NSRect(x: 0, y: (m.height - slot) / 2, width: slot, height: slot))
            drawText(value, font: m.valueFont, color: isActive ? .labelColor : .secondaryLabelColor, x: slot, m)
        case let .battery(state):
            drawBattery(state, body: m.batteryBody, origin: NSPoint(x: 0.5, y: snap((m.height - m.batteryBody.height) / 2)), insideText: nil, m)
        case let .batteryWithPercent(state, value):
            let valueColor: NSColor = state.fillTint == .critical ? .systemRed : .labelColor
            let width = valueWidth(value, m.valueFont)
            drawText(value, font: m.valueFont, color: valueColor, x: 0, width: width, alignment: .right, m)
            drawBattery(state, body: m.batteryBody, origin: NSPoint(x: width + m.spacing, y: snap((m.height - m.batteryBody.height) / 2)), insideText: nil, m)
        case let .batteryInside(state):
            drawBattery(state, body: m.batteryInsideBody, origin: NSPoint(x: 0.5, y: snap((m.height - m.batteryInsideBody.height) / 2)), insideText: "\(state.percent)", m)
            if let symbol = state.indicator.symbolName {
                let x = m.batteryInsideBody.width + m.batteryCap.width + 1.5
                let color: NSColor = state.indicator == .charging ? .labelColor : .secondaryLabelColor
                let box = NSRect(x: x, y: (m.height - m.batteryInsideBody.height) / 2, width: m.indicatorWidth, height: m.batteryInsideBody.height)
                drawSymbol(symbol, pointSize: m.batteryInsideBody.height * 0.75, weight: .bold, color: color, fitting: box)
            }
        }
    }

    private static func drawGauge(ratio: Double, tint: UsageTint, x: CGFloat, _ m: Metrics) {
        let track = NSRect(x: x, y: snap((m.height - m.gauge.height) / 2), width: m.gauge.width, height: m.gauge.height)
        let radius = m.gauge.width / 2
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let clamped = CGFloat(min(max(ratio, 0), 1))
        let fillHeight = max(m.gauge.height * clamped, m.gauge.width)
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width, height: fillHeight)
        (tint == .normal ? NSColor.labelColor : color(for: tint)).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }

    private static func drawStacked(label: String, value: String, tint: UsageTint, prominent: Bool, symbol: String?, in rect: NSRect, _ m: Metrics) {
        let valueFont = prominent ? m.stackedProminentFont : m.stackedValueFont
        let labelColor: NSColor = tint == .charging ? .systemGreen : .secondaryLabelColor
        let block = stackedBlock(topHeight: m.stackedLabelFont.capHeight, bottomHeight: valueFont.capHeight, gap: m.lineGap + 1, m)
        let valueBaseline = block.bottom
        let labelBaseline = block.top

        let labelAttributed = NSAttributedString(string: label, attributes: [
            .font: m.stackedLabelFont,
            .foregroundColor: labelColor,
            .kern: 0.4
        ])
        let symbolWidth: CGFloat = symbol == nil ? 0 : m.stackedLabelFont.pointSize + 1
        let labelX = (rect.width - labelAttributed.size().width - symbolWidth) / 2
        if let symbol {
            let capHeight = m.stackedLabelFont.capHeight
            drawSymbol(symbol, pointSize: m.stackedLabelFont.pointSize, weight: .bold, color: labelColor,
                       fitting: NSRect(x: labelX, y: labelBaseline - 0.5, width: symbolWidth - 1, height: capHeight + 1))
        }
        drawLine(labelAttributed, color: labelColor, x: labelX + symbolWidth, baseline: labelBaseline)
        drawCentered(value, font: valueFont, color: textColor(for: tint), baseline: valueBaseline, in: rect)
    }

    private static func drawNetwork(download: String, upload: String, downloadActive: Bool, uploadActive: Bool, in rect: NSRect, _ m: Metrics) {
        let font = m.networkFont
        let block = stackedBlock(topHeight: font.capHeight, bottomHeight: font.capHeight, gap: m.lineGap + 2, m)
        let lowerBaseline = block.bottom
        let upperBaseline = block.top
        let rows: [(String, String, Bool, CGFloat)] = [
            ("arrow.up", upload, uploadActive, upperBaseline),
            ("arrow.down", download, downloadActive, lowerBaseline)
        ]
        let arrowSlot = font.pointSize * 0.8
        for (symbol, value, active, baseline) in rows {
            drawSymbol(symbol, pointSize: font.pointSize * 0.8, weight: .black, color: active ? .labelColor : .secondaryLabelColor,
                       fitting: NSRect(x: 0, y: baseline - 0.5, width: arrowSlot, height: font.capHeight + 1))
            let textColor: NSColor = active ? .labelColor : .secondaryLabelColor
            let attributed = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: textColor])
            drawLine(attributed, color: textColor, x: rect.width - attributed.size().width, baseline: baseline)
        }
    }

    private static func drawBattery(_ state: BatteryGlyphState, body: NSSize, cap: NSSize? = nil, origin: NSPoint, insideText: String?, _ m: Metrics) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let cap = cap ?? m.batteryCap

        let bodyRect = NSRect(origin: origin, size: body)
        let radius = body.height * 0.3
        let outline = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(0.4).setStroke()
        outline.stroke()

        let capRect = NSRect(x: bodyRect.maxX + 1, y: bodyRect.midY - cap.height / 2, width: cap.width, height: cap.height)
        NSColor.labelColor.withAlphaComponent(0.4).setFill()
        capPath(capRect).fill()

        let inset = max((body.height * 0.115 * 2).rounded() / 2, 1.5)
        let inner = bodyRect.insetBy(dx: inset, dy: inset)
        let ratio = CGFloat(min(max(Double(state.percent) / 100, 0), 1))
        let fillWidth = max(inner.width * ratio, ratio > 0 ? 2 : 0)
        let fillRect = NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height)
        let innerRadius = max(radius - inset + 0.3, 1.5)
        let fillColor = state.fillTint == .normal ? NSColor.labelColor : color(for: state.fillTint)

        let textOverlay: ((NSColor) -> Void)?
        let symbolOverlay: ((NSColor, CGFloat, NSCompositingOperation) -> Void)?
        if let insideText {
            let font = insideText.count >= 3 ? m.insideFontSmall : m.insideFont
            let width = NSAttributedString(string: insideText, attributes: [.font: font]).size().width
            let origin = NSPoint(x: snap(inner.midX - width / 2), y: snap(inner.midY - font.capHeight / 2 + font.descender))
            textOverlay = { color in
                NSAttributedString(string: insideText, attributes: [.font: font, .foregroundColor: color]).draw(at: origin)
            }
            symbolOverlay = nil
        } else if let symbol = state.indicator.symbolName {
            let glyphHeight = inner.height + inset * (state.indicator == .charging ? 1.2 : 0.4)
            let box = NSRect(x: inner.midX - glyphHeight, y: inner.midY - glyphHeight / 2, width: glyphHeight * 2, height: glyphHeight)
            let pointSize = body.height * (state.indicator == .charging ? 0.7 : 0.6)
            textOverlay = nil
            symbolOverlay = { color, halo, operation in
                drawSymbol(symbol, pointSize: pointSize, weight: .heavy, color: color, fitting: box.insetBy(dx: -halo, dy: -halo), operation: operation)
            }
        } else {
            textOverlay = nil
            symbolOverlay = nil
        }

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if fillWidth > 0 {
            fillColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: min(innerRadius, fillWidth / 2), yRadius: innerRadius).fill()
        }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        textOverlay?(.black)
        symbolOverlay?(.black, 0.9, .destinationOut)
        context.restoreGState()
        context.endTransparencyLayer()

        if let textOverlay, fillRect.maxX < inner.maxX {
            context.saveGState()
            context.clip(to: NSRect(x: fillRect.maxX, y: bodyRect.minY, width: bodyRect.maxX - fillRect.maxX, height: bodyRect.height))
            textOverlay(.labelColor)
            context.restoreGState()
        }
        symbolOverlay?(.labelColor, 0, .sourceOver)
    }

    private static func drawLine(_ text: NSAttributedString, color: NSColor, x: CGFloat, baseline: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        color.setFill()
        context.textPosition = CGPoint(x: snap(x), y: snap(baseline))
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.restoreGState()
    }

    private static func capPath(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX, y: rect.maxY - radius), radius: radius, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
        path.appendArc(withCenter: NSPoint(x: rect.minX, y: rect.minY + radius), radius: radius, startAngle: 0, endAngle: -90, clockwise: true)
        path.close()
        return path
    }

    private static func valueString(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        guard let unit = text.last, unit == "%" || unit == "°", text.count > 1 else { return result }
        let unitFont = NSFont.systemFont(ofSize: (font.pointSize * 0.72 * 2).rounded() / 2, weight: .semibold)
        result.addAttributes([.font: unitFont, .kern: 0], range: NSRange(location: (text as NSString).length - 1, length: 1))
        result.addAttribute(.kern, value: 0.4, range: NSRange(location: (text as NSString).length - 2, length: 1))
        return result
    }

    private static func drawCentered(_ text: String, font: NSFont, color: NSColor, baseline: CGFloat, in rect: NSRect) {
        let attributed = valueString(text, font: font, color: color)
        drawLine(attributed, color: color, x: (rect.width - attributed.size().width) / 2, baseline: baseline)
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        x: CGFloat,
        width: CGFloat? = nil,
        alignment: NSTextAlignment = .left,
        baselineFont: NSFont? = nil,
        _ m: Metrics
    ) -> CGFloat {
        let attributed = valueString(text, font: font, color: color)
        let size = attributed.size()
        let available = width ?? size.width
        let originX = alignment == .right ? x + available - size.width : x
        drawLine(attributed, color: color, x: originX, baseline: (m.height - (baselineFont ?? font).capHeight) / 2)
        return size.width
    }

    private static func drawSymbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        fitting box: NSRect,
        operation: NSCompositingOperation = .sourceOver
    ) {
        guard let symbol = symbolImage(name, pointSize: pointSize, weight: weight, color: color) else { return }
        let glyph = glyphRect(of: symbol)
        let scale = fitScale(glyph.size, in: box.size)
        let rect = NSRect(
            x: snap(box.midX - (glyph.midX * scale)),
            y: snap(box.midY - (glyph.midY * scale)),
            width: symbol.size.width * scale,
            height: symbol.size.height * scale
        )
        symbol.draw(in: rect, from: .zero, operation: operation, fraction: 1)
    }

    private static func glyphRect(of symbol: NSImage) -> NSRect {
        let key = ObjectIdentifier(symbol)
        if let cached = glyphCache[key] {
            return cached
        }
        let rect = measureGlyph(symbol) ?? NSRect(origin: .zero, size: symbol.size)
        glyphCache[key] = rect
        return rect
    }

    private static func measureGlyph(_ symbol: NSImage) -> NSRect? {
        let scale: CGFloat = 4
        let width = Int(ceil(symbol.size.width * scale))
        let height = Int(ceil(symbol.size.height * scale))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let cgImage = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0..<height {
            for column in 0..<width where data[row * width + column] > 24 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NSRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(height - 1 - maxY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    private static func fitScale(_ size: NSSize, in bounds: NSSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return min(bounds.width / size.width, bounds.height / size.height, 1.4)
    }

    private static func symbolImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let key = SymbolKey(name: name, pointSize: pointSize, weight: weight.rawValue, color: color)
        if let cached = symbolCache[key] {
            return cached
        }
        if symbolCache.count > 256 {
            symbolCache.removeAll(keepingCapacity: true)
            glyphCache.removeAll(keepingCapacity: true)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        symbolCache[key] = image
        return image
    }

    private static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        let key = WidthKey(text: text, font: font)
        if let cached = widthCache[key] {
            return cached
        }
        if widthCache.count > 512 {
            widthCache.removeAll(keepingCapacity: true)
        }
        let width = valueString(text, font: font, color: .labelColor).size().width
        widthCache[key] = width
        return width
    }

    fileprivate static func valueWidth(_ value: String, _ font: NSFont) -> CGFloat {
        let digits = value.reduce(0) { $1.isNumber ? $0 + 1 : $0 }
        guard digits == 1 else { return textWidth(value, font) }
        let template = String(value.flatMap { $0.isNumber ? ["0", "0"] : [$0] })
        return max(textWidth(template, font), textWidth(value, font))
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
        let factor = max(abs(scale), 1)
        return (value * factor).rounded() / factor
    }

    private static func textColor(for tint: UsageTint) -> NSColor {
        switch tint {
        case .normal, .lowPower: return .labelColor
        case .charging: return .systemGreen
        case .warning, .critical: return color(for: tint)
        }
    }

    private static func color(for tint: UsageTint) -> NSColor {
        switch tint {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .charging: return .systemGreen
        case .lowPower: return .systemYellow
        }
    }
}

@MainActor
enum MenuBarContentFactory {
    static func content(for module: ModuleType, style: DisplayStyle) -> MenuBarContent {
        let engine = SystemMonitorEngine.shared
        let prefs = MonitorPreferences.shared
        let dynamic = prefs.useDynamicColors

        switch module {
        case .cpu:
            return usage(label: module.shortTitle, symbol: "cpu", ratio: engine.cpuData.totalUsage, style: style, dynamic: dynamic)
        case .ram:
            return usage(label: module.shortTitle, symbol: "memorychip", ratio: engine.ramData.usedPercent, style: style, dynamic: dynamic)
        case .gpu:
            return usage(label: module.shortTitle, symbol: "cube.transparent", ratio: engine.gpuData.deviceUtilization, style: style, dynamic: dynamic)
        case .disk:
            return usage(label: module.shortTitle, symbol: "internaldrive", ratio: engine.diskData.usedPercent, style: style, dynamic: dynamic)
        case .network:
            return network(engine.networkData, style: style)
        case .battery:
            return battery(engine.batteryData, style: style, dynamic: dynamic)
        case .sensors:
            return sensors(engine.sensorsData, style: style, dynamic: dynamic)
        }
    }

    private static func percentText(_ ratio: Double) -> String {
        let value = Int((min(max(ratio, 0), 1) * 100).rounded())
        return MonitorPreferences.shared.showPercentSymbol ? "\(value)%" : "\(value)"
    }

    private static func usage(label: String, symbol: String, ratio: Double, style: DisplayStyle, dynamic: Bool) -> MenuBarContent {
        let value = percentText(ratio)
        let quantized = (ratio * 100).rounded() / 100
        let tint = UsageTint.forUsage(ratio, dynamic: dynamic)
        switch style {
        case .combined, .batteryInside:
            return .gaugeWithLabel(label: label, value: value, ratio: quantized, tint: tint)
        case .bar:
            return .gaugeWithValue(value: value, ratio: quantized, tint: tint)
        case .icon:
            return .symbolWithValue(symbol: symbol, value: value, tint: tint)
        case .symbolStacked:
            return .symbolStacked(symbol: symbol, value: value, tint: tint)
        case .text:
            return .labelWithValue(label: label, value: value, tint: tint)
        case .stacked:
            return .stacked(label: label, value: value, tint: tint, prominent: MonitorPreferences.shared.prominentPercentage, labelSymbol: nil)
        }
    }

    private static func network(_ data: NetworkData, style: DisplayStyle) -> MenuBarContent {
        let threshold: UInt64 = 10_000
        switch style {
        case .icon:
            let isDownload = data.downloadBytesPerSec >= data.uploadBytesPerSec
            let speed = isDownload ? data.downloadBytesPerSec : data.uploadBytesPerSec
            return .networkCompact(value: Formatting.compactSpeed(speed), isDownload: isDownload, isActive: speed >= threshold)
        default:
            return .network(
                download: Formatting.compactSpeed(data.downloadBytesPerSec),
                upload: Formatting.compactSpeed(data.uploadBytesPerSec),
                downloadActive: data.downloadBytesPerSec >= threshold,
                uploadActive: data.uploadBytesPerSec >= threshold
            )
        }
    }

    private static func battery(_ data: BatteryData, style: DisplayStyle, dynamic: Bool) -> MenuBarContent {
        let state = BatteryGlyphState(
            percent: data.levelPercent,
            isCharging: data.isCharging,
            isConnected: data.isConnectedToPower,
            isLowPowerMode: data.isLowPowerMode,
            dynamicColors: dynamic
        )
        let value = percentText(data.level)
        switch style {
        case .combined:
            return .batteryWithPercent(state, value: value)
        case .batteryInside:
            return .batteryInside(state)
        case .icon:
            return .battery(state)
        case .symbolStacked:
            return .batteryStacked(state, value: value)
        case .stacked:
            return .stacked(
                label: "BAT",
                value: value,
                tint: state.isCharging ? .charging : (state.fillTint == .critical ? .critical : .normal),
                prominent: MonitorPreferences.shared.prominentPercentage,
                labelSymbol: state.indicator.symbolName
            )
        case .text:
            return .labelWithValue(label: "BAT", value: value, tint: state.isCharging ? .charging : state.fillTint)
        case .bar:
            return .gaugeWithValue(value: value, ratio: (data.level * 100).rounded() / 100, tint: state.isCharging ? .charging : state.fillTint)
        }
    }

    private static func sensors(_ data: SensorsData, style: DisplayStyle, dynamic: Bool) -> MenuBarContent {
        let tint = UsageTint.forThermal(data.thermalState, dynamic: dynamic)
        let degrees = data.socTemperature.map { "\(Int($0.rounded()))°" } ?? "—"
        switch style {
        case .stacked:
            return .stacked(label: "SOC", value: degrees, tint: tint, prominent: MonitorPreferences.shared.prominentPercentage, labelSymbol: nil)
        case .text:
            return .labelWithValue(label: "SOC", value: degrees, tint: tint)
        case .symbolStacked:
            return .symbolStacked(symbol: "thermometer.medium", value: degrees, tint: tint)
        default:
            return .symbolWithValue(symbol: "thermometer.medium", value: degrees, tint: tint)
        }
    }
}
