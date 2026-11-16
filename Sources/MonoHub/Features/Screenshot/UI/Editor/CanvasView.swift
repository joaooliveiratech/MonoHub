import AppKit
import CoreGraphics

protocol CanvasViewDelegate: AnyObject {
    func canvasView(_ canvas: CanvasView, didSelect element: AnnotationElement?)
    func canvasViewDidFinishTextEntry(_ canvas: CanvasView)
    func canvasView(_ canvas: CanvasView, didRequestTool tool: ToolMode)
}

final class ScreenshotBackdropView: NSView {
    var image: CGImage? {
        didSet {
            guard image !== oldValue else { return }
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { true }

    override func updateLayer() {
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .trilinear
    }
}

final class CanvasView: NSView {
    let document: ScreenshotDocument
    weak var delegate: (any CanvasViewDelegate)?
    weak var backdrop: ScreenshotBackdropView?

    var currentTool: ToolMode = .select {
        didSet {
            guard currentTool != oldValue else { return }
            if currentTool != .select {
                select(nil)
            }
            window?.invalidateCursorRects(for: self)
        }
    }
    var currentColor: RGBAColor = .red
    var censorScale: CGFloat = CensorStrength.default.scale

    private(set) var selectedAnnotationId: UUID? {
        didSet {
            if selectedAnnotationId != oldValue { needsDisplay = true }
        }
    }

    private var isDraggingSelectedAnnotation = false
    private var dragStartPoint: CGPoint = .zero
    private var dragPreviousState: [AnnotationElement] = []
    private var hasMovedSelectedAnnotation = false

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDrawing = false

    private var activeTextField: NSTextField?
    private var activeTextOrigin: CGPoint = .zero

    private static let textFontSize: CGFloat = 18
    private static let defaultStrokeWidth: CGFloat = 4

    var hasActiveInlineText: Bool {
        activeTextField != nil
    }

    var selectedAnnotation: AnnotationElement? {
        selectedAnnotationId.flatMap(document.annotation(withId:))
    }

    init(document: ScreenshotDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.logicalSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        switch currentTool {
        case .select: addCursorRect(bounds, cursor: .arrow)
        case .text: addCursorRect(bounds, cursor: .iBeam)
        default: addCursorRect(bounds, cursor: .crosshair)
        }
    }

    func documentDidChange() {
        backdrop?.image = document.censoredBaseImage
        if let selectedAnnotationId, document.annotation(withId: selectedAnnotationId) == nil {
            select(nil)
        }
        needsDisplay = true
    }

    private func select(_ element: AnnotationElement?) {
        selectedAnnotationId = element?.id
        delegate?.canvasView(self, didSelect: element)
    }

    private func add(_ element: AnnotationElement) {
        document.addAnnotation(element)
        documentDidChange()
        select(element)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if activeTextField != nil {
            commitInlineText()
        }

        switch currentTool {
        case .select:
            let hit = document.annotation(at: point)
            select(hit)
            if hit != nil {
                isDraggingSelectedAnnotation = true
                dragStartPoint = point
                hasMovedSelectedAnnotation = false
            }

        case .counter:
            add(.counter(CounterAnnotation(center: point, number: document.nextCounterIndex, color: currentColor)))

        case .text:
            startInlineText(at: point)

        case .arrow, .curvedArrow, .rectangle, .blur, .pixelate:
            select(nil)
            dragStart = point
            dragCurrent = point
            isDrawing = true
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDraggingSelectedAnnotation, let id = selectedAnnotationId {
            let delta = CGSize(width: point.x - dragStartPoint.x, height: point.y - dragStartPoint.y)
            if abs(delta.width) > 0.25 || abs(delta.height) > 0.25 {
                if !hasMovedSelectedAnnotation {
                    dragPreviousState = document.annotations
                }
                document.moveAnnotation(withId: id, by: delta)
                dragStartPoint = point
                hasMovedSelectedAnnotation = true
                documentDidChange()
            }
            return
        }

        guard isDrawing else { return }
        dragCurrent = constrained(point, from: dragStart, shift: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    private func constrained(_ point: CGPoint, from origin: CGPoint?, shift: Bool) -> CGPoint {
        guard shift, let origin else { return point }
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if currentTool == .arrow || currentTool == .curvedArrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: origin.x + (dx >= 0 ? side : -side), y: origin.y + (dy >= 0 ? side : -side))
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingSelectedAnnotation {
            isDraggingSelectedAnnotation = false
            if hasMovedSelectedAnnotation {
                document.commitMove(previousState: dragPreviousState)
                hasMovedSelectedAnnotation = false
            }
            dragPreviousState = []
            return
        }

        guard isDrawing, let start = dragStart, let end = dragCurrent else {
            isDrawing = false
            return
        }
        isDrawing = false
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true

        guard hypot(end.x - start.x, end.y - start.y) > 4,
              let element = makeElement(from: start, to: end) else { return }
        add(element)
    }

    private func makeElement(from start: CGPoint, to end: CGPoint) -> AnnotationElement? {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch currentTool {
        case .arrow:
            return .arrow(ArrowAnnotation(start: start, end: end, strokeWidth: Self.defaultStrokeWidth, color: currentColor))
        case .curvedArrow:
            return .arrow(ArrowAnnotation(
                start: start,
                end: end,
                controlPoint: ArrowAnnotation.defaultControlPoint(from: start, to: end),
                strokeWidth: Self.defaultStrokeWidth,
                color: currentColor
            ))
        case .rectangle:
            return .rectangle(RectAnnotation(rect: rect, strokeWidth: Self.defaultStrokeWidth, color: currentColor))
        case .blur, .pixelate:
            guard let kind = currentTool.censorKind else { return nil }
            return .censor(CensorAnnotation(rect: rect, kind: kind, scale: censorScale))
        case .select, .counter, .text:
            return nil
        }
    }

    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationId else { return }
        document.removeAnnotation(withId: id)
        select(nil)
        documentDidChange()
    }

    func applyColorToSelection(_ color: RGBAColor) {
        guard let element = selectedAnnotation, element.supportsColor else { return }
        document.updateAnnotation(element.withColor(color))
        documentDidChange()
    }

    @objc func undo(_ sender: Any?) {
        guard !hasActiveInlineText else { return }
        document.undo()
        documentDidChange()
    }

    @objc func redo(_ sender: Any?) {
        guard !hasActiveInlineText else { return }
        document.redo()
        documentDidChange()
    }

    @objc func delete(_ sender: Any?) {
        deleteSelectedAnnotation()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])

        if event.keyCode == ShotKeyCode.escape {
            window?.performClose(nil)
            return
        }

        if modifiers.isEmpty, event.keyCode == ShotKeyCode.delete || event.keyCode == ShotKeyCode.forwardDelete, selectedAnnotationId != nil {
            deleteSelectedAnnotation()
            return
        }

        if modifiers.isEmpty, !event.modifierFlags.contains(.shift),
           let number = ShotKeyCode.toolKeyCodes[event.keyCode],
           let tool = ToolMode.forShortcutNumber(number) {
            delegate?.canvasView(self, didRequestTool: tool)
            return
        }

        super.keyDown(with: event)
    }

    private func drawCensorPreview(ctx: CGContext, rect: CGRect, tool: ToolMode) {
        ctx.setFillColor(NSColor(white: 0.45, alpha: 0.45).cgColor)
        ctx.fill(rect)

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        let caption = "\(tool.displayName) · \(CensorStrength.nearest(to: censorScale).displayName)"
        let attributed = NSAttributedString(
            string: caption,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        let textSize = attributed.size()
        guard rect.width > textSize.width + 20, rect.height > textSize.height + 12 else { return }

        let pill = CGRect(
            x: rect.midX - (textSize.width + 18) / 2,
            y: rect.midY - (textSize.height + 8) / 2,
            width: textSize.width + 18,
            height: textSize.height + 8
        )
        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.8).cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
        ctx.fillPath()

        MonoStyle.draw(attributed, at: CGPoint(x: pill.minX + 9, y: pill.minY + 4), in: ctx)
    }

    private func startInlineText(at point: CGPoint) {
        select(nil)
        activeTextOrigin = point

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 6, width: 220, height: 30))
        field.placeholderString = ShotText.textPlaceholder
        field.font = TextMetrics.font(ofSize: Self.textFontSize)
        field.textColor = NSColor(cgColor: currentColor.cgColor) ?? .labelColor
        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85).cgColor
        field.layer?.cornerRadius = 6
        field.layer?.borderColor = currentColor.cgColor
        field.layer?.borderWidth = 1.5
        field.target = self
        field.action = #selector(inlineTextSubmitted)
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    @objc private func inlineTextSubmitted() {
        commitInlineText()
    }

    func commitInlineText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineText()
        if !text.isEmpty {
            add(.text(TextAnnotation(origin: activeTextOrigin, text: text, fontSize: Self.textFontSize, color: currentColor)))
        }
    }

    func cancelInlineText() {
        endInlineText()
    }

    private func endInlineText() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        delegate?.canvasViewDidFinishTextEntry(self)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        AnnotationRenderer.draw(document.annotations, in: ctx)

        if isDrawing, let start = dragStart, let current = dragCurrent {
            drawPreview(in: ctx, from: start, to: current)
        }

        if let element = selectedAnnotation {
            let box = element.boundingBox
            ctx.saveGState()
            ctx.setStrokeColor(MonoStyle.accent.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.stroke(box)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.restoreGState()
            MonoStyle.drawHandles(in: ctx, around: box)
        }
    }

    private func drawPreview(in ctx: CGContext, from start: CGPoint, to current: CGPoint) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        switch currentTool {
        case .arrow, .curvedArrow:
            let control = currentTool == .curvedArrow ? ArrowAnnotation.defaultControlPoint(from: start, to: current) : nil
            AnnotationRenderer.drawArrow(
                ArrowAnnotation(start: start, end: current, controlPoint: control, strokeWidth: Self.defaultStrokeWidth, color: currentColor),
                in: ctx
            )
        case .rectangle:
            AnnotationRenderer.drawRectangle(
                RectAnnotation(rect: rect, strokeWidth: Self.defaultStrokeWidth, color: currentColor),
                in: ctx
            )
        case .blur, .pixelate:
            drawCensorPreview(ctx: ctx, rect: rect, tool: currentTool)
        case .select, .counter, .text:
            break
        }
    }
}

extension CanvasView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = activeTextField else { return }
        let size = field.intrinsicContentSize
        let maxWidth = bounds.width - activeTextOrigin.x - 16
        field.frame.size.width = max(200, min(maxWidth, size.width + 28))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelInlineText()
            return true
        }
        return false
    }
}

extension CanvasView: NSMenuItemValidation, NSToolbarItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validate(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validate(item.action)
    }

    private func validate(_ action: Selector?) -> Bool {
        switch action {
        case #selector(undo(_:)): return !hasActiveInlineText && document.canUndo
        case #selector(redo(_:)): return !hasActiveInlineText && document.canRedo
        case #selector(delete(_:)): return selectedAnnotationId != nil
        default: return true
        }
    }
}
