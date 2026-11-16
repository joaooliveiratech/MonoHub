import AppKit
import Observation

@Observable
@MainActor
final class AppExclusionManager {
    static let shared = AppExclusionManager()

    private(set) var isSuppressed: Bool = false {
        didSet {
            if oldValue != isSuppressed {
                onSuppressionChange?(isSuppressed)
            }
        }
    }
    private(set) var frontmostBundleID: String?
    private(set) var frontmostAppName: String?

    @ObservationIgnored var onSuppressionChange: ((Bool) -> Void)?
    @ObservationIgnored private var workspaceTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var preferencesTask: Task<Void, Never>?
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var evaluationGeneration = 0
    @ObservationIgnored private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AppExclusionManager.shared.evaluateSuppression()
                }
            }
            workspaceTokens.append(token)
        }

        preferencesTask = Task { [weak self] in
            let stream = Observations { @MainActor in
                let prefs = NotchPreferences.shared
                return ExclusionInputs(excluded: prefs.excludedAppBundleIDs, hideInFullScreen: prefs.hideInFullScreenApps)
            }
            for await _ in stream {
                guard let self, self.isRunning, !Task.isCancelled else { break }
                self.evaluateSuppression()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens {
            center.removeObserver(token)
        }
        workspaceTokens.removeAll()
        preferencesTask?.cancel()
        preferencesTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        evaluationGeneration += 1
        isSuppressed = false
        frontmostBundleID = nil
        frontmostAppName = nil
    }

    func evaluateSuppression() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            isSuppressed = false
            return
        }

        let bundleID = frontApp.bundleIdentifier
        if bundleID == AppInfo.bundleIdentifier {
            return
        }

        if frontmostBundleID != bundleID {
            frontmostBundleID = bundleID
        }
        let appName = frontApp.localizedName ?? bundleID ?? "Aplicativo"
        if frontmostAppName != appName {
            frontmostAppName = appName
        }

        let prefs = NotchPreferences.shared
        evaluationGeneration += 1
        evaluationTask?.cancel()
        evaluationTask = nil

        if let bundleID, prefs.isAppExcluded(bundleID: bundleID) {
            isSuppressed = true
            return
        }

        guard prefs.hideInFullScreenApps else {
            isSuppressed = false
            return
        }

        let generation = evaluationGeneration
        let pid = frontApp.processIdentifier
        let screenSizes = NSScreen.screens.map(\.frame.size)
        evaluationTask = Task { [weak self] in
            let fullScreen = await Self.isAppFullScreen(pid: pid, screenSizes: screenSizes)
            guard let self, !Task.isCancelled, generation == self.evaluationGeneration else { return }
            self.isSuppressed = fullScreen
        }
    }

    @concurrent
    nonisolated private static func isAppFullScreen(pid: pid_t, screenSizes: [CGSize]) async -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else {
                continue
            }
            if screenSizes.contains(where: { abs(width - $0.width) < 2 && abs(height - $0.height) < 2 }) {
                return true
            }
        }
        return false
    }
}

private nonisolated struct ExclusionInputs: Equatable, Sendable {
    let excluded: [String]
    let hideInFullScreen: Bool
}
