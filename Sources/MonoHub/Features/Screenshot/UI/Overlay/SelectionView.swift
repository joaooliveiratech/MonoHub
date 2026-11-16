import AppKit
import CoreGraphics
import QuartzCore
import ScreenCaptureKit

enum OverlayMode: Sendable {
    case area
    case window

    var toggled: OverlayMode {
        self == .area ? .window : .area
    }
}

enum CaptureIntent: Sendable, Equatable {
    case screenshot
    case textRecognition
    case scrolling
    case screenRecord
}

protocol SelectionViewDelegate: AnyObject {
    func selectionViewDidComplete(rect: CGRect, screenNumber: CGDirectDisplayID, isOCR: Bool)
    func selectionViewDidSelectWindow(_ window: SCWindow)
    func selectionView(_ view: SelectionView, didChangeMode mode: OverlayMode)
    func selectionViewDidCancel()
}

final class SelectionView: NSView {
    weak var delegate: (any SelectionViewDelegate)?

    private let sourceImage: CGImage
    private let scaleFactor: CGFloat
    private let displayBounds: CGRect
    let screenNumber: CGDirectDisplayID
    let intent: CaptureIntent

    var mode: OverlayMode = .area {
        didSet {
            guard mode != oldValue else { return }
            startPoint = nil
            isDragging = false
            refreshHoveredWindow()
            refreshHints()
            refreshAll()
            window?.invalidateCursorRects(for: self)
        }
    }

    var visibleWindows: [SCWindow] = [] {
        didSet {
            windowRects = visibleWindows.map { ($0, localRect(for: $0)) }
            refreshHoveredWindow()
            refreshAll()
        }
    }

    private var windowRects: [(window: SCWindow, rect: CGRect)] = []
    private var hovered: (window: SCWindow, rect: CGRect)?

    private var startPoint: CGPoint?
    private var pointer: CGPoint?
    private var isDragging = false
    private var hoveredPixelColor: RGBAColor?
    private var copiedFeedbackText: String?
    private var feedbackTask: Task<Void, Never>?
    private var trackingArea: NSTrackingArea?

    private let stage = NSView()
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let loupeLayer = CALayer()
    private let loupeClipLayer = CALayer()
    private let loupeImageLayer = CALayer()
    private let loupeGridLayer = CAShapeLayer()

    private let hintsPill = GlassPill()
    private let sizePill = GlassPill(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
    private let windowPill = GlassPill(font: .systemFont(ofSize: 12, weight: .semibold))
    private let colorPill = GlassPill(font: .monospacedSystemFont(ofSize: 11, weight: .semibold))

    private static let loupeDiameter: CGFloat = 104
    private static let loupeSampleDimension = 13
    private static let loupeOffset: CGFloat = 26
    private static let windowCornerRadius: CGFloat = 12

    private let pixelSampler = PixelSampler()

    init(
        sourceImage: CGImage,
        scaleFactor: CGFloat,
        displayBounds: CGRect,
        screenNumber: CGDirectDisplayID,
        initialMode: OverlayMode = .area,
        intent: CaptureIntent = .screenshot
    ) {
        self.sourceImage = sourceImage
        self.scaleFactor = scaleFactor
        self.displayBounds = displayBounds
        self.screenNumber = screenNumber
        self.intent = intent
        self.mode = initialMode

        super.init(frame: CGRect(origin: .zero, size: displayBounds.size))
        wantsLayer = true
        setupLayers()
        setupPills()
        refreshHints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        stage.frame = bounds
        stage.autoresizingMask = [.width, .height]
        stage.wantsLayer = true
        addSubview(stage)
        guard let root = stage.layer else { return }

        imageLayer.contents = sourceImage
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = MonoStyle.dimColor.cgColor

        outlineLayer.fillColor = nil
        outlineLayer.lineJoin = .round

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.lineWidth = 1
        handlesLayer.shadowColor = NSColor.black.cgColor
        handlesLayer.shadowOpacity = 0.35
        handlesLayer.shadowRadius = 1.5
        handlesLayer.shadowOffset = CGSize(width: 0, height: -0.5)

        let diameter = Self.loupeDiameter
        let loupeBounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        loupeLayer.bounds = loupeBounds
        loupeLayer.shadowColor = NSColor.black.cgColor
        loupeLayer.shadowOpacity = 0.4
        loupeLayer.shadowRadius = 12
        loupeLayer.shadowOffset = CGSize(width: 0, height: -4)
        loupeLayer.shadowPath = CGPath(ellipseIn: loupeBounds, transform: nil)

        loupeClipLayer.frame = loupeBounds
        loupeClipLayer.cornerRadius = diameter / 2
        loupeClipLayer.masksToBounds = true
        loupeClipLayer.borderWidth = 2.5
        loupeClipLayer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        loupeClipLayer.backgroundColor = NSColor.black.cgColor

        loupeImageLayer.frame = loupeBounds
        loupeImageLayer.magnificationFilter = .nearest
        loupeImageLayer.contentsGravity = .resize

        loupeGridLayer.frame = loupeBounds
        loupeGridLayer.path = Self.loupeGridPath(in: loupeBounds)
        loupeGridLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        loupeGridLayer.lineWidth = 0.5
        loupeGridLayer.fillColor = nil

        let reticle = CAShapeLayer()
        reticle.frame = loupeBounds
        reticle.path = CGPath(rect: Self.loupeCenterPixelRect(in: loupeBounds), transform: nil)
        reticle.fillColor = nil
        reticle.strokeColor = NSColor.white.cgColor
        reticle.lineWidth = 1.5
        reticle.shadowColor = NSColor.black.cgColor
        reticle.shadowOpacity = 0.8
        reticle.shadowRadius = 0.5
        reticle.shadowOffset = .zero

        loupeClipLayer.addSublayer(loupeImageLayer)
        loupeClipLayer.addSublayer(loupeGridLayer)
        loupeClipLayer.addSublayer(reticle)
        loupeLayer.addSublayer(loupeClipLayer)
        loupeLayer.isHidden = true

        for layer in [imageLayer, dimLayer, outlineLayer, handlesLayer, loupeLayer] {
            root.addSublayer(layer)
        }
    }

    private func setupPills() {
        for pill in [hintsPill, sizePill, windowPill, colorPill] {
            pill.isHidden = true
            addSubview(pill)
        }
    }

    private static func loupeGridPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cell = rect.width / CGFloat(loupeSampleDimension)
        for index in 1..<loupeSampleDimension {
            let offset = CGFloat(index) * cell
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }
        return path
    }

