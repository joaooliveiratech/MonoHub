import AppKit

enum ToastAnchor {
    case window(NSWindow)
    case screen(NSScreen)

    static var pointerScreen: ToastAnchor? {
        NSScreen.underPointer.map(ToastAnchor.screen)
    }
}

enum Toast {
    private static var activePanel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ message: String, symbol: String? = nil, anchor: ToastAnchor?) {
        guard let anchor else { return }

        let pill = GlassPill(font: .systemFont(ofSize: 13, weight: .semibold))
        pill.configure(text: message, symbol: symbol)

        let panel = activePanel ?? makePanel()
        panel.parent?.removeChildWindow(panel)
        panel.contentView = pill
        panel.setContentSize(pill.frame.size)
        panel.setFrameOrigin(origin(for: pill.frame.size, anchor: anchor))
        activePanel = panel

        if case .window(let window) = anchor {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()

        dismissTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    static func dismissAndRelease() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel = activePanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        activePanel = nil
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.alphaValue = 0
        return panel
    }

    private static func origin(for size: CGSize, anchor: ToastAnchor) -> CGPoint {
        let area: CGRect
        let topInset: CGFloat
        switch anchor {
        case .window(let window):
            area = window.frame
            topInset = window.frame.height - window.contentLayoutRect.height + 16
        case .screen(let screen):
            area = screen.visibleFrame
            topInset = 24
        }
        return CGPoint(x: area.midX - size.width / 2, y: area.maxY - topInset - size.height).rounded
    }
}
