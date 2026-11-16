import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class ShelfManager {
    static let shared = ShelfManager()

    private(set) var items: [ShelfItem] = []

    private init() {}

    func addURLs(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            if !items.contains(where: { $0.url == url }) {
                items.insert(ShelfItem(url: url), at: 0)
            }
        }
        enforceLimit()
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                let item = ShelfItem(url: url)
                Task { @MainActor in
                    ShelfManager.shared.insert(item)
                }
            }
            didHandle = true
        }
        return didHandle
    }

    private func insert(_ item: ShelfItem) {
        guard !items.contains(where: { $0.url == item.url }) else { return }
        items.insert(item, at: 0)
        enforceLimit()
    }

    private func enforceLimit() {
        let maxCount = max(3, NotchPreferences.shared.shelfMaxItems)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
    }

    func openItem(_ item: ShelfItem) {
        guard !AppInfo.isRunningTests else { return }
        switch NotchPreferences.shared.shelfClickAction {
        case .openFile:
            NSWorkspace.shared.open(item.url)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        case .copyPath:
            copyPath(item: item)
        }
    }

    func removeItem(id: UUID) {
        items.removeAll(where: { $0.id == id })
    }

    func clearAll() {
        items.removeAll()
    }

    func revealInFinder(item: ShelfItem) {
        guard !AppInfo.isRunningTests else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }
}
