import AppKit
import CoreGraphics

final class PinCoordinator {
    static let shared = PinCoordinator()
    private var activeControllers: [PinWindowController] = []

    private init() {}

    func pin(image: CGImage, scaleFactor: CGFloat) {
        let controller = PinWindowController(image: image, scaleFactor: scaleFactor)
        activeControllers.append(controller)
        controller.showWindow(nil)
    }

    func remove(_ controller: PinWindowController) {
        activeControllers.removeAll(where: { $0 === controller })
    }

    func closeAll() {
        let controllers = activeControllers
        activeControllers.removeAll()
        for controller in controllers {
            controller.close()
        }
    }
}

final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let image: CGImage

    init(image: CGImage, scaleFactor: CGFloat) {
        self.image = image

        let logicalSize = CGSize(width: CGFloat(image.width) / scaleFactor, height: CGFloat(image.height) / scaleFactor)
        let panel = PinPanel(
            contentRect: Self.initialFrame(for: logicalSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = logicalSize
        panel.minSize = NSSize(width: 48, height: 48)

        super.init(window: panel)
        panel.delegate = self

        let content = PinContentView(image: image)
        content.onClose = { [weak self] in self?.close() }
        panel.contentView = content
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func initialFrame(for logicalSize: CGSize) -> NSRect {
        let visible = NSScreen.underPointer?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fit = min(1, (visible.width * 0.8) / logicalSize.width, (visible.height * 0.8) / logicalSize.height)
        let size = CGSize(width: logicalSize.width * fit, height: logicalSize.height * fit)
        let pointer = NSEvent.mouseLocation
        let origin = CGPoint(
            x: min(max(visible.minX, pointer.x - size.width / 2), visible.maxX - size.width),
            y: min(max(visible.minY, pointer.y - size.height / 2), visible.maxY - size.height)
        )
        return NSRect(origin: origin.rounded, size: size)
    }

    func windowWillClose(_ notification: Notification) {
        PinCoordinator.shared.remove(self)
    }
}

final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == ShotKeyCode.escape {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class PinContentView: NSView {
    var onClose: (() -> Void)?

    private let image: CGImage
    private let closeButton = NSButton()
    private var hoverArea: NSTrackingArea?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        closeButton.bezelStyle = .glass
        closeButton.borderShape = .circle
        closeButton.image = MonoStyle.symbol("xmark", pointSize: 11, weight: .bold, description: ShotText.pinClose)
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = ShotText.pinClose
        closeButton.alphaValue = 0
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        ])

        let menu = NSMenu()
        let copyItem = NSMenuItem(title: ShotText.pinCopy, action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.image = MonoStyle.symbol("doc.on.doc")
        menu.addItem(copyItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: ShotText.pinClose, action: #selector(closeClicked), keyEquivalent: "")
        closeItem.target = self
        closeItem.image = MonoStyle.symbol("xmark")
        menu.addItem(closeItem)
        self.menu = menu

        setAccessibilityRole(.image)
        setAccessibilityLabel(ShotText.menuPin)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setCloseButtonVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setCloseButtonVisible(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose?()
        } else {
            window?.performDrag(with: event)
        }
    }

    private func setCloseButtonVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    @objc func copy(_ sender: Any?) {
        let image = image
        Task {
            guard let data = try? await ImageEncoder.encodeInBackground(image, as: .png) else { return }
            PasteboardWriter.write(pngData: data)
            Toast.show(ShotText.toastCopied, symbol: "doc.on.clipboard", anchor: .pointerScreen)
        }
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
