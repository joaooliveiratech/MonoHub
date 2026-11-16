import Foundation
import AppKit

@MainActor
final class FocusController {
    static let shared = FocusController()

    private(set) var isEngaged = false
    private var activationObserver: (any NSObjectProtocol)?

    private init() {}

    nonisolated static func parseBundleIDs(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func setActive(_ active: Bool) {
        let prefs = NotchPreferences.shared
        if active {
            guard prefs.focusModeEnabled, !isEngaged else { return }
            isEngaged = true
            runShortcut(prefs.focusEnterShortcut)
            if prefs.focusBlockDistractions { startBlocking(prefs.focusBlockedApps) }
        } else {
            guard isEngaged else { return }
            isEngaged = false
            stopBlocking()
            runShortcut(prefs.focusExitShortcut)
        }
    }

    private func startBlocking(_ raw: String) {
        let ids = Set(Self.parseBundleIDs(raw))
        guard !ids.isEmpty else { return }
        hideRunning(ids)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated {
                if let id, ids.contains(id) { app?.hide() }
            }
        }
    }

    private func stopBlocking() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func hideRunning(_ ids: Set<String>) {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) { app.hide() }
        }
    }

    private func runShortcut(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !AppInfo.isRunningTests else { return }
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", trimmed]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
