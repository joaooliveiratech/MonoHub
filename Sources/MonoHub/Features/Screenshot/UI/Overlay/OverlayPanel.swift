import AppKit
import CoreGraphics
import ScreenCaptureKit

protocol OverlayCoordinatorDelegate: AnyObject {
    func overlayDidCaptureSelection(image: CGImage, scaleFactor: CGFloat)
    func overlayDidRequestOCR(image: CGImage)
    func overlayDidRequestScrolling(rect: CGRect, displayID: CGDirectDisplayID)
    func overlayDidRequestRecording(rect: CGRect, displayID: CGDirectDisplayID)
}

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

final class OverlayCoordinator: NSObject, SelectionViewDelegate {
    static let shared = OverlayCoordinator()

    weak var delegate: (any OverlayCoordinatorDelegate)?

    private var activePanels: [OverlayPanel] = []
    private var capturedDisplays: [CGDirectDisplayID: DisplayCapture] = [:]
    private var escapeMonitor: Any?
    private var presentationID = 0
    private var intent: CaptureIntent = .screenshot
    private var previousApplication: NSRunningApplication?

    private override init() {
        super.init()
    }

    func present(mode: OverlayMode = .area, intent: CaptureIntent = .screenshot) async {
        dismiss()
        presentationID += 1
        let presentation = presentationID
        self.intent = intent

        let content: SCShareableContent
        do {
            content = try await ScreenCaptureService.shared.shareableContent()
        } catch {
            ScreenshotLogger.captureError("shareable content query failed", error)
            return
        }
        guard presentation == presentationID else { return }

        let visibleWindows = ScreenCaptureService.shared.visibleWindows(in: content)
        let targets = NSScreen.screens.compactMap(DisplayTarget.init(screen:))
        let captures = await ScreenCaptureService.shared.captureDisplays(targets, in: content)
        guard presentation == presentationID, !captures.isEmpty else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        NSApp.activate()
        installEscapeMonitor()

        let pointerScreenID = NSScreen.underPointer.flatMap(DisplayTarget.init(screen:))?.displayID
        var keyPanel: OverlayPanel?

        for capture in captures {
            capturedDisplays[capture.target.displayID] = capture

            let panel = OverlayPanel(contentRect: capture.target.frame)
            let selectionView = SelectionView(
                sourceImage: capture.image,
                scaleFactor: capture.target.scaleFactor,
                displayBounds: capture.target.frame,
                screenNumber: capture.target.displayID,
                initialMode: mode,
                intent: intent
            )
            selectionView.visibleWindows = visibleWindows
            selectionView.delegate = self
            panel.contentView = selectionView
            panel.setFrame(capture.target.frame, display: false)
            panel.orderFrontRegardless()
            activePanels.append(panel)

            if capture.target.displayID == pointerScreenID {
                keyPanel = panel
            }
        }

        if let panel = keyPanel ?? activePanels.first {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        }
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == ShotKeyCode.escape else { return event }
            self?.cancel()
            return nil
        }
    }

    func restoreFocus() {
        guard let previousApplication, !previousApplication.isTerminated else { return }
        self.previousApplication = nil
        previousApplication.activate()
    }

    private func cancel() {
        dismiss()
        restoreFocus()
    }

    func dismiss() {
        presentationID += 1
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        for panel in activePanels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        activePanels.removeAll()
        capturedDisplays.removeAll()
    }

    func selectionView(_ view: SelectionView, didChangeMode mode: OverlayMode) {
        for case let other as SelectionView in activePanels.map(\.contentView) where other !== view {
            other.mode = mode
        }
    }

    func selectionViewDidSelectWindow(_ window: SCWindow) {
        let intent = self.intent
        dismiss()

        if intent == .scrolling {
            let screenRect = window.frame
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) }) ?? NSScreen.main ?? NSScreen.screens.first
            let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            delegate?.overlayDidRequestScrolling(rect: screenRect, displayID: displayID)
            return
        }

        if intent == .screenRecord {
            let screenRect = window.frame
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) }) ?? NSScreen.main ?? NSScreen.screens.first
            let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            delegate?.overlayDidRequestRecording(rect: screenRect, displayID: displayID)
            return
        }

        Task {
            do {
                let capture = try await ScreenCaptureService.shared.captureWindow(window)
                if intent == .textRecognition {
                    delegate?.overlayDidRequestOCR(image: capture.image)
                } else {
                    delegate?.overlayDidCaptureSelection(image: capture.image, scaleFactor: capture.scaleFactor)
                }
            } catch {
                ScreenshotLogger.captureError("window capture failed", error)
            }
        }
    }

    func selectionViewDidComplete(rect: CGRect, screenNumber: CGDirectDisplayID, isOCR: Bool) {
        let capture = capturedDisplays[screenNumber]
        let intent = self.intent
        dismiss()

        guard let capture else { return }

        if intent == .scrolling {
            let screenRect = CGRect(
                x: capture.target.frame.minX + rect.minX,
                y: capture.target.frame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
            delegate?.overlayDidRequestScrolling(rect: screenRect, displayID: screenNumber)
            return
        }

        if intent == .screenRecord {
            let screenRect = CGRect(
                x: capture.target.frame.minX + rect.minX,
                y: capture.target.frame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
            delegate?.overlayDidRequestRecording(rect: screenRect, displayID: screenNumber)
            return
        }

        guard let cropped = ScreenCaptureService.shared.crop(capture, to: rect) else { return }

        if isOCR {
            delegate?.overlayDidRequestOCR(image: cropped)
        } else {
            delegate?.overlayDidCaptureSelection(image: cropped, scaleFactor: capture.target.scaleFactor)
        }
    }

    func selectionViewDidCancel() {
        cancel()
    }
}
