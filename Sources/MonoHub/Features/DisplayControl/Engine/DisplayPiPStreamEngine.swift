import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import Observation
import QuartzCore
import ScreenCaptureKit

@Observable
@MainActor
final class DisplayPiPStreamEngine {
    static let shared = DisplayPiPStreamEngine()

    private(set) var activeStreams: [PiPStreamConfig] = []
    @ObservationIgnored private var streamSessions: [UUID: PiPStreamWindowSession] = [:]

    private init() {}

    func startPiPStream(_ config: PiPStreamConfig) {
        guard DisplayControlGate.isOpen else { return }
        if let idx = activeStreams.firstIndex(where: { $0.id == config.id }) {
            activeStreams[idx] = config
        } else {
            activeStreams.append(config)
        }

        guard !AppInfo.isRunningTests else { return }

        if let existing = streamSessions[config.id] {
            existing.updateConfig(config)
        } else {
            let session = PiPStreamWindowSession(config: config) { [weak self] closedID in
                Task { @MainActor [weak self] in
                    self?.stopPiPStream(id: closedID)
                }
            }
            streamSessions[config.id] = session
            session.start()
        }
    }

    func stopPiPStream(id: UUID) {
        activeStreams.removeAll { $0.id == id }
        if let session = streamSessions.removeValue(forKey: id) {
            session.stop()
        }
    }

    func stopAllStreams() {
        for id in Array(streamSessions.keys) {
            stopPiPStream(id: id)
        }
    }
}

@MainActor
private final class PiPStreamWindowSession: NSObject {
    private var config: PiPStreamConfig
    private let onClose: (UUID) -> Void
    private var panel: NSPanel?
    private let videoLayer = CALayer()
    private var scStream: SCStream?
    private var outputHandler: PiPStreamSampleOutput?

    init(config: PiPStreamConfig, onClose: @escaping (UUID) -> Void) {
        self.config = config
        self.onClose = onClose
        super.init()
    }

    func start() {
        setupPanel()
        Task {
            await startCaptureStream()
        }
    }

    func updateConfig(_ newConfig: PiPStreamConfig) {
        self.config = newConfig
        guard let panel else { return }
        panel.alphaValue = CGFloat(newConfig.opacity)
        panel.ignoresMouseEvents = newConfig.isClickThrough
        panel.level = newConfig.alwaysOnTop ? .floating : .normal
        panel.title = "\(newConfig.sourceName) • PiP"
        applyLayerTransforms()
    }

    func stop() {
        if let stream = scStream {
            Task {
                try? await stream.stopCapture()
            }
            scStream = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func setupPanel() {
        let rect = NSRect(x: 120, y: 120, width: config.width, height: config.height)
        let newPanel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = config.alwaysOnTop ? .floating : .normal
        newPanel.alphaValue = CGFloat(config.opacity)
        newPanel.ignoresMouseEvents = config.isClickThrough
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.title = "\(config.sourceName) • PiP"
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self

        let containerView = NSView(frame: rect)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        videoLayer.frame = containerView.bounds
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        containerView.layer?.addSublayer(videoLayer)

        newPanel.contentView = containerView
        self.panel = newPanel
        applyLayerTransforms()
        newPanel.orderFrontRegardless()
    }

    private func applyLayerTransforms() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let scaleX: CGFloat = (config.flipMode == .horizontal || config.flipMode == .both) ? -1.0 : 1.0
        let scaleY: CGFloat = (config.flipMode == .vertical || config.flipMode == .both) ? -1.0 : 1.0
        videoLayer.setAffineTransform(CGAffineTransform(scaleX: scaleX, y: scaleY))
        videoLayer.contentsRect = config.cropPreset.normalizedRect

        CATransaction.commit()
    }

    private func startCaptureStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == config.sourceDisplayID }) ?? content.displays.first else {
                return
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let streamCfg = SCStreamConfiguration()
            streamCfg.width = max(640, Int(config.width * 2))
            streamCfg.height = max(360, Int(config.height * 2))
            streamCfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(15, min(60, config.targetFPS))))
            streamCfg.showsCursor = true
            streamCfg.queueDepth = 3

            let handler = PiPStreamSampleOutput { [weak self] box in
                Task { @MainActor [weak self] in
                    self?.videoLayer.contents = box.surface
                }
            }
            self.outputHandler = handler

            let stream = SCStream(filter: filter, configuration: streamCfg, delegate: nil)
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.antigravity.monohub.pipstream", qos: .userInteractive))
            try await stream.startCapture()
            self.scStream = stream
        } catch {

        }
    }
}

extension PiPStreamWindowSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose(config.id)
    }
}

private nonisolated struct SendableIOSurfaceBox: @unchecked Sendable {
    let surface: IOSurfaceRef
}

private nonisolated final class PiPStreamSampleOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: @Sendable (SendableIOSurfaceBox) -> Void

    init(onFrame: @escaping @Sendable (SendableIOSurfaceBox) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(imageBuffer)?.takeUnretainedValue() else {
            return
        }
        onFrame(SendableIOSurfaceBox(surface: surface))
    }
}
