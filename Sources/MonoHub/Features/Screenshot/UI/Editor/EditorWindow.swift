import AppKit
import CoreGraphics
import UniformTypeIdentifiers

protocol EditorWindowControllerDelegate: AnyObject {
    func editorWindowControllerDidClose(_ controller: EditorWindowController)
}

final class CenteringClipView: NSClipView {

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        let magnification = enclosingScrollView?.magnification ?? 1
        let insets = enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let topInset = insets.top / magnification
        let bottomInset = insets.bottom / magnification

        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2.0
        }
        let visibleHeight = rect.height - topInset - bottomInset
        if visibleHeight > docFrame.height {
            rect.origin.y = (docFrame.height - visibleHeight) / 2.0 - bottomInset
        }
        return rect
    }
}

final class EditorWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

private extension NSToolbarItem.Identifier {
    static let tools = Self("monoshot.tools")
    static let color = Self("monoshot.color")
    static let intensity = Self("monoshot.intensity")
    static let undo = Self("monoshot.undo")
    static let redo = Self("monoshot.redo")
    static let delete = Self("monoshot.delete")
    static let recognizeText = Self("monoshot.ocr")
    static let pin = Self("monoshot.pin")
    static let save = Self("monoshot.save")
    static let copy = Self("monoshot.copy")
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let screenshotDoc: ScreenshotDocument
    weak var editorDelegate: (any EditorWindowControllerDelegate)?

    private let canvasView: CanvasView
    private let backdropView: ScreenshotBackdropView
    private let documentContainer: NSView
    private let scrollView = NSScrollView()
    private let clipView = CenteringClipView()

    private weak var toolGroup: NSToolbarItemGroup?
    private weak var colorItem: NSToolbarItem?
    private weak var intensityItem: NSToolbarItem?
    private let colorWell = NSColorWell(style: .minimal)
    private var magnificationObserver: (any NSObjectProtocol)?

    private static let minZoom: CGFloat = 0.1
    private static let maxZoom: CGFloat = 16.0
    private static let zoomStep: CGFloat = 1.25

