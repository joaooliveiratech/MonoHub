import AppKit
import CoreGraphics
import QuartzCore

@MainActor
final class SnapPreviewPanel: NSPanel {
    private static var loaded: SnapPreviewPanel?

    static var shared: SnapPreviewPanel {
        if let loaded { return loaded }
        let panel = SnapPreviewPanel()
        loaded = panel
        return panel
    }

    static func release() {
        loaded?.orderOut(nil)
        loaded = nil
    }

    private let inset: CGFloat = 6
    private let tileLayer = CALayer()
    private var isPresented = false

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        tileLayer.cornerRadius = 14
        tileLayer.cornerCurve = .continuous
        tileLayer.borderWidth = 1.5
        tileLayer.opacity = 0

        let host = NSView()
        host.wantsLayer = true
        host.layer?.addSublayer(tileLayer)
        contentView = host
    }

    func show(_ quartzRect: CGRect, on screen: ScreenLayout, primaryScreenHeight: CGFloat) {
        let screenFrame = ScreenLayout.flipped(screen.bounds, primaryHeight: primaryScreenHeight)
        let tileFrame = ScreenLayout.flipped(quartzRect, primaryHeight: primaryScreenHeight)
            .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            .insetBy(dx: inset, dy: inset)

        let changesScreen = !frame.equalTo(screenFrame)
        let appears = !isPresented || changesScreen
        isPresented = true

        if changesScreen {
            setFrame(screenFrame, display: false)
        }
        if appears {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                tileLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                tileLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
            }
            tileLayer.frame = tileFrame
            CATransaction.commit()
        }
        if !isVisible {
            orderFrontRegardless()
        }

        animate(duration: 0.18) {
            tileLayer.frame = tileFrame
            tileLayer.opacity = 1
        }
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        animate(duration: 0.12) {
            tileLayer.opacity = 0
        } completion: {
            guard let panel = SnapPreviewPanel.loaded, !panel.isPresented else { return }
            panel.orderOut(nil)
        }
    }

    private func animate(duration: CFTimeInterval, _ changes: () -> Void, completion: (@MainActor @Sendable () -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if let completion {
            CATransaction.setCompletionBlock {
                MainActor.assumeIsolated(completion)
            }
        }
        changes()
        CATransaction.commit()
    }
}
