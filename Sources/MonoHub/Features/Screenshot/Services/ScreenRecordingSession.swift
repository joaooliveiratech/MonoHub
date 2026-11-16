import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import Synchronization

@MainActor
protocol ScreenRecordingSessionDelegate: AnyObject {
    func screenRecordingSession(_ session: ScreenRecordingSession, didFinishWith url: URL, format: ScreenRecordingFormat)
    func screenRecordingSessionDidCancel(_ session: ScreenRecordingSession)
}

nonisolated final class VideoSampleWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var hasStarted = false
    private let queue = DispatchQueue(label: "com.antigravity.monohub.writerQueue", qos: .userInteractive)

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard self.input.isReadyForMoreMediaData else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !self.hasStarted {
                self.writer.startSession(atSourceTime: pts)
                self.hasStarted = true
            }
            self.input.append(sampleBuffer)
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.input.markAsFinished()
                self.writer.finishWriting {
                    continuation.resume()
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.input.markAsFinished()
            self.writer.cancelWriting()
        }
    }
}

final class ScreenRecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    weak var delegate: (any ScreenRecordingSessionDelegate)?

    let targetRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat

    private var stream: SCStream?
    private nonisolated(unsafe) var sampleWriter: VideoSampleWriter?
    private var tempMasterURL: URL?

    private var isRecording = false
    private var isProcessing = false
    private var currentFormat: ScreenRecordingFormat = .gif
    private var elapsedSeconds = 0

    private var hudPanel: ScreenRecordingHUDPanel?
    private var timerTask: Task<Void, Never>?
    private var keyMonitor: Any?

    init(rect: CGRect, displayID: CGDirectDisplayID, initialFormat: ScreenRecordingFormat = .gif) {
        self.targetRect = rect
        self.displayID = displayID
        let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        self.scaleFactor = screen.backingScaleFactor
        self.currentFormat = initialFormat
        super.init()
    }

    func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.setupRecording()
                self.showHUD()
                self.installKeyMonitor()
                self.startTimer()
            } catch {
                ScreenshotLogger.captureError("failed to start screen recording", error)
                Toast.show("Falha ao iniciar gravação", symbol: "exclamationmark.triangle", anchor: .pointerScreen)
                self.delegate?.screenRecordingSessionDidCancel(self)
            }
        }
    }

    private func setupRecording() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("monohub_rec_\(UUID().uuidString).mp4")
        self.tempMasterURL = tempURL

        var pixelWidth = Int((targetRect.width * scaleFactor).rounded())
        var pixelHeight = Int((targetRect.height * scaleFactor).rounded())
        if pixelWidth % 2 != 0 { pixelWidth += 1 }
        if pixelHeight % 2 != 0 { pixelHeight += 1 }

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(8_000_000, max(1_000_000, pixelWidth * pixelHeight * 4)),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw CaptureError.noDisplay
        }
        writer.add(input)
        writer.startWriting()

        let sampleWriterInstance = VideoSampleWriter(writer: writer, input: input)
        self.sampleWriter = sampleWriterInstance

        let content = try await ScreenCaptureService.shared.shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let config = SCStreamConfiguration()
        let displayHeight = CGFloat(display.height)
        let localTopLeftY = max(0, displayHeight - targetRect.maxY)
        config.sourceRect = CGRect(x: targetRect.minX, y: localTopLeftY, width: targetRect.width, height: targetRect.height)
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        let queue = DispatchQueue(label: "com.antigravity.monohub.screenrecording", qos: .userInteractive)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await newStream.startCapture()

        self.stream = newStream
        self.isRecording = true
    }

    private func showHUD() {
        let hudSize = CGSize(width: 440, height: 48)
        var originX = targetRect.midX - hudSize.width / 2
        var originY = targetRect.maxY + 16

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(targetRect) }) {
            if originY + hudSize.height > screen.frame.maxY - 40 {
                originY = max(screen.frame.minY + 20, targetRect.minY - hudSize.height - 16)
            }
            originX = min(max(screen.frame.minX + 16, originX), screen.frame.maxX - hudSize.width - 16)
        }

        let panel = ScreenRecordingHUDPanel(contentRect: CGRect(origin: CGPoint(x: originX, y: originY), size: hudSize))
        updateHUDContent(panel: panel)
        panel.orderFrontRegardless()
        self.hudPanel = panel
    }

    private func updateHUDContent(panel: ScreenRecordingHUDPanel? = nil) {
        guard let panel = panel ?? self.hudPanel else { return }
        let binding = Binding<ScreenRecordingFormat>(
            get: { self.currentFormat },
            set: { self.currentFormat = $0 }
        )
        let view = ScreenRecordingHUDView(
            elapsedSeconds: elapsedSeconds,
            dimensions: targetRect.size,
            selectedFormat: binding,
            isProcessing: isProcessing,
            onStop: { [weak self] in
                self?.stop()
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
                self.stop()
                return nil
            }
            return event
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRecording else { break }
                self.elapsedSeconds += 1
                self.updateHUDContent()
            }
        }
    }

    func stop() {
        guard isRecording, !isProcessing else { return }
        isRecording = false
        isProcessing = true
        timerTask?.cancel()
        timerTask = nil
        updateHUDContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.stream?.stopCapture()
                await self.sampleWriter?.finish()

                guard let masterURL = self.tempMasterURL, FileManager.default.fileExists(atPath: masterURL.path) else {
                    self.cancel()
                    return
                }

                let finalURL = try await self.exportRecording(from: masterURL, format: self.currentFormat)
                try? FileManager.default.removeItem(at: masterURL)

                await MainActor.run {
                    self.cleanupHUD()
                    self.delegate?.screenRecordingSession(self, didFinishWith: finalURL, format: self.currentFormat)
                }
            } catch {
                ScreenshotLogger.captureError("failed to finalize recording", error)
                await MainActor.run {
                    self.cleanupHUD()
                    self.delegate?.screenRecordingSessionDidCancel(self)
                }
            }
        }
    }

    private func exportRecording(from masterURL: URL, format: ScreenRecordingFormat) async throws -> URL {
        let saveDir = URL(fileURLWithPath: ScreenshotPreferences.shared.effectiveSaveDirectory)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = Localization.language == .english ? "yyyy-MM-dd 'at' HH.mm.ss" : "yyyy-MM-dd 'às' HH.mm.ss"
        let prefix = Localization.language == .english ? "Screen Recording" : "Gravação de Tela"
        let filename = "\(prefix) \(dateFormatter.string(from: Date())).\(format.fileExtension)"
        let destinationURL = saveDir.appendingPathComponent(filename)

        switch format {
        case .gif:
            _ = try await ImageConverterEngine.convertVideoToGIF(
                sourceURL: masterURL,
                destinationURL: destinationURL,
                fps: 12,
                quality: 0.85,
                maxDimension: 960
            )
        case .mp4:
            _ = try await VideoConverterEngine.convert(
                sourceURL: masterURL,
                destinationURL: destinationURL,
                options: VideoConversionOptions(preset: .webOptimized, fastStart: true)
            )
        case .webm:
            _ = try await VideoConverterEngine.convertToWebM(
                sourceURL: masterURL,
                destinationURL: destinationURL
            )
        }

        return destinationURL
    }

    func cancel() {
        isRecording = false
        timerTask?.cancel()
        timerTask = nil

        Task { [weak self] in
            guard let self else { return }
            try? await self.stream?.stopCapture()
            self.sampleWriter?.cancel()

            if let tempURL = self.tempMasterURL {
                try? FileManager.default.removeItem(at: tempURL)
            }

            await MainActor.run {
                self.cleanupHUD()
                self.delegate?.screenRecordingSessionDidCancel(self)
            }
        }
    }

    private func cleanupHUD() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        hudPanel?.orderOut(nil)
        hudPanel?.contentView = nil
        hudPanel = nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              formatDesc.mediaType == .video else { return }

        sampleWriter?.append(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            ScreenshotLogger.captureError("stream stopped with error", error)
            guard let self else { return }
            self.cancel()
        }
    }
}
