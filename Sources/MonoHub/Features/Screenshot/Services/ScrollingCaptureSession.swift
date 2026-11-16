import AppKit
import SwiftUI
import CoreGraphics

@MainActor
protocol ScrollingCaptureSessionDelegate: AnyObject {
    func scrollingCaptureSession(_ session: ScrollingCaptureSession, didFinishWith image: CGImage, scaleFactor: CGFloat)
    func scrollingCaptureSessionDidCancel(_ session: ScrollingCaptureSession)
}

@MainActor
final class ScrollingCaptureSession: NSObject, ScrollingCaptureEngineDelegate {
    weak var delegate: (any ScrollingCaptureSessionDelegate)?

    let targetRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat

    private let engine: ScrollingCaptureEngine
    private var hudPanel: ScrollingCaptureHUDPanel?
    private var samplingTask: Task<Void, Never>?
    private var autoScrollTask: Task<Void, Never>?
    private var keyMonitor: Any?

    private var isAutoScrolling = false
    private var isFinished = false

    init(rect: CGRect, displayID: CGDirectDisplayID) {
        self.targetRect = rect
        self.displayID = displayID
        let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        self.scaleFactor = screen.backingScaleFactor
        self.engine = ScrollingCaptureEngine(targetRect: rect, displayID: displayID, scaleFactor: screen.backingScaleFactor)
        super.init()
        self.engine.delegate = self
    }

    func start() {
        showHUD()
        installKeyMonitor()

        Task { [weak self] in
            guard let self else { return }
            await self.captureFrame()
            self.startSamplingLoop()
        }
    }

    private func showHUD() {
        let hudSize = CGSize(width: 380, height: 48)

        var originX = targetRect.midX - hudSize.width / 2
        var originY = targetRect.maxY + 16

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(targetRect) }) {
            if originY + hudSize.height > screen.frame.maxY - 40 {
                originY = max(screen.frame.minY + 20, targetRect.minY - hudSize.height - 16)
            }
            originX = min(max(screen.frame.minX + 16, originX), screen.frame.maxX - hudSize.width - 16)
        }

        let panel = ScrollingCaptureHUDPanel(contentRect: CGRect(origin: CGPoint(x: originX, y: originY), size: hudSize))
        updateHUDContent(panel: panel)
        panel.orderFrontRegardless()
        self.hudPanel = panel
    }

    private func updateHUDContent(panel: ScrollingCaptureHUDPanel? = nil) {
        guard let panel = panel ?? self.hudPanel else { return }
        let view = ScrollingCaptureHUDView(
            height: engine.currentHeight,
            frames: engine.frameCount,
            isAutoScrolling: isAutoScrolling,
            onToggleAutoScroll: { [weak self] in
                self?.toggleAutoScroll()
            },
            onFinish: { [weak self] in
                self?.finish()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == ShotKeyCode.escape {
                self.cancel()
                return nil
            } else if event.keyCode == ShotKeyCode.returnKey || event.keyCode == ShotKeyCode.keypadEnter {
                self.finish()
                return nil
            }
            return event
        }
    }

    private func startSamplingLoop() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, !self.isFinished else { break }
                await self.captureFrame()
            }
        }
    }

    private func captureFrame() async {
        do {
            let image = try await ScreenCaptureService.shared.captureRect(
                targetRect,
                displayID: displayID,
                scaleFactor: scaleFactor,
                excludingSelf: true
            )
            engine.processFrame(image)
        } catch {
            ScreenshotLogger.captureError("scrolling frame capture failed", error)
        }
    }

    private func toggleAutoScroll() {
        isAutoScrolling.toggle()
        updateHUDContent()

        if isAutoScrolling {
            startAutoScroll()
        } else {
            stopAutoScroll()
        }
    }

    private func startAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled, let self, self.isAutoScrolling else { break }
                self.emitScrollEvent()
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func emitScrollEvent() {
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -12,
            wheel2: 0,
            wheel3: 0
        )
        scrollEvent?.post(tap: .cghidEventTap)
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()

        if let composite = engine.compositeImage {
            delegate?.scrollingCaptureSession(self, didFinishWith: composite, scaleFactor: scaleFactor)
        } else {
            delegate?.scrollingCaptureSessionDidCancel(self)
        }
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
        delegate?.scrollingCaptureSessionDidCancel(self)
    }

    private func cleanup() {
        samplingTask?.cancel()
        samplingTask = nil
        stopAutoScroll()

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        hudPanel?.orderOut(nil)
        hudPanel?.contentView = nil
        hudPanel = nil
    }

    func scrollingEngineDidUpdate(height: Int, frameCount: Int, previewImage: CGImage?) {
        updateHUDContent()
    }

    func scrollingEngineDidReachMaxHeight() {
        Toast.show(ShotText.maxHeightReached, symbol: "exclamationmark.triangle", anchor: .pointerScreen)
        finish()
    }
}
