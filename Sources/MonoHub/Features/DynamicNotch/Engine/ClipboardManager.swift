import Foundation
import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()

    private(set) var items: [ClipboardItem] = []
    var searchQuery: String = ""
    var selectedFilter: ClipboardFilter = .all

    @ObservationIgnored private var isRunning: Bool = false
    @ObservationIgnored private var monitorTimer: Timer?
    @ObservationIgnored private var sleepObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastChangeCount: Int = -1
    @ObservationIgnored private var isInternalWrite: Bool = false
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()

    @ObservationIgnored var workspaceOpener: (URL) -> Bool = { url in
        guard !AppInfo.isRunningTests else { return true }
        return NSWorkspace.shared.open(url)
    }
    @ObservationIgnored var fileViewerActivator: ([URL]) -> Void = { urls in
        guard !AppInfo.isRunningTests else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    @ObservationIgnored var colorPresenter: (NSColor) -> Void = { color in
        guard !AppInfo.isRunningTests else { return }
        NSColorPanel.shared.color = color
        NSColorPanel.shared.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resetOpenHandlers() {
        workspaceOpener = { url in
            guard !AppInfo.isRunningTests else { return true }
            return NSWorkspace.shared.open(url)
        }
        fileViewerActivator = { urls in
            guard !AppInfo.isRunningTests else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        colorPresenter = { color in
            guard !AppInfo.isRunningTests else { return }
            NSColorPanel.shared.color = color
            NSColorPanel.shared.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private init() {
        thumbnailCache.countLimit = 100
        prepareStorageDirectories()
    }

    var lastCopiedItem: ClipboardItem? {
        items.first
    }

    var filteredItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items.filter { item in
            switch selectedFilter {
            case .all:
                break
            case .text:
                guard item.type == .text else { return false }
            case .link:
                guard item.type == .link else { return false }
            case .color:
                guard item.type == .color else { return false }
            case .image:
                guard item.type == .image else { return false }
            case .pinned:
                guard item.isPinned else { return false }
            case .snippets:
                return false
            }

            if !query.isEmpty {
                let matchContent = item.content.localizedCaseInsensitiveContains(query)
                let matchPreview = item.previewText.localizedCaseInsensitiveContains(query)
                let matchApp = item.sourceAppName?.localizedCaseInsensitiveContains(query) ?? false
                let matchHex = item.colorInfo?.hex.localizedCaseInsensitiveContains(query) ?? false
                let matchRGB = item.colorInfo?.rgbString.localizedCaseInsensitiveContains(query) ?? false
                guard matchContent || matchPreview || matchApp || matchHex || matchRGB else {
                    return false
                }
            }

            return true
        }.sorted { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            return a.copiedAt > b.copiedAt
        }
    }

    func itemCount(for filter: ClipboardFilter) -> Int {
        switch filter {
        case .all:
            return items.count
        case .text:
            return items.filter { $0.type == .text }.count
        case .link:
            return items.filter { $0.type == .link }.count
        case .color:
            return items.filter { $0.type == .color }.count
        case .image:
            return items.filter { $0.type == .image }.count
        case .pinned:
            return items.filter { $0.isPinned }.count
        case .snippets:
            return SnippetManager.shared.snippets.filter { $0.isEnabled }.count
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        loadPinnedItems()
        lastChangeCount = NSPasteboard.general.changeCount

        monitorTimer?.invalidate()
        startTimer()
        registerSleepObservers()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        unregisterSleepObservers()
    }

    private func startTimer() {
        guard isRunning, monitorTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                ClipboardManager.shared.pollPasteboard()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func registerSleepObservers() {
        unregisterSleepObservers()
        let nc = NSWorkspace.shared.notificationCenter
        let sleepNames = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        for name in sleepNames {
            sleepObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitorTimer?.invalidate()
                    self?.monitorTimer = nil
                }
            })
        }
        let wakeNames = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in wakeNames {
            sleepObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.startTimer()
                }
            })
        }
    }

    private func unregisterSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for observer in sleepObservers {
            nc.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    func pollPasteboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if isInternalWrite {
            isInternalWrite = false
            return
        }

        guard let types = pb.types, !types.isEmpty else { return }

        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        let onePasswordType = NSPasteboard.PasteboardType("com.agilebits.onepassword")
        let transientType = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
        let findType = NSPasteboard.PasteboardType("com.apple.find.pasteboard")

        if types.contains(concealedType) ||
            types.contains(autoGeneratedType) ||
            types.contains(onePasswordType) ||
            types.contains(transientType) ||
            types.contains(findType) {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName
        let bundleID = frontApp?.bundleIdentifier

        if types.contains(.color), let color = NSColor(from: pb) {
            let info = ClipboardColor.from(nsColor: color)
            let item = ClipboardItem(
                type: .color,
                content: info.hex,
                previewText: "\(info.hex) • \(info.rgbString)",
                rawText: info.hex,
                colorInfo: info,
                sourceAppName: appName,
                sourceAppBundleID: bundleID
            )
            insertItem(item)
            return
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("public.jpeg")
        ]

        if types.contains(where: { imageTypes.contains($0) }),
           let image = NSImage(pasteboard: pb),
           image.isValid,
           image.size.width > 2 && image.size.height > 2 {
            if let item = processImage(image: image, pasteboard: pb, appName: appName, bundleID: bundleID) {
                insertItem(item)
                return
            }
        }

        if let text = pb.string(forType: .string), !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if let colorInfo = ClipboardColor.parse(from: trimmed) {
                let item = ClipboardItem(
                    type: .color,
                    content: colorInfo.hex,
                    previewText: "\(colorInfo.hex) • \(colorInfo.rgbString)",
                    rawText: text,
                    colorInfo: colorInfo,
                    sourceAppName: appName,
                    sourceAppBundleID: bundleID
                )
                insertItem(item)
                return
            }

            if let url = parseURL(trimmed) {
                let host = url.host ?? url.scheme ?? "link"
                let preview = url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
                let item = ClipboardItem(
                    type: .link,
                    content: trimmed,
                    previewText: preview,
                    rawText: text,
                    urlString: url.absoluteString,
                    sourceAppName: appName,
                    sourceAppBundleID: bundleID
                )
                insertItem(item)
                return
            }

            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let preview = lines.prefix(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let item = ClipboardItem(
                type: .text,
                content: text,
                previewText: preview.isEmpty ? text : preview,
                rawText: text,
                sourceAppName: appName,
                sourceAppBundleID: bundleID
            )
            insertItem(item)
        }
    }

    private func parseURL(_ string: String) -> URL? {
        guard !string.contains("\n") && !string.contains("\r") else { return nil }
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return nil }
        if (scheme == "http" || scheme == "https" || scheme == "ftp" || scheme == "file"),
           url.host != nil || scheme == "file" {
            return url
        }
        return nil
    }

    private func processImage(
        image: NSImage,
        pasteboard: NSPasteboard,
        appName: String?,
        bundleID: String?
    ) -> ClipboardItem? {
        var pngData: Data?

        if let data = pasteboard.data(forType: .png) {
            pngData = data
        } else if let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }

        guard let data = pngData else { return nil }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let fileURL = imageStorageURL.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let summary = "Imagem \(width)×\(height)"

        if let thumb = makeThumbnail(image: image, maxDimension: 120) {
            thumbnailCache.setObject(thumb, forKey: fileName as NSString)
        }

        return ClipboardItem(
            id: id,
            type: .image,
            content: summary,
            previewText: summary,
            imageFileName: fileName,
            imageWidth: width,
            imageHeight: height,
            byteSize: data.count,
            sourceAppName: appName,
            sourceAppBundleID: bundleID
        )
    }

    func insertItem(_ newItem: ClipboardItem) {

        if let existingIdx = items.firstIndex(where: { areItemsEquivalent($0, newItem) }) {
            let old = items[existingIdx]
            var updated = newItem
            updated.isPinned = old.isPinned
            items.remove(at: existingIdx)
            items.insert(updated, at: 0)
        } else {
            items.insert(newItem, at: 0)
        }

        enforceCapacityLimit()
    }

    private func areItemsEquivalent(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
        if a.type != b.type { return false }
        switch a.type {
        case .text, .link:
            return a.content == b.content
        case .color:
            return a.colorInfo?.hex == b.colorInfo?.hex
        case .image:
            return a.byteSize == b.byteSize && a.imageWidth == b.imageWidth && a.imageHeight == b.imageHeight
        }
    }

    private func enforceCapacityLimit() {
        let limit = max(10, NotchPreferences.shared.clipboardHistoryLimit)
        while items.count > limit {
            if let lastUnpinnedIdx = items.lastIndex(where: { !$0.isPinned }) {
                let removed = items.remove(at: lastUnpinnedIdx)
                deleteImageFile(named: removed.imageFileName)
            } else {
                break
            }
        }
    }

    func copyToPasteboard(item: ClipboardItem) {
        isInternalWrite = true
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            pb.setString(item.rawText ?? item.content, forType: .string)
        case .link:
            let urlString = item.urlString ?? item.content
            if let url = URL(string: urlString) {
                pb.writeObjects([url as NSURL])
            }
            pb.setString(urlString, forType: .string)
        case .color:
            let hex = item.colorInfo?.hex ?? item.content
            pb.setString(hex, forType: .string)
            if let nsColor = item.colorInfo?.nsColor {
                pb.writeObjects([nsColor])
            }
        case .image:
            if let data = imageData(for: item) {
                pb.setData(data, forType: .png)
            } else if let img = fullImage(for: item) {
                pb.writeObjects([img])
            }
        }

        lastChangeCount = pb.changeCount
        NotchHaptics.tap()

        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var updated = items.remove(at: idx)
            updated.copiedAt = Date()
            items.insert(updated, at: 0)
        } else {
            var updated = item
            updated.copiedAt = Date()
            items.insert(updated, at: 0)
        }
    }

    func paste(item: ClipboardItem) {
        copyToPasteboard(item: item)

        guard NotchPreferences.shared.clipboardAutoPaste && AXIsProcessTrusted() else {
            return
        }

        NotchWindowController.shared.isExpanded = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            Self.simulatePaste()
        }
    }

    static func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09
        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else { return }
        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
    }

    func open(item: ClipboardItem) {
        NotchWindowController.shared.isExpanded = false

        switch item.type {
        case .image:
            if let fileName = item.imageFileName {
                let fileURL = imageStorageURL.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = workspaceOpener(fileURL)
                    NotchHaptics.tap()
                    return
                }
            }
            if let data = imageData(for: item) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MonoHub_Image_\(item.id.uuidString.prefix(8)).png")
                try? data.write(to: tempURL)
                _ = workspaceOpener(tempURL)
                NotchHaptics.tap()
            }

        case .link:
            if let url = item.url {
                _ = workspaceOpener(url)
                NotchHaptics.tap()
            } else if let url = URL(string: item.content) {
                _ = workspaceOpener(url)
                NotchHaptics.tap()
            }

        case .color:
            if let color = item.colorInfo?.nsColor {
                colorPresenter(color)
                NotchHaptics.tap()
            }

        case .text:
            let text = item.rawText ?? item.content
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            let expandedPath = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                let fileURL = URL(fileURLWithPath: expandedPath)
                fileViewerActivator([fileURL])
                NotchHaptics.tap()
                return
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MonoHub_Texto_\(item.id.uuidString.prefix(8)).txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
                _ = workspaceOpener(tempURL)
                NotchHaptics.tap()
            } catch {
                copyToPasteboard(item: item)
            }
        }
    }

    func togglePin(item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPinned.toggle()
        savePinnedItems()
        NotchHaptics.tap()
    }

    func delete(item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: idx)
        deleteImageFile(named: removed.imageFileName)
        if removed.isPinned {
            savePinnedItems()
        }
        NotchHaptics.tap()
    }

    func clearHistory() {
        let unpinned = items.filter { !$0.isPinned }
        for item in unpinned {
            deleteImageFile(named: item.imageFileName)
        }
        items.removeAll(where: { !$0.isPinned })
        NotchHaptics.tap()
    }

    func clearAll() {
        for item in items {
            deleteImageFile(named: item.imageFileName)
        }
        items.removeAll()
        savePinnedItems()
        NotchHaptics.tap()
    }

    private var imageStorageURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.antigravity.monohub/ClipboardImages")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var pinnedStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MonoHub")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clipboard_pinned.json")
    }

    private func prepareStorageDirectories() {
        _ = imageStorageURL
        _ = pinnedStorageURL
    }

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        if let cached = thumbnailCache.object(forKey: fileName as NSString) {
            return cached
        }

        let fileURL = imageStorageURL.appendingPathComponent(fileName)
        guard let full = NSImage(contentsOf: fileURL),
              let thumb = makeThumbnail(image: full, maxDimension: 120) else {
            return nil
        }

        thumbnailCache.setObject(thumb, forKey: fileName as NSString)
        return thumb
    }

    func fullImage(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let fileURL = imageStorageURL.appendingPathComponent(fileName)
        return NSImage(contentsOf: fileURL)
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.imageFileName else { return nil }
        let fileURL = imageStorageURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }

    private func makeThumbnail(image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let targetSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let target = NSImage(size: targetSize)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        target.unlockFocus()
        return target
    }

    private func deleteImageFile(named fileName: String?) {
        guard let fileName else { return }
        thumbnailCache.removeObject(forKey: fileName as NSString)
        let fileURL = imageStorageURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func savePinnedItems() {
        let pinned = items.filter { $0.isPinned }
        do {
            let data = try JSONEncoder().encode(pinned)
            try data.write(to: pinnedStorageURL, options: .atomic)
        } catch {
        }
    }

    private func loadPinnedItems() {
        guard FileManager.default.fileExists(atPath: pinnedStorageURL.path) else { return }
        do {
            let data = try Data(contentsOf: pinnedStorageURL)
            let loaded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            for item in loaded {
                if !items.contains(where: { $0.id == item.id }) {
                    items.append(item)
                }
            }
        } catch {
        }
    }
}
