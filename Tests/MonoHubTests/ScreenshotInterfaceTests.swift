import AppKit
import Testing
@testable import MonoHub

@Suite("Interface")
@MainActor
struct ScreenshotInterfaceTests {
    @Test("Every SF Symbol the interface references exists on this system")
    func symbolsResolve() {
        let names = ToolMode.allCases.map(\.iconName)
            + CaptureRequest.allCases.map(\.iconName)
            + ["camera.viewfinder", "slider.horizontal.3", "arrow.uturn.backward", "arrow.uturn.forward", "trash",
               "text.viewfinder", "pin", "square.and.arrow.down", "doc.on.clipboard", "text.magnifyingglass",
               "exclamationmark.triangle", "checkmark.circle", "checkmark.circle.fill", "macwindow", "rectangle.dashed",
               "lock.shield", "info.circle", "gearshape", "power", "xmark", "doc.on.doc", "folder",
               "wifi.slash", "cpu", "eye.slash", "location.slash"]

        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Missing symbols: \(missing)")
    }

    @Test("Glass pills size themselves to their content and expose it to VoiceOver")
    func glassPillSizing() {
        let pill = GlassPill()
        pill.configure(text: "Short")
        let short = pill.frame.width
        pill.configure(text: "A considerably longer piece of text", symbol: "macwindow")
        #expect(pill.frame.width > short)
        #expect(pill.frame.height > 0)
        #expect(pill.accessibilityLabel() == "A considerably longer piece of text")

        pill.place(centeredAt: CGPoint(x: -500, y: -500), within: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(pill.frame.minX >= 0 && pill.frame.minY >= 0)
    }

    private final class MockCaptureTarget: NSObject {
        @objc func captureArea() {}
        @objc func captureFullscreen() {}
        @objc func captureWindow() {}
        @objc func captureText() {}
    }

    @Test("Builds a capture menu whose shortcuts reach the editor actions")
    func captureMenuWiring() throws {
        _ = NSApplication.shared
        let target = MockCaptureTarget()
        let root = ScreenshotMenu.makeMenuItem(captureTarget: target, captureActions: [
            .area: #selector(MockCaptureTarget.captureArea),
            .fullscreen: #selector(MockCaptureTarget.captureFullscreen),
            .window: #selector(MockCaptureTarget.captureWindow),
            .textRecognition: #selector(MockCaptureTarget.captureText)
        ])
        let menu = try #require(root.submenu)
        let allItems = menu.items + menu.items.flatMap { $0.submenu?.items ?? [] }

        let save = try #require(allItems.first { $0.action == #selector(EditorWindowController.saveDocument(_:)) })
        #expect(save.keyEquivalent == "s")

        let zoomShortcuts = allItems.filter { $0.action == #selector(EditorWindowController.zoomIn(_:)) }.map(\.keyEquivalent)
        #expect(Set(zoomShortcuts) == ["+", "="])

        let tools = allItems.filter { $0.action == #selector(EditorWindowController.selectToolFromMenu(_:)) }
        #expect(tools.count == ToolMode.allCases.count)

        let unmodified = allItems.filter { !$0.keyEquivalent.isEmpty && $0.keyEquivalentModifierMask.isEmpty }
        #expect(unmodified.isEmpty, "Unmodified key equivalents steal keys from inline text: \(unmodified.map(\.title))")
    }

    @Test("Opens an editor window with a native toolbar and subtitle")
    func editorWindowSmokeTest() throws {
        _ = NSApplication.shared
        let ctx = CGContext(
            data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let controller = EditorWindowController(document: ScreenshotDocument(baseImage: ctx.makeImage()!, scaleFactor: 2.0))
        let window = try #require(controller.window)

        #expect(window.toolbar != nil)
        #expect(window.toolbarStyle == .unified)
        #expect(window.subtitle.hasPrefix("200 × 120 px"))
        #expect(window.isReleasedWhenClosed == false)

        controller.selectTool(.blur)
        controller.selectTool(.arrow)
        window.close()
    }

    @Test("Localizes every editor feedback message")
    func feedbackIsLocalized() {
        let original = Localization.language
        defer { Localization.language = original }

        let messages: () -> [String] = {
            [ShotText.ocrNoText, ShotText.ocrCopied, ShotText.ocrFailed, ShotText.textPlaceholder, ShotText.toastCopied,
             ShotText.toastSavedSuccess, ShotText.toastSaveFailed, ShotText.keySpace, ShotText.windowFallbackTitle]
        }
        Localization.language = .english
        let english = messages()
        Localization.language = .portuguese
        let portuguese = messages()

        for (en, pt) in zip(english, portuguese) where en != "Zoom" {
            #expect(en != pt, "\(en) is not translated")
        }
    }
}
