import Foundation
import os

enum ScreenshotLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.antigravity.monoshot"

    private static let general = Logger(subsystem: subsystem, category: "General")
    private static let capture = Logger(subsystem: subsystem, category: "Capture")
    private static let ocr = Logger(subsystem: subsystem, category: "OCR")

    static func info(_ event: StaticString) {
        general.info("\(event, privacy: .public)")
    }

    static func error(_ event: StaticString, _ error: any Error) {
        general.error("\(event, privacy: .public): \(String(describing: error), privacy: .private)")
    }

    static func captureError(_ event: StaticString, _ error: any Error) {
        capture.error("\(event, privacy: .public): \(String(describing: error), privacy: .private)")
    }

    static func captureError(_ event: StaticString, status: Int32) {
        capture.error("\(event, privacy: .public): \(status, privacy: .public)")
    }

    static func ocrError(_ event: StaticString, _ error: any Error) {
        ocr.error("\(event, privacy: .public): \(String(describing: error), privacy: .private)")
    }
}
