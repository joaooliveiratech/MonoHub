import AppKit
import Observation
import SwiftUI

enum ScreenshotStyle {
    static let symbol = "camera.viewfinder"
    static let tint = Color.orange
}

@MainActor
enum ScreenshotFeature: FeatureModule {
    private(set) static var isActive = false
    private static var isObservingPreferences = false

    static func activate() {
        guard !isActive else { return }
        isActive = true

        ScreenshotController.shared.start()
        applyPreferences()
        observePreferences()
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false

        ScreenshotShortcutRecordingSession.shared.cancel()
        ScreenshotController.shared.stop()
        ScreenshotStatusItemController.shared.setVisible(false)
    }

    private static func applyPreferences() {
        ScreenshotHotkeyService.shared.reload()
        ScreenshotStatusItemController.shared.setVisible(ScreenshotPreferences.shared.showMenuBarIcon)
    }

    private static func observePreferences() {
        guard !isObservingPreferences else { return }
        isObservingPreferences = true
        withObservationTracking {
            let prefs = ScreenshotPreferences.shared
            _ = prefs.shortcuts
            _ = prefs.showMenuBarIcon
        } onChange: {
            Task { @MainActor in
                isObservingPreferences = false
                guard isActive else { return }
                applyPreferences()
                observePreferences()
            }
        }
    }
}