    init(document: ScreenshotDocument) {
        self.screenshotDoc = document
        let documentRect = NSRect(origin: .zero, size: document.logicalSize)
        self.documentContainer = NSView(frame: documentRect)
        self.backdropView = ScreenshotBackdropView(frame: documentRect)
        self.canvasView = CanvasView(document: document)

        let window = EditorWindow(
            contentRect: Self.initialContentRect(for: document.logicalSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ShotText.defaultFileStem(for: document.capturedAt)
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 420)
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.titlebarSeparatorStyle = .none

        super.init(window: window)
        window.delegate = self
        setupCanvas()
        setupToolbar()
        updateSubtitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func initialContentRect(for imageSize: CGSize) -> NSRect {
        let screen = (NSScreen.underPointer ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(screen.width * 0.9, max(980, imageSize.width + 80))
        let height = min(screen.height * 0.88, max(480, imageSize.height + 140))
        return NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        zoomToFitIfNeeded()
    }

    private func setupCanvas() {
        guard let window, let contentView = window.contentView else { return }

        backdropView.image = screenshotDoc.censoredBaseImage
        backdropView.autoresizingMask = [.width, .height]
        canvasView.autoresizingMask = [.width, .height]
        canvasView.backdrop = backdropView
        canvasView.delegate = self

        documentContainer.wantsLayer = true
        documentContainer.layer?.shadowColor = NSColor.black.cgColor
        documentContainer.layer?.shadowOpacity = 0.28
        documentContainer.layer?.shadowRadius = 18
        documentContainer.layer?.shadowOffset = CGSize(width: 0, height: -6)
        documentContainer.layer?.borderWidth = 0.5
        documentContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        documentContainer.addSubview(backdropView)
        documentContainer.addSubview(canvasView)

        scrollView.frame = contentView.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Self.minZoom
        scrollView.maxMagnification = Self.maxZoom
        scrollView.automaticallyAdjustsContentInsets = true

        clipView.drawsBackground = false
        clipView.postsBoundsChangedNotifications = true
        scrollView.contentView = clipView
        scrollView.documentView = documentContainer
        contentView.addSubview(scrollView)

        magnificationObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSubtitle() }
        }

        window.makeFirstResponder(canvasView)
    }

    private func updateSubtitle() {
        window?.subtitle = ShotText.editorSubtitle(
            width: screenshotDoc.baseImage.width,
            height: screenshotDoc.baseImage.height,
            zoomPercent: Int((scrollView.magnification * 100).rounded())
        )
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MonoShotEditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar

        colorWell.supportsAlpha = false
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 28),
            colorWell.heightAnchor.constraint(equalToConstant: 28)
        ])
        colorWell.color = NSColor(cgColor: canvasView.currentColor.cgColor) ?? .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        colorWell.toolTip = ShotText.colorTooltip

        reflectTool(canvasView.currentTool)
    }

    func selectTool(_ tool: ToolMode) {
        if canvasView.hasActiveInlineText {
            canvasView.commitInlineText()
        }
        canvasView.currentTool = tool
        reflectTool(tool)
    }

    private func reflectTool(_ tool: ToolMode) {
        toolGroup?.selectedIndex = ToolMode.allCases.firstIndex(of: tool) ?? 0
        colorItem?.isHidden = tool.isCensor
        intensityItem?.isHidden = !tool.isCensor
    }

    @objc private func toolGroupChanged(_ sender: NSToolbarItemGroup) {
        guard ToolMode.allCases.indices.contains(sender.selectedIndex) else { return }
        selectTool(ToolMode.allCases[sender.selectedIndex])
    }

    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        guard ToolMode.allCases.indices.contains(sender.tag) else { return }
        selectTool(ToolMode.allCases[sender.tag])
    }

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        guard let color = RGBAColor(nsColor: sender.color) else { return }
        canvasView.currentColor = color
        canvasView.applyColorToSelection(color)
    }

    @objc private func setCensorStrength(_ sender: NSMenuItem) {
        guard CensorStrength.allCases.indices.contains(sender.tag) else { return }
        canvasView.censorScale = CensorStrength.allCases[sender.tag].scale
    }

    private func setZoom(_ magnification: CGFloat, animated: Bool = true) {
        let clamped = min(Self.maxZoom, max(Self.minZoom, magnification))
        let center = CGPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                scrollView.animator().setMagnification(clamped, centeredAt: center)
            }
        } else {
            scrollView.setMagnification(clamped, centeredAt: center)
        }
        updateSubtitle()
    }

    private func fitMagnification() -> CGFloat {
        let insets = scrollView.contentInsets
        let available = CGSize(
            width: scrollView.bounds.width - insets.left - insets.right - 48,
            height: scrollView.bounds.height - insets.top - insets.bottom - 48
        )
        let size = screenshotDoc.logicalSize
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(available.width / size.width, available.height / size.height)
    }

    private func zoomToFitIfNeeded() {
        window?.layoutIfNeeded()
        setZoom(min(1, fitMagnification()), animated: false)
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(scrollView.magnification * Self.zoomStep)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(scrollView.magnification / Self.zoomStep)
    }

    @objc func zoomImageToActualSize(_ sender: Any?) {
        setZoom(1)
    }

    @objc func zoomImageToFit(_ sender: Any?) {
        setZoom(fitMagnification())
    }

    private func commitPendingText() {
        if canvasView.hasActiveInlineText {
            canvasView.commitInlineText()
        }
    }

    @objc func copy(_ sender: Any?) {
        commitPendingText()
        let document = screenshotDoc
        Task {
            if await document.copyToPasteboard() {
                Toast.show(ShotText.toastCopied, symbol: "doc.on.clipboard", anchor: .pointerScreen)
            }
        }
        close()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let window else { return }
        commitPendingText()
        let preferences = ScreenshotPreferences.shared
        let defaultFormat = preferences.defaultExportFormat

        let panel = NSSavePanel()
        panel.allowedContentTypes = ExportFormat.allCases.map(\.contentType)
        panel.showsContentTypes = true
        panel.currentContentType = defaultFormat.contentType
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(ShotText.defaultFileStem(for: screenshotDoc.capturedAt)).\(defaultFormat.fileExtension)"
        panel.directoryURL = URL(fileURLWithPath: preferences.effectiveSaveDirectory, isDirectory: true)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let format = panel.currentContentType.flatMap(ExportFormat.init(contentType:))
                ?? ExportFormat.inferred(fromExtension: url.pathExtension)
            self.export(to: url, format: format)
        }
    }

    private func export(to url: URL, format: ExportFormat) {
        let preferences = ScreenshotPreferences.shared
        preferences.defaultExportFormat = format

        let image: CGImage
        do {
            image = try screenshotDoc.exportImage(downscaleRetina: preferences.downscaleRetina)
        } catch {
            ScreenshotLogger.error("image export failed", error)
            Toast.show(ShotText.toastSaveFailed, symbol: "exclamationmark.triangle", anchor: window.map(ToastAnchor.window))
            return
        }

        let quality = preferences.jpegQuality
        Task { [weak self] in
            let anchor = self?.window.map(ToastAnchor.window) ?? .pointerScreen
            do {
                try await ImageEncoder.write(image, as: format, quality: quality, to: url)
                ScreenshotPreferences.shared.updateLastSaveDirectory(url.deletingLastPathComponent().path)
                Toast.show(ShotText.toastSavedSuccess, symbol: "checkmark.circle", anchor: anchor)
            } catch {
                ScreenshotLogger.error("image export failed", error)
                Toast.show(ShotText.toastSaveFailed, symbol: "exclamationmark.triangle", anchor: anchor)
            }
        }
    }

    @objc func pinToScreen(_ sender: Any?) {
        commitPendingText()
        guard let finalImage = screenshotDoc.renderCompositeImage() else { return }
        PinCoordinator.shared.pin(image: finalImage, scaleFactor: screenshotDoc.scaleFactor)
        close()
    }

    @objc func recognizeText(_ sender: Any?) {
        commitPendingText()
        guard let finalImage = screenshotDoc.renderCompositeImage() else { return }
        let anchor = window.map(ToastAnchor.window)
        Task {
            await TextRecognitionFeedback.recognizeAndCopy(finalImage, anchor: anchor)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let magnificationObserver {
            NotificationCenter.default.removeObserver(magnificationObserver)
            self.magnificationObserver = nil
        }
        if canvasView.hasActiveInlineText {
            canvasView.cancelInlineText()
        }
        editorDelegate?.editorWindowControllerDidClose(self)
    }
}

