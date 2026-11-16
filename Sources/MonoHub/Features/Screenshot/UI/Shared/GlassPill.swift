import AppKit

final class GlassPill: NSGlassEffectView {
    private let stack = NSStackView()
    private let iconView = NSImageView()
    private let swatchView = NSView()
    private let label = NSTextField(labelWithString: "")

    init(font: NSFont = .systemFont(ofSize: 12, weight: .medium)) {
        super.init(frame: .zero)
        style = .regular

        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        iconView.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.isHidden = true

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 6
        swatchView.layer?.borderWidth = 1
        swatchView.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        swatchView.isHidden = true
        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: 12),
            swatchView.heightAnchor.constraint(equalToConstant: 12)
        ])

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 13, bottom: 6, right: 14)
        stack.setViews([iconView, swatchView, label], in: .leading)
        contentView = stack
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
    }

    func configure(text: String, symbol: String? = nil, swatch: NSColor? = nil) {
        configure(attributedText: NSAttributedString(string: text, attributes: [
            .font: label.font ?? .systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]), symbol: symbol, swatch: swatch)
    }

    func configure(attributedText: NSAttributedString, symbol: String? = nil, swatch: NSColor? = nil) {
        label.attributedStringValue = attributedText
        iconView.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        iconView.isHidden = iconView.image == nil
        swatchView.layer?.backgroundColor = swatch?.cgColor
        swatchView.isHidden = swatch == nil
        setFrameSize(stack.fittingSize)
        setAccessibilityLabel(attributedText.string)
    }

    func place(centeredAt point: CGPoint, within bounds: CGRect, margin: CGFloat = 8) {
        var origin = CGPoint(x: point.x - frame.width / 2, y: point.y - frame.height / 2)
        origin.x = min(max(bounds.minX + margin, origin.x), bounds.maxX - frame.width - margin)
        origin.y = min(max(bounds.minY + margin, origin.y), bounds.maxY - frame.height - margin)
        setFrameOrigin(origin.rounded)
    }
}

extension CGPoint {
    var rounded: CGPoint {
        CGPoint(x: x.rounded(), y: y.rounded())
    }
}
