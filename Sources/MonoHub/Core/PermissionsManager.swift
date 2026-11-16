import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Observation

enum SystemPermissionKind: Sendable {
    case fullDiskAccess
    case accessibility
    case screenRecording
    case camera
    case calendars
    case reminders

    var settingsURL: String {
        switch self {
        case .fullDiskAccess: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .camera: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .calendars: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        }
    }
}

@Observable
@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()

    static var hasFullDiskAccess: Bool {
        shared.hasFullDiskAccess
    }

    private(set) var hasFullDiskAccess: Bool = false
    private(set) var hasAccessibility: Bool = false
    private(set) var hasScreenRecording: Bool = false

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    private init() {
        refreshStatus()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                PermissionsManager.shared.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        let fda = Self.checkSystemFullDiskAccess()
        if fda != hasFullDiskAccess {
            hasFullDiskAccess = fda
        }

        let ax = AXIsProcessTrusted()
        if ax != hasAccessibility {
            hasAccessibility = ax
        }

        let scr = CGPreflightScreenCaptureAccess()
        if scr != hasScreenRecording {
            hasScreenRecording = scr
        }
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        return hasAccessibility
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        hasScreenRecording = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        return hasScreenRecording
    }

    func openSettings(for kind: SystemPermissionKind) {
        if kind == .fullDiskAccess {
            openFullDiskAccessSettingsAndRevealApp()
            return
        }
        if kind == .accessibility {
            _ = requestAccessibility()
        } else if kind == .screenRecording {
            _ = requestScreenRecording()
        }
        if let url = URL(string: kind.settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated static var protectedProbePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Safari",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Suggestions",
            "\(home)/Library/PersonalizationPortrait"
        ]
    }

    nonisolated static func checkSystemFullDiskAccess() -> Bool {
        for path in protectedProbePaths {
            guard let directory = opendir(path) else { continue }
            defer { closedir(directory) }
            errno = 0
            if readdir(directory) != nil {
                return true
            }
        }
        return false
    }

    func triggerAccessProbe() {
        for path in Self.protectedProbePaths {
            let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NONBLOCK | O_CLOEXEC)
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
        }
    }

    var appBundleURL: URL {
        let installedURL = URL(fileURLWithPath: "/Applications/MonoHub.app")
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return installedURL
        }
        return Bundle.main.bundleURL
    }

    var appPath: String {
        appBundleURL.path
    }

    func copyAppPathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appPath, forType: .string)
    }

    static func openSettingsPane(_ identifier: String) {
        guard !AppInfo.isRunningTests else { return }
        guard let url = URL(string: "x-apple.systempreferences:\(identifier)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettingsAndRevealApp() {
        guard !AppInfo.isRunningTests else { return }
        triggerAccessProbe()

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }

        let bundleURL = appBundleURL
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        }
    }
}