    private static func loupeCenterPixelRect(in rect: CGRect) -> CGRect {
        let cell = rect.width / CGFloat(loupeSampleDimension)
        let middle = CGFloat(loupeSampleDimension / 2)
        return CGRect(x: rect.minX + middle * cell, y: rect.minY + middle * cell, width: cell, height: cell)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateContentsScale()
        let location = NSEvent.mouseLocation
        let local = CGPoint(x: location.x - displayBounds.minX, y: location.y - displayBounds.minY)
        if bounds.contains(local) {
            pointerMoved(to: local)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? scaleFactor
        for layer in [dimLayer, outlineLayer, handlesLayer, loupeGridLayer] as [CALayer] {
            layer.contentsScale = scale
        }
        loupeClipLayer.sublayers?.forEach { $0.contentsScale = scale }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .area ? .crosshair : .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        (mode == .area ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    func localRect(for window: SCWindow) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? displayBounds.height
        let globalY = primaryHeight - (window.frame.origin.y + window.frame.height)
        return CGRect(
            x: window.frame.origin.x - displayBounds.origin.x,
            y: globalY - displayBounds.origin.y,
            width: window.frame.width,
            height: window.frame.height
        )
    }

    func windowAt(point: CGPoint) -> SCWindow? {
        windowRects.first(where: { $0.rect.contains(point) })?.window
    }

    private var currentRegion: CaptureRegion? {
        guard let startPoint, let pointer else { return nil }
        return CaptureRegion(startPoint: startPoint, currentPoint: pointer, displayBounds: displayBounds, scaleFactor: scaleFactor)
    }

    private var selectedRect: CGRect? {
        guard let rect = currentRegion?.normalizedRect, rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }

    private func constrained(_ point: CGPoint, squareFrom origin: CGPoint?, shift: Bool) -> CGPoint {
        guard shift, let origin else { return point }
        let side = max(abs(point.x - origin.x), abs(point.y - origin.y))
        return CGPoint(
            x: origin.x + (point.x >= origin.x ? side : -side),
            y: origin.y + (point.y >= origin.y ? side : -side)
        )
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hovered = nil
        refreshAll()
    }

    private func pointerMoved(to point: CGPoint) {
        pointer = point
        hoveredPixelColor = pixelColor(at: point)
        if mode == .window {
            refreshHoveredWindow()
        }
        refreshAll()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .window {
            if let target = windowAt(point: point) ?? hovered?.window {
                delegate?.selectionViewDidSelectWindow(target)
            }
            return
        }

        startPoint = point
        pointer = point
        hoveredPixelColor = pixelColor(at: point)
        isDragging = true
        refreshAll()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let raw = convert(event.locationInWindow, from: nil)
        let point = constrained(raw, squareFrom: startPoint, shift: event.modifierFlags.contains(.shift))
        pointer = point
        hoveredPixelColor = pixelColor(at: raw)
        refreshAll()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let region = currentRegion else {
            isDragging = false
            return
        }
        isDragging = false

        if region.isValid {
            complete(rect: region.normalizedRect, forceOCR: false)
        } else {
            startPoint = nil
            refreshAll()
        }
    }

    private func complete(rect: CGRect, forceOCR: Bool) {
        let isOCR = forceOCR || intent == .textRecognition
        delegate?.selectionViewDidComplete(rect: rect, screenNumber: screenNumber, isOCR: isOCR)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case ShotKeyCode.space:
            mode = mode.toggled
            delegate?.selectionView(self, didChangeMode: mode)
            return
        case ShotKeyCode.returnKey, ShotKeyCode.keypadEnter:
            if let rect = selectedRect, rect.width > 4, rect.height > 4 {
                complete(rect: rect, forceOCR: false)
            } else if mode == .window, let target = hovered?.window ?? pointer.flatMap(windowAt(point:)) {
                delegate?.selectionViewDidSelectWindow(target)
            }
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copyHoveredColor()
        case "o":
            if let rect = selectedRect, rect.width > 4, rect.height > 4 {
                complete(rect: rect, forceOCR: true)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func copyHoveredColor() {
        guard let color = hoveredPixelColor else { return }
        PasteboardWriter.write(text: color.hexString, concealed: false)

        feedbackTask?.cancel()
        copiedFeedbackText = ShotText.hexCopiedFeedback(hex: color.hexString)
        refreshLoupe()

        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self else { return }
            self.copiedFeedbackText = nil
            self.refreshLoupe()
        }
    }

    private func pixelCoordinates(at point: CGPoint) -> (x: Int, y: Int) {
        (Int(point.x * scaleFactor), Int((displayBounds.height - point.y) * scaleFactor))
    }

    private func pixelColor(at point: CGPoint) -> RGBAColor? {
        let pixel = pixelCoordinates(at: point)
        return pixelSampler.color(in: sourceImage, pixelX: pixel.x, pixelY: pixel.y)
    }

    private func loupeSample(at point: CGPoint) -> CGImage? {
        let dimension = Self.loupeSampleDimension
        guard sourceImage.width >= dimension, sourceImage.height >= dimension else { return nil }

        let pixel = pixelCoordinates(at: point)
        let half = dimension / 2
        let originX = min(max(0, pixel.x - half), sourceImage.width - dimension)
        let originY = min(max(0, pixel.y - half), sourceImage.height - dimension)
        return sourceImage.cropping(to: CGRect(x: originX, y: originY, width: dimension, height: dimension))
    }

    private func refreshHoveredWindow() {
        guard mode == .window, let pointer else {
            hovered = nil
            return
        }
        hovered = windowRects.first(where: { $0.rect.contains(pointer) })
    }

    private func refreshAll() {
        MonoStyle.withoutImplicitAnimations {
            refreshSelectionLayers()
            refreshLoupe()
        }
        refreshPills()
    }

    private func refreshSelectionLayers() {
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)

        let accent = MonoStyle.accent.cgColor
        outlineLayer.strokeColor = accent
        handlesLayer.strokeColor = accent

        if mode == .window, let rect = hovered?.rect {
            let radius = Self.windowCornerRadius
            dimPath.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            outlineLayer.path = CGPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
            outlineLayer.lineWidth = 3
            outlineLayer.fillColor = MonoStyle.accent.withAlphaComponent(0.12).cgColor
            handlesLayer.path = nil
        } else if mode == .area, let rect = selectedRect {
            dimPath.addRect(rect)
            outlineLayer.path = CGPath(rect: rect, transform: nil)
            outlineLayer.lineWidth = 1.5
            outlineLayer.fillColor = nil
            handlesLayer.path = MonoStyle.handlesPath(around: rect)
        } else {
            outlineLayer.path = nil
            handlesLayer.path = nil
        }

        dimLayer.path = dimPath
    }

    private func loupeCenter(for point: CGPoint) -> CGPoint {
        let radius = Self.loupeDiameter / 2
        let offset = Self.loupeOffset + radius
        var center = CGPoint(x: point.x + offset, y: point.y + offset)
        if center.x + radius + 12 > bounds.maxX {
            center.x = point.x - offset
        }
        if center.y + radius + 12 > bounds.maxY {
            center.y = point.y - offset
        }
        if center.y - radius - 44 < bounds.minY {
            center.y = point.y + offset
        }
        return center
    }

    private func refreshLoupe() {
        guard mode == .area, let pointer, hoveredPixelColor != nil, let sample = loupeSample(at: pointer) else {
            loupeLayer.isHidden = true
            colorPill.isHidden = true
            return
        }
        MonoStyle.withoutImplicitAnimations {
            loupeLayer.isHidden = false
            loupeLayer.position = loupeCenter(for: pointer).rounded
            loupeImageLayer.contents = sample
        }
        refreshColorPill()
    }

    private func refreshColorPill() {
        guard let pointer, let color = hoveredPixelColor, !loupeLayer.isHidden else {
            colorPill.isHidden = true
            return
        }
        if let copiedFeedbackText {
            colorPill.configure(text: copiedFeedbackText, symbol: "checkmark.circle.fill")
        } else {
            colorPill.configure(text: "\(color.hexString)  C", swatch: NSColor(cgColor: color.cgColor))
        }
        let center = loupeCenter(for: pointer)
        colorPill.place(
            centeredAt: CGPoint(x: center.x, y: center.y - Self.loupeDiameter / 2 - colorPill.frame.height / 2 - 8),
            within: bounds
        )
        colorPill.isHidden = false
    }

    private func refreshPills() {
        refreshColorPill()

        if mode == .area, isDragging, let region = currentRegion, region.isValid {
            sizePill.configure(text: "\(Int(region.width)) × \(Int(region.height))  ·  \(region.pixelDimensionLabel)")
            let rect = region.normalizedRect
            var anchor = CGPoint(x: rect.midX, y: rect.minY - sizePill.frame.height / 2 - 10)
            if anchor.y - sizePill.frame.height / 2 < bounds.minY + 8 {
                anchor.y = rect.minY + sizePill.frame.height / 2 + 10
            }
            sizePill.place(centeredAt: anchor, within: bounds)
            sizePill.isHidden = false
        } else {
            sizePill.isHidden = true
        }

        if mode == .window, let hovered {
            let appName = hovered.window.owningApplication?.applicationName ?? ShotText.windowFallbackTitle
            windowPill.configure(
                text: "\(appName)  ·  \(Int(hovered.rect.width)) × \(Int(hovered.rect.height))",
                symbol: "macwindow"
            )
            var anchor = CGPoint(x: hovered.rect.midX, y: hovered.rect.maxY + windowPill.frame.height / 2 + 10)
            if anchor.y + windowPill.frame.height / 2 > bounds.maxY - 8 {
                anchor.y = hovered.rect.maxY - windowPill.frame.height / 2 - 14
            }
            windowPill.place(centeredAt: anchor, within: bounds)
            windowPill.isHidden = false
        } else {
            windowPill.isHidden = true
        }
    }

    private func refreshHints() {
        let modeName: String
        let primaryHint: String
        switch (intent, mode) {
        case (.textRecognition, .area):
            modeName = ShotText.overlayModeText
            primaryHint = ShotText.overlayHintDragText
        case (.scrolling, .area):
            modeName = ShotText.overlayModeScrolling
            primaryHint = ShotText.overlayHintDragScrolling
        case (.screenRecord, .area):
            modeName = ShotText.overlayModeRecording
            primaryHint = ShotText.overlayHintDragRecording
        case (.scrolling, .window):
            modeName = ShotText.overlayModeScrolling
            primaryHint = ShotText.overlayHintClickWindowScrolling
        case (.screenRecord, .window):
            modeName = ShotText.overlayModeRecording
            primaryHint = ShotText.overlayHintClickWindowRecording
        case (_, .window):
            modeName = ShotText.overlayModeWindow
            primaryHint = ShotText.overlayHintClickWindow
        case (.screenshot, .area):
            modeName = ShotText.overlayModeArea
            primaryHint = ShotText.overlayHintDrag
        }

        var keys: [(String, String)] = [
            (ShotText.keySpace, mode == .area ? ShotText.overlayHintSwitchToWindow : ShotText.overlayHintSwitchToArea)
        ]
        if mode == .area && intent == .screenshot {
            keys.append(("C", ShotText.overlayHintCopyColor))
            keys.append(("O", ShotText.overlayHintText))
        }
        keys.append(("esc", ShotText.overlayHintCancel))

        let text = NSMutableAttributedString(string: "\(modeName)  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: primaryHint, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]))
        for (key, label) in keys {
            text.append(NSAttributedString(string: "     \(key) ", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]))
            text.append(NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        hintsPill.configure(attributedText: text, symbol: mode == .area ? "rectangle.dashed" : "macwindow")
        hintsPill.place(centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 56), within: bounds)
        hintsPill.isHidden = false
    }
}
