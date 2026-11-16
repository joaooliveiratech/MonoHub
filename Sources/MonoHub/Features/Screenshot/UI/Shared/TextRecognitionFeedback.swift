import AppKit

enum TextRecognitionFeedback {
    static func recognizeAndCopy(_ image: CGImage, anchor: ToastAnchor?) async {
        let concealed = ScreenshotPreferences.shared.concealRecognizedText
        do {
            let text = try await OCRService.shared.recognizeAndCopy(from: image, concealed: concealed)
            if text.isEmpty {
                Toast.show(ShotText.ocrNoText, symbol: "text.magnifyingglass", anchor: anchor)
            } else {
                ScreenshotLogger.info("OCR finished, text copied to the pasteboard")
                Toast.show(ShotText.ocrCopied, symbol: "doc.on.clipboard", anchor: anchor)
            }
        } catch {
            ScreenshotLogger.ocrError("OCR failed", error)
            Toast.show(ShotText.ocrFailed, symbol: "exclamationmark.triangle", anchor: anchor)
        }
    }
}
