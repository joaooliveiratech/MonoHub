import AppKit
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
final class XDRAndOverlayEngine {
    static let shared = XDRAndOverlayEngine()

    private var dimmingWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var xdrWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var blackoutDisplayIDs: Set<CGDirectDisplayID> = []
    private var overlayAlphas: [CGDirectDisplayID: CGFloat] = [:]
    private var activeXDRFactors: [CGDirectDisplayID: Float] = [:]

    private init() {}

    func setOverlayDimmingAlpha(displayID: CGDirectDisplayID, alpha: CGFloat) {
        let clamped = DisplayControlGate.isOpen ? max(0.0, min(1.0, alpha)) : 0.0
        overlayAlphas[displayID] = clamped
        updateDimmingWindow(for: displayID)
    }

    func setBlackout(displayID: CGDirectDisplayID, enabled: Bool) {
        if enabled {
            guard DisplayControlGate.isOpen else { return }

            let totalScreens = NSScreen.screens.count
            if totalScreens <= 1 || blackoutDisplayIDs.count + 1 >= totalScreens {

                blackoutDisplayIDs.insert(displayID)
                updateDimmingWindow(for: displayID)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    if self?.blackoutDisplayIDs.contains(displayID) == true {
                        self?.setBlackout(displayID: displayID, enabled: false)
                    }
                }
                return
            }
            blackoutDisplayIDs.insert(displayID)
        } else {
            blackoutDisplayIDs.remove(displayID)
        }
        updateDimmingWindow(for: displayID)
    }

    func isBlackedOut(displayID: CGDirectDisplayID) -> Bool {
        blackoutDisplayIDs.contains(displayID)
    }

    func restoreAllBlackouts() {
        let ids = Array(blackoutDisplayIDs)
        blackoutDisplayIDs.removeAll()
        for id in ids {
            updateDimmingWindow(for: id)
        }
    }

    func closeAllOverlays() {
        for win in dimmingWindows.values {
            win.orderOut(nil)
        }
        dimmingWindows.removeAll()

        for win in xdrWindows.values {
            win.orderOut(nil)
        }
        xdrWindows.removeAll()

        blackoutDisplayIDs.removeAll()
        overlayAlphas.removeAll()
        activeXDRFactors.removeAll()
    }

    private func updateDimmingWindow(for displayID: CGDirectDisplayID) {
        guard !AppInfo.isRunningTests else { return }

        let isBlackout = blackoutDisplayIDs.contains(displayID)
        let effectiveAlpha = isBlackout ? 1.0 : (overlayAlphas[displayID] ?? 0.0)

        if effectiveAlpha <= 0.005 {
            if let win = dimmingWindows.removeValue(forKey: displayID) {
                win.orderOut(nil)
            }
            return
        }

        guard let screen = screen(for: displayID) else { return }

        let window: NSWindow
        if let existing = dimmingWindows[displayID] {
            window = existing
            window.setFrame(screen.frame, display: true)
        } else {
            let newWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWin.isReleasedWhenClosed = false
            newWin.level = .screenSaver
            newWin.ignoresMouseEvents = true
            newWin.isOpaque = false
            newWin.hasShadow = false
            newWin.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            dimmingWindows[displayID] = newWin
            window = newWin
        }

        window.backgroundColor = NSColor.black.withAlphaComponent(effectiveAlpha)
        window.orderFrontRegardless()
    }

    func setXDRBoost(displayID: CGDirectDisplayID, factor: Float, enabled: Bool) {
        let clamped = (enabled && DisplayControlGate.isOpen) ? max(1.0, min(2.0, factor)) : 1.0
        activeXDRFactors[displayID] = clamped

        guard !AppInfo.isRunningTests else { return }

        if clamped <= 1.01 {
            if let win = xdrWindows.removeValue(forKey: displayID) {
                win.orderOut(nil)
            }
            return
        }

        guard let screen = screen(for: displayID) else { return }

        let window: NSWindow
        if let existing = xdrWindows[displayID] {
            window = existing
            window.setFrame(screen.frame, display: true)
        } else {
            let newWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWin.isReleasedWhenClosed = false
            newWin.level = .statusBar
            newWin.ignoresMouseEvents = true
            newWin.isOpaque = false
            newWin.hasShadow = false
            newWin.backgroundColor = .clear
            newWin.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

            let edrView = XDREDRTriggerView(frame: screen.frame)
            newWin.contentView = edrView
            xdrWindows[displayID] = newWin
            window = newWin
        }

        if let edrView = window.contentView as? XDREDRTriggerView {
            edrView.updateBoostFactor(clamped)
        }
        window.orderFrontRegardless()
    }

    func currentXDRBoost(for displayID: CGDirectDisplayID) -> Float {
        activeXDRFactors[displayID] ?? 1.0
    }

    var hasActiveOverlays: Bool {
        !dimmingWindows.isEmpty || !xdrWindows.isEmpty
    }

    func repositionOverlays() {
        guard DisplayControlGate.isOpen else { return }
        for displayID in Array(dimmingWindows.keys) {
            updateDimmingWindow(for: displayID)
        }
        for (displayID, factor) in activeXDRFactors where factor > 1.01 {
            setXDRBoost(displayID: displayID, factor: factor, enabled: true)
        }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return num == displayID
        }
    }
}

private final class XDREDRTriggerView: NSView {
    private let edrLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupEDRLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupEDRLayer()
    }

    private func setupEDRLayer() {
        edrLayer.isOpaque = false
        self.layer = edrLayer
    }

    func updateBoostFactor(_ factor: Float) {
        let extraRatio = CGFloat(max(0.0, min(1.0, factor - 1.0)))

        edrLayer.backgroundColor = CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB(),
            components: [1.0 + extraRatio, 1.0 + extraRatio, 1.0 + extraRatio, 0.002]
        )
    }
}
