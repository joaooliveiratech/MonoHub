import Foundation
import Observation

@MainActor
enum TilingFeature: FeatureModule {
    private(set) static var isActive = false
    private static var isObservingPreferences = false

    static func activate() {
        guard !isActive else { return }
        isActive = true

        WindowManager.shared.startObserving()
        TileAccessibilityManager.shared.startObserving()
        HotkeyManager.shared.start()
        applyPreferences()
        observePreferences()
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false

        ShortcutRecordingSession.shared.cancel()
        HotkeyManager.shared.stop()
        SnapManager.shared.stop()
        ModifierDragManager.shared.stop()
        SnapPreviewPanel.release()
        TileStatusItemController.shared.setVisible(false)
        TileAccessibilityManager.shared.stopObserving()
        WindowManager.shared.stopObserving()
    }

    private static func applyPreferences() {
        HotkeyManager.shared.reload()
        SnapManager.shared.reload()
        ModifierDragManager.shared.reload()
        let controller = TileStatusItemController.shared
        controller.setVisible(TilePreferencesManager.shared.showMenuBarIcon)
        controller.rebuildMenu()
    }

    private static func observePreferences() {
        guard !isObservingPreferences else { return }
        isObservingPreferences = true
        withObservationTracking {
            let prefs = TilePreferencesManager.shared
            _ = prefs.customShortcuts
            _ = prefs.disabledShortcuts
            _ = prefs.isMouseTrackingNeeded
            _ = prefs.isModifierDragEnabled
            _ = prefs.showMenuBarIcon
            _ = TileAccessibilityManager.shared.isTrusted
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
