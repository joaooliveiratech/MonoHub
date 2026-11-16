import Foundation

enum CaptureRequest: UInt32, CaseIterable, Sendable {
    case area = 1
    case fullscreen = 2
    case window = 3
    case textRecognition = 4
    case scrolling = 5
    case screenRecord = 6

    var defaultShortcut: KeyShortcut {
        switch self {
        case .area: return .defaultArea
        case .fullscreen: return .defaultFullscreen
        case .window: return .defaultWindow
        case .textRecognition: return .defaultOCR
        case .scrolling: return .defaultScrolling
        case .screenRecord: return .defaultRecord
        }
    }

    var legacyPreferencesKey: String {
        switch self {
        case .area: return "shortcutArea"
        case .fullscreen: return "shortcutFullscreen"
        case .window: return "shortcutWindow"
        case .textRecognition: return "shortcutOCR"
        case .scrolling: return "shortcutScrolling"
        case .screenRecord: return "shortcutRecord"
        }
    }

    var preferencesKey: String {
        "MonoHub_Screenshot_\(legacyPreferencesKey)"
    }

    var urlCommand: String {
        switch self {
        case .area: return "area"
        case .fullscreen: return "fullscreen"
        case .window: return "window"
        case .textRecognition: return "ocr"
        case .scrolling: return "scrolling"
        case .screenRecord: return "record"
        }
    }

    var iconName: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .fullscreen: return "display"
        case .window: return "macwindow"
        case .textRecognition: return "text.viewfinder"
        case .scrolling: return "arrow.up.and.down.square"
        case .screenRecord: return "record.circle"
        }
    }

    var menuTitle: String {
        switch self {
        case .area: return ShotText.menuCaptureArea
        case .fullscreen: return ShotText.menuCaptureFullscreen
        case .window: return ShotText.menuCaptureWindow
        case .textRecognition: return ShotText.menuOCR
        case .scrolling: return ShotText.menuCaptureScrolling
        case .screenRecord: return ShotText.menuRecordScreen
        }
    }

    var settingsTitle: String {
        switch self {
        case .area: return ShotText.shortcutAreaTitle
        case .fullscreen: return ShotText.shortcutFullscreenTitle
        case .window: return ShotText.shortcutWindowTitle
        case .textRecognition: return ShotText.shortcutOCRTitle
        case .scrolling: return ShotText.shortcutScrollingTitle
        case .screenRecord: return ShotText.shortcutRecordTitle
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .area: return ShotText.shortcutAreaSubtitle
        case .fullscreen: return ShotText.shortcutFullscreenSubtitle
        case .window: return ShotText.shortcutWindowSubtitle
        case .textRecognition: return ShotText.shortcutOCRSubtitle
        case .scrolling: return ShotText.shortcutScrollingSubtitle
        case .screenRecord: return ShotText.shortcutRecordSubtitle
        }
    }
}

protocol CaptureRequestHandler: AnyObject {
    func handleCaptureRequest(_ request: CaptureRequest)
}
