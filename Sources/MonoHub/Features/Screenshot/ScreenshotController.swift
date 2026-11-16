import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotController: NSObject, CaptureRequestHandler, OverlayCoordinatorDelegate, EditorWindowControllerDelegate, ScrollingCaptureSessionDelegate, ScreenRecordingSessionDelegate {
    static let shared = ScreenshotController()

    private var editorControllers: [EditorWindowController] = []
    private var activeScrollingSession: ScrollingCaptureSession?
    private var activeRecordingSession: ScreenRecordingSession?

    private override init() {
        super.init()
    }

    var hasOpenEditors: Bool {
        !editorControllers.isEmpty
    }

    func start() {
        ScreenshotHotkeyService.shared.delegate = self
        OverlayCoordinator.shared.delegate = self
        ScreenshotHotkeyService.shared.start()
    }

    func stop() {
        activeScrollingSession?.cancel()
        activeScrollingSession = nil
        activeRecordingSession?.cancel()
        activeRecordingSession = nil
        ScreenshotHotkeyService.shared.stop()
        ScreenshotHotkeyService.shared.delegate = nil
        OverlayCoordinator.shared.dismiss()
        OverlayCoordinator.shared.delegate = nil

        for controller in editorControllers {
            controller.editorDelegate = nil
            controller.close()
        }
        editorControllers.removeAll()
        PinCoordinator.shared.closeAll()
        Toast.dismissAndRelease()
        MainWindowController.shared.updateActivationPolicy()
    }

    func openImageFiles(_ urls: [URL]) {
        guard ScreenshotFeature.isActive else { return }
        for url in urls {
            Task {
                do {
                    let loaded = try await ImageFileLoader.load(url)
                    openEditor(for: ScreenshotDocument(baseImage: loaded.image, scaleFactor: loaded.scaleFactor))
                } catch {
                    ScreenshotLogger.error("image file could not be opened", error)
                    Toast.show(ShotText.openImageFailed, symbol: "exclamationmark.triangle", anchor: .pointerScreen)
                }
            }
        }
    }

    func presentOpenImagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        openImageFiles(panel.urls)
    }

    func handleCaptureRequest(_ request: CaptureRequest) {
        guard ScreenshotFeature.isActive else { return }
        let permissions = SwitcherPermissionsManager.shared
        permissions.refresh(force: true)
        guard permissions.hasScreenRecording else {
            permissions.request(.screenRecording)
            Toast.show(ShotText.permissionRequired, symbol: "lock.shield", anchor: .pointerScreen)
            return
        }

        switch request {
        case .area:
            presentOverlay(mode: .area, intent: .screenshot)
        case .window:
            presentOverlay(mode: .window, intent: .screenshot)
        case .textRecognition:
            presentOverlay(mode: .area, intent: .textRecognition)
        case .fullscreen:
            captureFullscreen()
        case .scrolling:
            presentOverlay(mode: .area, intent: .scrolling)
        case .screenRecord:
            presentOverlay(mode: .area, intent: .screenRecord)
        }
    }

    func startScrollingCapture(in rect: CGRect, displayID: CGDirectDisplayID) {
        activeScrollingSession?.cancel()
        let session = ScrollingCaptureSession(rect: rect, displayID: displayID)
        session.delegate = self
        activeScrollingSession = session
        session.start()
    }

    func startScreenRecording(in rect: CGRect, displayID: CGDirectDisplayID) {
        activeRecordingSession?.cancel()
        let session = ScreenRecordingSession(rect: rect, displayID: displayID)
        session.delegate = self
        activeRecordingSession = session
        session.start()
    }

    private func handleFinishedRecording(url: URL, format: ScreenRecordingFormat) {
        let preferences = ScreenshotPreferences.shared
        if preferences.playShutterSound {
            ShutterSound.play()
        }

        if preferences.copyToClipboardAfterCapture {
            PasteboardWriter.write(fileURL: url)
            if format == .gif, let data = try? Data(contentsOf: url) {
                PasteboardWriter.write(gifData: data)
            }
        }

        let toastMessage = ShotText.recordingSavedToast(format: format.displayName, name: url.lastPathComponent)
        Toast.show(toastMessage, symbol: "video.fill", anchor: .pointerScreen)
        OverlayCoordinator.shared.restoreFocus()
    }

    private func presentOverlay(mode: OverlayMode, intent: CaptureIntent) {
        Task {
            await OverlayCoordinator.shared.present(mode: mode, intent: intent)
        }
    }

    private func captureFullscreen() {
        guard let screen = NSScreen.underPointer else { return }
        Task {
            do {
                let capture = try await ScreenCaptureService.shared.captureFullscreen(of: screen)
                handleCapturedScreenshot(image: capture.image, scaleFactor: capture.target.scaleFactor)
            } catch {
                ScreenshotLogger.captureError("fullscreen capture failed", error)
            }
        }
    }

    private func handleCapturedScreenshot(image: CGImage, scaleFactor: CGFloat) {
        let preferences = ScreenshotPreferences.shared
        let document = ScreenshotDocument(baseImage: image, scaleFactor: scaleFactor)

        if preferences.playShutterSound {
            ShutterSound.play()
        }

        if preferences.copyToClipboardAfterCapture {
            let opensEditor = preferences.openEditorAfterCapture
            Task {
                if await document.copyToPasteboard(), !opensEditor {
                    Toast.show(ShotText.toastCopied, symbol: "doc.on.clipboard", anchor: .pointerScreen)
                }
            }
        }

        if preferences.openEditorAfterCapture {
            openEditor(for: document)
        } else {
            OverlayCoordinator.shared.restoreFocus()
        }
    }

    private func openEditor(for document: ScreenshotDocument) {
        let controller = EditorWindowController(document: document)
        controller.editorDelegate = self
        editorControllers.append(controller)
        MainWindowController.shared.updateActivationPolicy()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func editorWindowControllerDidClose(_ controller: EditorWindowController) {
        editorControllers.removeAll { $0 === controller }
        MainWindowController.shared.updateActivationPolicy()
    }

    func overlayDidCaptureSelection(image: CGImage, scaleFactor: CGFloat) {
        handleCapturedScreenshot(image: image, scaleFactor: scaleFactor)
    }

    func overlayDidRequestOCR(image: CGImage) {
        if ScreenshotPreferences.shared.playShutterSound {
            ShutterSound.play()
        }
        OverlayCoordinator.shared.restoreFocus()
        Task {
            await TextRecognitionFeedback.recognizeAndCopy(image, anchor: .pointerScreen)
        }
    }

    func overlayDidRequestScrolling(rect: CGRect, displayID: CGDirectDisplayID) {
        startScrollingCapture(in: rect, displayID: displayID)
    }

    func overlayDidRequestRecording(rect: CGRect, displayID: CGDirectDisplayID) {
        startScreenRecording(in: rect, displayID: displayID)
    }

    func scrollingCaptureSession(_ session: ScrollingCaptureSession, didFinishWith image: CGImage, scaleFactor: CGFloat) {
        activeScrollingSession = nil
        handleCapturedScreenshot(image: image, scaleFactor: scaleFactor)
    }

    func scrollingCaptureSessionDidCancel(_ session: ScrollingCaptureSession) {
        activeScrollingSession = nil
        OverlayCoordinator.shared.restoreFocus()
    }

    func screenRecordingSession(_ session: ScreenRecordingSession, didFinishWith url: URL, format: ScreenRecordingFormat) {
        activeRecordingSession = nil
        handleFinishedRecording(url: url, format: format)
    }

    func screenRecordingSessionDidCancel(_ session: ScreenRecordingSession) {
        activeRecordingSession = nil
        OverlayCoordinator.shared.restoreFocus()
    }
}
