import AppKit

enum SwitcherAppIconCache {
    private nonisolated static let pixelSize = 128
    private static var icons: [pid_t: CGImage] = [:]
    private static var observers: [any NSObjectProtocol] = []

    static func icon(for pid: pid_t) -> CGImage? {
        if let cached = icons[pid] { return cached }
        guard let icon = render(NSRunningApplication(processIdentifier: pid)?.icon) else { return nil }
        icons[pid] = icon
        return icon
    }

    static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                guard let pid = runningApplication(in: note)?.processIdentifier else { return }
                MainActor.assumeIsolated { prewarm(pids: [pid]) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
                guard let pid = runningApplication(in: note)?.processIdentifier else { return }
                MainActor.assumeIsolated { _ = icons.removeValue(forKey: pid) }
            }
        ]
        prewarm(pids: NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    }

    static func prewarm(pids: [pid_t]) {
        let missing = pids.filter { icons[$0] == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            let rendered = missing.compactMap { pid in
                render(NSRunningApplication(processIdentifier: pid)?.icon).map { (pid, $0) }
            }
            await MainActor.run {
                guard !observers.isEmpty else { return }
                for (pid, icon) in rendered where icons[pid] == nil {
                    icons[pid] = icon
                }
            }
        }
    }

    static func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        icons.removeAll()
    }

    private nonisolated static func runningApplication(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private nonisolated static func render(_ image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        var rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}
