import AppKit
import Foundation

enum SystemTiling {
    static var isEdgeDragTilingEnabled: Bool {
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        let sideTiling = defaults?.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true
        let topTiling = defaults?.object(forKey: "EnableTopTilingByEdgeDrag") as? Bool ?? true
        return sideTiling || topTiling
    }

    @MainActor
    static func openDesktopAndDockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
