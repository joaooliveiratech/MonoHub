import AppKit
import SwiftUI

@MainActor
final class MenuBarPanel: NSPanel {
    static let width: CGFloat = 320
    private static let cornerRadius: CGFloat = 18
    private static let screenMargin: CGFloat = 8
    private static let gapBelowMenuBar: CGFloat = 5

    var onCancel: (() -> Void)?
    private let hostingView: NSHostingView<AnyView>
    private var anchorTop: CGFloat?

    init<Content: View>(content: Content) {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]

        hostingView.sizingOptions = []
        hostingView.rootView = AnyView(
            content
                .frame(width: Self.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] height in
                    self?.resize(toHeight: height)
                }
        )

        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius
        glass.style = .regular
        glass.contentView = hostingView
        contentView = glass
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    func present(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame

        var x = buttonFrame.minX - 4
        x = min(x, visible.maxX - Self.width - Self.screenMargin)
        x = max(x, visible.minX + Self.screenMargin)
        let top = min(buttonFrame.minY, visible.maxY) - Self.gapBelowMenuBar
        anchorTop = top

        setFrame(NSRect(x: x, y: top - 200, width: Self.width, height: 200), display: false)
        contentView?.layoutSubtreeIfNeeded()
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss(completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.tearDown()
                completion()
            }
        }
    }

    func tearDown() {
        orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
        onCancel = nil
        close()
    }

    private func resize(toHeight height: CGFloat) {
        let target = ceil(height)
        guard target > 0, abs(frame.height - target) >= 0.5, let anchorTop else { return }
        setFrame(NSRect(x: frame.minX, y: anchorTop - target, width: Self.width, height: target), display: true)
        invalidateShadow()
    }
}
