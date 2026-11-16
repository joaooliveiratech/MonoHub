import AppKit
import ApplicationServices
import Foundation
import Observation

nonisolated enum SwitcherPermissionKind: Sendable {
    case accessibility
    case screenRecording
}

@MainActor
protocol SwitcherPermissionsManaging: AnyObject {
    var hasAccessibility: Bool { get }
    var hasScreenRecording: Bool { get }
    var bannerDismissed: Bool { get }
    var allGranted: Bool { get }
    var showsBanner: Bool { get }
    func refresh(force: Bool)
    func monitorUntilGranted() async
    func request(_ kind: SwitcherPermissionKind) -> Bool
    func openSettings(for kind: SwitcherPermissionKind)
    func dismissBanner()
}

@Observable
final class SwitcherPermissionsManager: SwitcherPermissionsManaging {
    static let shared = SwitcherPermissionsManager()

    private static let cacheLifetime = Duration.milliseconds(750)
    private static let pollInterval = Duration.seconds(2)

    private(set) var hasAccessibility = false
    private(set) var hasScreenRecording = false

    var bannerDismissed: Bool {
        didSet { UserDefaults.standard.set(bannerDismissed, forKey: "monotab_banner_dismissed") }
    }

    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?

    var allGranted: Bool {
        hasAccessibility && hasScreenRecording
    }

    var showsBanner: Bool {
        !allGranted && !bannerDismissed
    }

    private init() {
        bannerDismissed = UserDefaults.standard.bool(forKey: "monotab_banner_dismissed")
        refresh(force: true)
    }

    func dismissBanner() {
        bannerDismissed = true
    }

    func refresh(force: Bool = false) {
        let now = ContinuousClock.now
        if !force, let lastRefresh, now - lastRefresh < Self.cacheLifetime { return }
        lastRefresh = now

        PermissionsManager.shared.refreshStatus()
        let accessibility = PermissionsManager.shared.hasAccessibility
        let screenRecording = PermissionsManager.shared.hasScreenRecording
        if hasAccessibility != accessibility { hasAccessibility = accessibility }
        if hasScreenRecording != screenRecording { hasScreenRecording = screenRecording }
    }

    func monitorUntilGranted() async {
        refresh(force: true)
        while !allGranted, !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval, tolerance: .milliseconds(500))
            guard !Task.isCancelled else { return }
            refresh(force: true)
        }
    }

    @discardableResult
    func request(_ kind: SwitcherPermissionKind) -> Bool {
        lastRefresh = ContinuousClock.now
        switch kind {
        case .accessibility:
            hasAccessibility = PermissionsManager.shared.requestAccessibility()
            return hasAccessibility
        case .screenRecording:
            hasScreenRecording = PermissionsManager.shared.requestScreenRecording()
            return hasScreenRecording
        }
    }

    func openSettings(for kind: SwitcherPermissionKind) {
        let systemKind: SystemPermissionKind = kind == .accessibility ? .accessibility : .screenRecording
        PermissionsManager.shared.openSettings(for: systemKind)
        refresh(force: true)
    }
}
