import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppMetadata: Identifiable, Sendable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, iconSize: NSSize? = nil) {
        self.bundleIdentifier = bundleIdentifier
        let resolvedIcon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            self.name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            resolvedIcon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            self.name = bundleIdentifier
            resolvedIcon = NSWorkspace.shared.icon(for: .application)
        }
        if let iconSize {
            resolvedIcon.size = iconSize
        }
        self.icon = resolvedIcon
    }
}
