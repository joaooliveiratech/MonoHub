import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private lazy var genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    private init() {
        cache.countLimit = 256
    }

    func icon(for bundlePath: String?) -> NSImage {
        guard let bundlePath else { return genericIcon }
        if let cached = cache.object(forKey: bundlePath as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        cache.setObject(icon, forKey: bundlePath as NSString)
        return icon
    }
}