extension EditorWindowController: CanvasViewDelegate {
    func canvasView(_ canvas: CanvasView, didSelect element: AnnotationElement?) {
        if let color = element?.color {
            colorWell.color = NSColor(cgColor: color.cgColor) ?? colorWell.color
            canvas.currentColor = color
        }
    }

    func canvasViewDidFinishTextEntry(_ canvas: CanvasView) {
        selectTool(.select)
    }

    func canvasView(_ canvas: CanvasView, didRequestTool tool: ToolMode) {
        selectTool(tool)
    }
}

extension EditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectToolFromMenu(_:)):
            menuItem.state = ToolMode.allCases.firstIndex(of: canvasView.currentTool) == menuItem.tag ? .on : .off
        case #selector(setCensorStrength(_:)):
            let current = CensorStrength.nearest(to: canvasView.censorScale)
            menuItem.state = CensorStrength.allCases.firstIndex(of: current) == menuItem.tag ? .on : .off
            return canvasView.currentTool.isCensor
        case #selector(zoomIn(_:)):
            return scrollView.magnification < Self.maxZoom
        case #selector(zoomOut(_:)):
            return scrollView.magnification > Self.minZoom
        default:
            break
        }
        return true
    }
}

extension EditorWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.tools, .color, .intensity, .space, .undo, .redo, .delete, .flexibleSpace, .recognizeText, .pin, .save, .copy]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .tools:
            let tools = ToolMode.allCases
            let group = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                images: tools.map { MonoStyle.symbol($0.iconName, description: $0.displayName) ?? NSImage() },
                selectionMode: .selectOne,
                labels: tools.map(\.displayName),
                target: self,
                action: #selector(toolGroupChanged(_:))
            )
            group.role = .valueSelection
            group.controlRepresentation = .expanded
            group.visibilityPriority = .user
            group.label = ShotText.toolbarTools
            group.paletteLabel = ShotText.toolbarTools
            for (tool, item) in zip(tools, group.subitems) {
                item.toolTip = "\(tool.displayName) (\(tool.shortcutNumber))"
            }
            group.selectedIndex = tools.firstIndex(of: canvasView.currentTool) ?? 0
            if flag { toolGroup = group }
            return group

        case .color:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = flag ? colorWell : NSColorWell(style: .minimal)
            item.label = ShotText.toolbarColor
            item.paletteLabel = ShotText.toolbarColor
            item.toolTip = ShotText.colorTooltip
            item.isHidden = canvasView.currentTool.isCensor
            if flag { colorItem = item }
            return item

        case .intensity:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.image = MonoStyle.symbol("slider.horizontal.3", description: ShotText.toolbarIntensity)
            item.label = ShotText.toolbarIntensity
            item.paletteLabel = ShotText.toolbarIntensity
            item.toolTip = ShotText.intensityTooltip
            item.showsIndicator = true
            let menu = NSMenu()
            for (index, strength) in CensorStrength.allCases.enumerated() {
                let entry = NSMenuItem(title: strength.displayName, action: #selector(setCensorStrength(_:)), keyEquivalent: "")
                entry.tag = index
                entry.target = self
                menu.addItem(entry)
            }
            item.menu = menu
            item.isHidden = !canvasView.currentTool.isCensor
            if flag { intensityItem = item }
            return item

        case .undo:
            return actionItem(itemIdentifier, symbol: "arrow.uturn.backward", label: ShotText.toolbarUndo,
                              tooltip: ShotText.undoTooltip, action: #selector(CanvasView.undo(_:)))
        case .redo:
            return actionItem(itemIdentifier, symbol: "arrow.uturn.forward", label: ShotText.toolbarRedo,
                              tooltip: ShotText.redoTooltip, action: #selector(CanvasView.redo(_:)))
        case .delete:
            return actionItem(itemIdentifier, symbol: "trash", label: ShotText.toolbarDelete,
                              tooltip: ShotText.deleteTooltip, action: #selector(CanvasView.delete(_:)))
        case .recognizeText:
            return actionItem(itemIdentifier, symbol: "text.viewfinder", label: ShotText.toolbarText,
                              tooltip: ShotText.ocrTooltip, action: #selector(recognizeText(_:)))
        case .pin:
            return actionItem(itemIdentifier, symbol: "pin", label: ShotText.toolbarPin,
                              tooltip: ShotText.pinTooltip, action: #selector(pinToScreen(_:)))
        case .save:
            return actionItem(itemIdentifier, symbol: "square.and.arrow.down", label: ShotText.saveButtonTitle,
                              tooltip: ShotText.saveTooltip, action: #selector(saveDocument(_:)))
        case .copy:
            let item = actionItem(itemIdentifier, symbol: nil, label: ShotText.copyButtonTitle,
                                  tooltip: ShotText.copyTooltip, action: #selector(copy(_:)))
            item.title = ShotText.copyButtonTitle
            item.target = self
            item.style = .prominent
            item.visibilityPriority = .high
            return item

        default:
            return nil
        }
    }

    private func actionItem(
        _ identifier: NSToolbarItem.Identifier,
        symbol: String?,
        label: String,
        tooltip: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = symbol.flatMap { MonoStyle.symbol($0, description: label) }
        item.label = label
        item.paletteLabel = label
        item.toolTip = tooltip
        item.action = action
        item.target = nil
        item.isBordered = true
        item.autovalidates = true
        return item
    }
}

extension RGBAColor {
    init?(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent, a: srgb.alphaComponent)
    }
}
