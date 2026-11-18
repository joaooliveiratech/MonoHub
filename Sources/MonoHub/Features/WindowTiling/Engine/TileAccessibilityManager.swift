import AppKit
import ApplicationServices
import Foundation

@MainActor
@Observable
final class TileAccessibilityManager {
    static let shared = TileAccessibilityManager()

    private static let pollInterval = Duration.seconds(2)

    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private var trustObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var hasPrompted = false

    private init() {}

    func startObserving() {
        guard trustObserver == nil else { return }
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                TileAccessibilityManager.shared.refresh()
            }
        }
        refresh()
    }

    func stopObserving() {
        if let trustObserver {
            DistributedNotificationCenter.default().removeObserver(trustObserver)
        }
        trustObserver = nil
    }

    @discardableResult
    func refresh() -> Bool {
        PermissionsManager.shared.refreshAccessibilityAndScreenRecording()
        let trusted = PermissionsManager.shared.hasAccessibility
        if trusted != isTrusted {
            isTrusted = trusted
        }
        return trusted
    }

    func monitorUntilTrusted() async {
        refresh()
        while !isTrusted, !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval, tolerance: .milliseconds(500))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    func promptIfNeeded() {
        guard !isTrusted, !hasPrompted else { return }
        hasPrompted = true
        _ = PermissionsManager.shared.requestAccessibility()
    }

    func openSystemSettings() {
        PermissionsManager.shared.openSettings(for: .accessibility)
    }
}
