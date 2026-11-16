import AppKit
import CoreGraphics
import ScreenCaptureKit

struct DisplayTarget: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat
    let frame: CGRect

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = number
        self.scaleFactor = screen.backingScaleFactor
        self.frame = screen.frame
    }
}

struct DisplayCapture: Sendable {
    let target: DisplayTarget
    let image: CGImage
}

enum CaptureError: Error {
    case noDisplay
}

final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private static let ignoredBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.wallpaper",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.SystemUIServer"
    ]

    private init() {}

    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    func visibleWindows(in content: SCShareableContent) -> [SCWindow] {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let filtered = content.windows.filter { window in
            guard window.isOnScreen else { return false }
            guard window.frame.width > 50 && window.frame.height > 50 else { return false }
            guard let app = window.owningApplication, app.processID != currentPID else { return false }
            if Self.ignoredBundles.contains(app.bundleIdentifier) { return false }

            guard window.windowLayer >= 0 && window.windowLayer <= 10 else { return false }
            if let title = window.title, (title == "Desktop" || title == "Wallpaper") { return false }
            return true
        }

        return sortedWindowsByZOrder(filtered)
    }

    private func sortedWindowsByZOrder(_ windows: [SCWindow]) -> [SCWindow] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }

        var zIndexMap: [CGWindowID: Int] = [:]
        for (index, info) in windowInfoList.enumerated() {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                zIndexMap[CGWindowID(number.uint32Value)] = index
            }
        }

        return windows.sorted { lhs, rhs in
            (zIndexMap[lhs.windowID] ?? Int.max) < (zIndexMap[rhs.windowID] ?? Int.max)
        }
    }

    private func screenshotConfiguration(width: CGFloat, height: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(2, Int(width.rounded()))
        config.height = max(2, Int(height.rounded()))
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    func captureDisplay(_ target: DisplayTarget, in content: SCShareableContent) async throws -> CGImage {
        guard let display = content.displays.first(where: { $0.displayID == target.displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = screenshotConfiguration(
            width: CGFloat(display.width) * target.scaleFactor,
            height: CGFloat(display.height) * target.scaleFactor
        )
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func captureRect(_ rect: CGRect, displayID: CGDirectDisplayID, scaleFactor: CGFloat, excludingSelf: Bool = true) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let excludedWindows: [SCWindow]
        if excludingSelf {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            excludedWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }
        } else {
            excludedWindows = []
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        let displayHeight = CGFloat(display.height)
        let localTopLeftY = max(0, displayHeight - rect.maxY)
        config.sourceRect = CGRect(x: rect.minX, y: localTopLeftY, width: rect.width, height: rect.height)
        config.width = max(2, Int((rect.width * scaleFactor).rounded()))
        config.height = max(2, Int((rect.height * scaleFactor).rounded()))
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func captureDisplays(_ targets: [DisplayTarget], in content: SCShareableContent) async -> [DisplayCapture] {
        let tasks = targets.map { target in
            Task { () -> DisplayCapture? in
                do {
                    let image = try await self.captureDisplay(target, in: content)
                    return DisplayCapture(target: target, image: image)
                } catch {
                    ScreenshotLogger.captureError("display capture failed", error)
                    return nil
                }
            }
        }

        var captures: [DisplayCapture] = []
        for task in tasks {
            if let capture = await task.value {
                captures.append(capture)
            }
        }
        return captures
    }

    func captureFullscreen(of screen: NSScreen) async throws -> DisplayCapture {
        guard let target = DisplayTarget(screen: screen) else { throw CaptureError.noDisplay }
        let content = try await shareableContent()
        let image = try await captureDisplay(target, in: content)
        return DisplayCapture(target: target, image: image)
    }

    func captureWindow(_ window: SCWindow) async throws -> (image: CGImage, scaleFactor: CGFloat) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(max(1, filter.pointPixelScale))
        let config = screenshotConfiguration(
            width: filter.contentRect.width * scale,
            height: filter.contentRect.height * scale
        )
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

    func crop(_ capture: DisplayCapture, to localRect: CGRect) -> CGImage? {
        let region = CaptureRegion(
            startPoint: localRect.origin,
            currentPoint: CGPoint(x: localRect.maxX, y: localRect.maxY),
            displayBounds: capture.target.frame,
            scaleFactor: capture.target.scaleFactor
        )
        let pixelRect = region.pixelCropRect(imagePixelSize: CGSize(width: capture.image.width, height: capture.image.height))
        return capture.image.cropping(to: pixelRect)
    }
}

extension NSScreen {
    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main ?? screens.first
    }
}
