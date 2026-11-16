import AppKit
import Foundation
import Observation

@MainActor
enum SwitcherFeature: FeatureModule {
    private(set) static var isActive = false
    private static var isObservingPreferences = false
    private static var accessibilityObservers: [any NSObjectProtocol] = []

    static func activate() {
        guard !isActive else { return }
        isActive = true

        let prefs = SwitcherPreferencesManager.shared
        SwitcherPermissionsManager.shared.refresh(force: true)
        WindowActivationHistory.shared.startObserving()
        SwitcherAppIconCache.startObserving()
        SwitcherHotkeyManager.shared.delegate = SwitcherPanelController.shared
        SwitcherHotkeyManager.shared.setShortcutPreference(prefs.shortcut)
        SwitcherStatusItemController.shared.setVisible(prefs.showMenuBarIcon)
        SwitcherPanelController.shared.warmUp()
        startHotkeys()
        observePreferences()
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false

        stopWaitingForAccessibility()
        SwitcherHotkeyManager.shared.stop()
        SwitcherHotkeyManager.shared.delegate = nil
        SwitcherPanelController.shared.tearDown()
        SwitcherWindowManager.shared.clearCache()
        SwitcherAppIconCache.stopObserving()
        WindowActivationHistory.shared.stopObserving()
        SwitcherStatusItemController.shared.setVisible(false)
    }

    private static func startHotkeys() {
        guard isActive else { return }
        if SwitcherHotkeyManager.shared.start() {
            stopWaitingForAccessibility()
        } else {
            waitForAccessibility()
        }
    }

    private static func waitForAccessibility() {
        guard accessibilityObservers.isEmpty else { return }
        let retry: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                SwitcherPermissionsManager.shared.refresh(force: true)
                startHotkeys()
            }
        }
        accessibilityObservers = [
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main,
                using: retry
            ),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: retry
            )
        ]
    }

    private static func stopWaitingForAccessibility() {
        guard !accessibilityObservers.isEmpty else { return }
        DistributedNotificationCenter.default().removeObserver(accessibilityObservers[0])
        NotificationCenter.default.removeObserver(accessibilityObservers[1])
        accessibilityObservers.removeAll()
    }

    private static func observePreferences() {
        guard !isObservingPreferences else { return }
        isObservingPreferences = true
        withObservationTracking {
            let prefs = SwitcherPreferencesManager.shared
            _ = prefs.shortcut
            _ = prefs.showMenuBarIcon
        } onChange: {
            Task { @MainActor in
                isObservingPreferences = false
                guard isActive else { return }
                let prefs = SwitcherPreferencesManager.shared
                SwitcherHotkeyManager.shared.setShortcutPreference(prefs.shortcut)
                SwitcherStatusItemController.shared.setVisible(prefs.showMenuBarIcon)
                observePreferences()
            }
        }
    }
}
