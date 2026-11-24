import AppKit
import ApplicationServices
import CoreGraphics
import os
import QuartzCore

@MainActor
final class ModifierDragManager: NSObject {
    static let shared = ModifierDragManager()

    private let logger = Logger(subsystem: "com.antigravity.monohub", category: "ModifierDragManager")

    private enum Mode {
        case move
        case resize(anchorLeft: Bool, anchorTop: Bool)
    }

    private struct Session {
        let window: AXUIElement
        let mode: Mode
        let startPoint: CGPoint
        let startFrame: CGRect
        let enhancedUIPID: pid_t
        let hadEnhancedUI: Bool
        var lastAppliedFrame: CGRect
        var pendingFrame: CGRect?
    }

    private final class EventTap {
        let port: CFMachPort
        let source: CFRunLoopSource
        private(set) var isEnabled = true

        init?(events: [CGEventType]) {
            let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: modifierDragEventCallback,
                userInfo: nil
            ) else { return nil }
            self.port = port
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        func setEnabled(_ enabled: Bool) {
            guard isEnabled != enabled else { return }
            isEnabled = enabled
            CGEvent.tapEnable(tap: port, enable: enabled)
        }

        func forceReenable() {
            isEnabled = true
            CGEvent.tapEnable(tap: port, enable: true)
        }

        func invalidate() {
            setEnabled(false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(port)
        }
    }

    private let minimumSize = CGSize(width: 200, height: 120)
    private var pressTap: EventTap?
    private var trackingTap: EventTap?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isArmed = false
    private var displayLink: CADisplayLink?
    private var session: Session?

    private override init() {
        super.init()
    }

    var isRunning: Bool {
        pressTap != nil
    }

    func reload() {
        let shouldRun = TilePreferencesManager.shared.isModifierDragEnabled && AXIsProcessTrusted()
        guard shouldRun != isRunning else { return }
        stop()
        guard shouldRun else { return }
        guard let pressTap = EventTap(events: [.leftMouseDown, .rightMouseDown]),
              let trackingTap = EventTap(events: [.leftMouseDragged, .leftMouseUp, .rightMouseDragged, .rightMouseUp]) else {
            logger.error("Failed to create modifier drag event tap")
            return
        }
        trackingTap.setEnabled(false)
        pressTap.setEnabled(false)
        self.pressTap = pressTap
        self.trackingTap = trackingTap

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateArming(for: event.modifierFlags)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateArming(for: event.modifierFlags)
            return event
        }
        updateArming(for: NSEvent.modifierFlags)
    }

    func stop() {
        endSession()
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        isArmed = false
        pressTap?.invalidate()
        trackingTap?.invalidate()
        pressTap = nil
        trackingTap = nil
    }

    private func updateArming(for flags: NSEvent.ModifierFlags) {
        let matches = ShortcutModifiers(nsEventModifiers: flags) == TilePreferencesManager.shared.dragModifier.modifiers
        let armed = matches || session != nil
        guard armed != isArmed else { return }
        isArmed = armed
        pressTap?.setEnabled(armed)
    }

    fileprivate func reenableTaps() {
        if isArmed {
            pressTap?.forceReenable()
        }
        if session != nil {
            trackingTap?.forceReenable()
        }
    }

    fileprivate func handle(type: CGEventType, point: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            return beginSession(at: point, flags: flags, isResize: type == .rightMouseDown)
        case .leftMouseDragged, .rightMouseDragged:
            guard session != nil else { return false }
            session?.pendingFrame = targetFrame(for: point)
            displayLink?.isPaused = false
            return true
        case .leftMouseUp, .rightMouseUp:
            guard session != nil else { return false }
            applyPendingFrame()
            endSession()
            return true
        default:
            return false
        }
    }

    private func beginSession(at point: CGPoint, flags: CGEventFlags, isResize: Bool) -> Bool {
        endSession()
        guard ShortcutModifiers(cgEventFlags: flags) == TilePreferencesManager.shared.dragModifier.modifiers else { return false }

        let windows = WindowManager.shared
        guard let window = windows.window(at: point),
              let inspection = windows.inspectWindow(window),
              !inspection.isFullScreen else { return false }

        let frame = inspection.frame
        let mode: Mode = isResize
            ? .resize(anchorLeft: point.x < frame.midX, anchorTop: point.y < frame.midY)
            : .move
        windows.bringToFront(window, pid: inspection.pid)
        let enhanced = windows.suspendEnhancedUserInterface(for: window)
        session = Session(
            window: window,
            mode: mode,
            startPoint: point,
            startFrame: frame,
            enhancedUIPID: enhanced.pid,
            hadEnhancedUI: enhanced.wasEnabled,
            lastAppliedFrame: frame
        )

        let targetScreen = screen(containingQuartzPoint: point, primaryHeight: windows.primaryScreenHeight)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let link = targetScreen?.displayLink(target: self, selector: #selector(displayLinkFired))
        link?.isPaused = true
        link?.add(to: .main, forMode: .common)
        displayLink = link
        trackingTap?.setEnabled(true)
        return true
    }

    private func screen(containingQuartzPoint point: CGPoint, primaryHeight: CGFloat) -> NSScreen? {
        let cocoaPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(cocoaPoint) }
    }

    private func endSession() {
        trackingTap?.setEnabled(false)
        displayLink?.invalidate()
        displayLink = nil
        if let active = session {
            WindowManager.shared.restoreEnhancedUserInterface(pid: active.enhancedUIPID, wasEnabled: active.hadEnhancedUI)
            session = nil
            updateArming(for: NSEvent.modifierFlags)
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard session?.pendingFrame != nil else {
            link.isPaused = true
            return
        }
        applyPendingFrame()
    }

    private func applyPendingFrame() {
        guard let session, let frame = session.pendingFrame else { return }
        self.session?.pendingFrame = nil
        guard !frame.isApproximatelyEqual(to: session.lastAppliedFrame, tolerance: 0.5) else { return }
        self.session?.lastAppliedFrame = frame
        switch session.mode {
        case .move:
            WindowManager.shared.move(session.window, to: frame.origin)
        case .resize:
            WindowManager.shared.resize(session.window, to: frame)
        }
    }

    private func targetFrame(for point: CGPoint) -> CGRect? {
        guard let session else { return nil }
        let dx = point.x - session.startPoint.x
        let dy = point.y - session.startPoint.y
        let start = session.startFrame

        switch session.mode {
        case .move:
            return start.offsetBy(dx: dx, dy: dy)
        case .resize(let anchorLeft, let anchorTop):
            let width = max(minimumSize.width, anchorLeft ? start.width - dx : start.width + dx)
            let height = max(minimumSize.height, anchorTop ? start.height - dy : start.height + dy)
            return CGRect(
                x: anchorLeft ? start.maxX - width : start.minX,
                y: anchorTop ? start.maxY - height : start.minY,
                width: width,
                height: height
            )
        }
    }
}

nonisolated private func modifierDragEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout {
        MainActor.assumeIsolated {
            ModifierDragManager.shared.reenableTaps()
        }
        return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }

    let point = event.location
    let flags = event.flags
    let consumed = MainActor.assumeIsolated {
        ModifierDragManager.shared.handle(type: type, point: point, flags: flags)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
