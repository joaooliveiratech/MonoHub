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

    private let inset: CGFloat = 8
    private let tileCornerRadius: CGFloat = 16

    private let hostView = NSView()
    private let glassTile = NSGlassEffectView()
    private let fallbackTile = NSView()
    private let borderOverlay = NSView()
    private let badgePill = NSGlassEffectView()
    private let badgeStack = NSStackView()
    private let badgeIcon = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")

    private var isPresented = false
    private var currentAction: WindowAction?

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

        hostView.wantsLayer = true

        // Native macOS 27 Liquid Glass preview tile
        glassTile.style = .clear
        glassTile.cornerRadius = tileCornerRadius
        glassTile.wantsLayer = true
        glassTile.alphaValue = 0

        // Reduce-transparency high-contrast fallback surface
        fallbackTile.wantsLayer = true
        fallbackTile.layer?.cornerRadius = tileCornerRadius
        fallbackTile.layer?.cornerCurve = .continuous
        fallbackTile.alphaValue = 0
        fallbackTile.isHidden = true

        // Crisp continuous hairline border for luminous edge definition
        borderOverlay.wantsLayer = true
        borderOverlay.layer?.cornerRadius = tileCornerRadius
        borderOverlay.layer?.cornerCurve = .continuous
        borderOverlay.layer?.borderWidth = 1.5
        borderOverlay.autoresizingMask = [.width, .height]

        // Centered Liquid Glass action pill badge
        badgePill.style = .regular
        badgePill.wantsLayer = true

        badgeIcon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        badgeIcon.contentTintColor = .labelColor

        badgeLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        badgeLabel.textColor = .labelColor
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.maximumNumberOfLines = 1

        badgeStack.orientation = .horizontal
        badgeStack.alignment = .centerY
        badgeStack.spacing = 6
        badgeStack.edgeInsets = NSEdgeInsets(top: 7, left: 13, bottom: 7, right: 14)
        badgeStack.setViews([badgeIcon, badgeLabel], in: .leading)
        badgePill.contentView = badgeStack

        let tileContent = NSView()
        tileContent.wantsLayer = true
        tileContent.addSubview(borderOverlay)
        tileContent.addSubview(badgePill)
        glassTile.contentView = tileContent

        hostView.addSubview(fallbackTile)
        hostView.addSubview(glassTile)
        contentView = hostView
    }

    func show(_ quartzRect: CGRect, on screen: ScreenLayout, primaryScreenHeight: CGFloat) {
        show(quartzRect, action: nil, on: screen, primaryScreenHeight: primaryScreenHeight)
    }

    func show(_ quartzRect: CGRect, action: WindowAction?, on screen: ScreenLayout, primaryScreenHeight: CGFloat) {
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

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        applySurfaceColors(reduceTransparency: reduceTransparency)
        configureBadge(for: action, in: tileFrame.size)

        let activeTile: NSView = reduceTransparency ? fallbackTile : glassTile
        let inactiveTile: NSView = reduceTransparency ? glassTile : fallbackTile
        inactiveTile.isHidden = true
        inactiveTile.alphaValue = 0
        activeTile.isHidden = false

        if reduceTransparency {
            if borderOverlay.superview !== fallbackTile {
                fallbackTile.addSubview(borderOverlay)
                fallbackTile.addSubview(badgePill)
            }
        } else if let tileContent = glassTile.contentView, borderOverlay.superview !== tileContent {
            tileContent.addSubview(borderOverlay)
            tileContent.addSubview(badgePill)
        }

        if appears {
            let startFrame = reduceMotion ? tileFrame : tileFrame.insetBy(dx: 12, dy: 12)
            activeTile.frame = startFrame
            borderOverlay.frame = CGRect(origin: .zero, size: startFrame.size)
            layoutBadge(in: startFrame.size)
            activeTile.alphaValue = 0
        }

        if !isVisible {
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : (appears ? 0.16 : 0.18)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            activeTile.animator().frame = tileFrame
            activeTile.animator().alphaValue = 1
            borderOverlay.animator().frame = CGRect(origin: .zero, size: tileFrame.size)
            layoutBadge(in: tileFrame.size, animated: !reduceMotion)
        }
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        currentAction = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let activeTile: NSView = glassTile.isHidden ? fallbackTile : glassTile

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            activeTile.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                guard let panel = SnapPreviewPanel.loaded, !panel.isPresented else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func applySurfaceColors(reduceTransparency: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            if reduceTransparency {
                fallbackTile.layer?.backgroundColor = accent.withAlphaComponent(0.24).cgColor
                borderOverlay.layer?.borderColor = accent.withAlphaComponent(0.85).cgColor
            } else {
                glassTile.tintColor = accent.withAlphaComponent(0.16)
                borderOverlay.layer?.borderColor = accent.withAlphaComponent(0.65).cgColor
            }
        }
    }

    private func configureBadge(for action: WindowAction?, in tileSize: CGSize) {
        guard let action, tileSize.width >= 150, tileSize.height >= 72 else {
            badgePill.isHidden = true
            currentAction = action
            return
        }
        badgePill.isHidden = false
        if currentAction != action {
            currentAction = action
            badgeIcon.image = NSImage(systemSymbolName: action.sfSymbol, accessibilityDescription: nil)
            badgeLabel.stringValue = action.displayName
        }
        let pillSize = badgeStack.fittingSize
        badgePill.setFrameSize(pillSize)
        badgePill.cornerRadius = pillSize.height / 2
    }

    private func layoutBadge(in tileSize: CGSize, animated: Bool = false) {
        guard !badgePill.isHidden else { return }
        let pillSize = badgePill.frame.size
        let origin = CGPoint(
            x: ((tileSize.width - pillSize.width) / 2).rounded(),
            y: ((tileSize.height - pillSize.height) / 2).rounded()
        )
        let target = CGRect(origin: origin, size: pillSize)
        if animated {
            badgePill.animator().frame = target
        } else {
            badgePill.frame = target
        }
    }
}
