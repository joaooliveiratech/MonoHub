import Foundation
import SwiftUI
import AppKit

enum MediaConverterTab: String, CaseIterable, Identifiable, Sendable {
    case videos = "Vídeos"
    case images = "Imagens"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .videos: return "film.stack"
        case .images: return "photo.stack"
        }
    }

    var tintColor: Color {
        switch self {
        case .videos: return .indigo
        case .images: return .teal
        }
    }
}

enum OutputLocationMode: String, CaseIterable, Identifiable, Sendable {
    case sameFolder = "Mesma pasta de origem"
    case customFolder = "Pasta personalizada…"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameFolder: return localized("Same source folder")
        case .customFolder: return localized("Custom folder…")
        }
    }
}

@Observable
@MainActor
final class ConversionQueueManager {
    static let shared = ConversionQueueManager()

    var items: [MediaItem] = []
    var selectedTab: MediaConverterTab = .videos
    var isConverting: Bool = false
    var locationMode: OutputLocationMode = .sameFolder
    var customOutputFolder: URL? = nil

    var defaultVideoPreset: VideoPreset = .tablet720p {
        didSet { applyDefaultVideoPresetToPending() }
    }
    var defaultFastStart: Bool = true {
        didSet { applyDefaultFastStartToPending() }
    }

    var defaultImageFormat: ImageFormat = .heic {
        didSet { applyDefaultImageFormatToPending() }
    }
    var defaultImageQuality: Double = 0.82 {
        didSet { applyDefaultImageQualityToPending() }
    }
    var defaultStripEXIF: Bool = true {
        didSet { applyDefaultStripEXIFToPending() }
    }
    var defaultMaxDimensionPreset: MaxDimensionPreset = .original {
        didSet { applyDefaultMaxDimensionToPending() }
    }

    var selectedFilter: MediaConverterTab {
        get { selectedTab }
        set { selectedTab = newValue }
    }

    @ObservationIgnored
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init() {}

    var currentTabItems: [MediaItem] {
        items(for: selectedTab)
    }

    var filteredItems: [MediaItem] {
        currentTabItems
    }

    func items(for tab: MediaConverterTab) -> [MediaItem] {
        switch tab {
        case .videos:
            return items.filter { $0.kind == .video }
        case .images:
            return items.filter { $0.kind == .image }
        }
    }

    func pendingCount(for tab: MediaConverterTab) -> Int {
        items(for: tab).filter { $0.status == .pending }.count
    }

    func completedCount(for tab: MediaConverterTab) -> Int {
        items(for: tab).filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    func originalBytes(for tab: MediaConverterTab) -> Int64 {
        items(for: tab).reduce(0) { $0 + $1.fileSize }
    }

    func savedBytes(for tab: MediaConverterTab) -> Int64 {
        items(for: tab).reduce(0) { total, item in
            if case .completed(let res) = item.status {
                return total + res.savedBytes
            }
            return total
        }
    }

    func savingsPercentage(for tab: MediaConverterTab) -> Double {
        let tabCompleted = items(for: tab).compactMap { item -> ConversionResult? in
            if case .completed(let res) = item.status { return res }
            return nil
        }
        let original = tabCompleted.reduce(0) { $0 + $1.originalSize }
        let converted = tabCompleted.reduce(0) { $0 + $1.convertedSize }
        guard original > 0 else { return 0 }
        let diff = Double(original - converted)
        return (diff / Double(original)) * 100.0
    }

    var pendingCount: Int {
        items.filter { $0.status == .pending }.count
    }

    var completedCount: Int {
        items.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    func addFiles(urls: [URL], expectedKind: MediaKind? = nil) async {
        var filesToAdd: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    filesToAdd.append(contentsOf: scanDirectory(url, matching: expectedKind))
                } else if MediaInspector.isSupported(url: url) {
                    if let kind = MediaInspector.mediaKind(for: url) {
                        if expectedKind == nil || kind == expectedKind {
                            filesToAdd.append(url)
                        }
                    }
                }
            }
        }

        for fileURL in filesToAdd {

            if items.contains(where: { $0.fileURL == fileURL }) {
                continue
            }

            guard let inspected = await MediaInspector.inspect(url: fileURL) else {
                continue
            }

            let item = MediaItem(
                fileURL: fileURL,
                fileSize: inspected.fileSize,
                kind: inspected.kind,
                originalExtension: inspected.format,
                metadata: inspected.metadata,
                videoOptions: VideoConversionOptions(
                    preset: defaultVideoPreset,
                    fastStart: defaultFastStart
                ),
                imageOptions: ImageConversionOptions(
                    format: defaultImageFormat,
                    quality: defaultImageQuality,
                    stripEXIF: defaultStripEXIF,
                    maxDimension: defaultMaxDimensionPreset.pixelLimit
                )
            )
            items.append(item)
        }
    }

    private func scanDirectory(_ dir: URL, matching expectedKind: MediaKind?) -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if MediaInspector.isSupported(url: fileURL) {
                if let kind = MediaInspector.mediaKind(for: fileURL) {
                    if expectedKind == nil || kind == expectedKind {
                        result.append(fileURL)
                    }
                }
            }
        }
        return result
    }

    func remove(id: UUID) {
        cancelItem(id: id)
        items.removeAll { $0.id == id }
    }

    func retry(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].status = .pending
        }
    }

    func reconvertAll(for tab: MediaConverterTab) {
        let targetKind: MediaKind = (tab == .videos) ? .video : .image
        for idx in items.indices where items[idx].kind == targetKind {
            items[idx].status = .pending
        }
        startConversion(for: tab)
    }

    func clearCompleted(for tab: MediaConverterTab) {
        let toRemove = Set(items(for: tab).compactMap { item -> UUID? in
            if case .completed = item.status { return item.id }
            return nil
        })
        items.removeAll { toRemove.contains($0.id) }
    }

    func clearAll(for tab: MediaConverterTab) {
        let toRemove = Set(items(for: tab).map(\.id))
        for id in toRemove {
            cancelItem(id: id)
        }
        items.removeAll { toRemove.contains($0.id) }
    }

    func clearAll() {
        cancelAll()
        items.removeAll()
    }

    func cancelItem(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if case .converting = items[idx].status {
                items[idx].status = .cancelled
            }
        }
    }

    func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        for i in 0..<items.count {
            if case .converting = items[i].status {
                items[i].status = .cancelled
            }
        }
        isConverting = false
    }

    func startConversion(for tab: MediaConverterTab) {
        guard !isConverting else { return }
        isConverting = true

        Task {
            await processTabQueue(tab: tab)
            self.isConverting = false
            PreferencesManager.shared.playCompletionSound()
        }
    }

    func startConversion() {
        startConversion(for: selectedTab)
    }

    private func processTabQueue(tab: MediaConverterTab) async {
        let maxConcurrency = 2
        let targetKind: MediaKind = (tab == .videos) ? .video : .image

        var pendingIndices: [Int] = []
        for (idx, item) in items.enumerated() {
            if item.kind == targetKind && (item.status == .pending || item.status == .cancelled) {
                pendingIndices.append(idx)
            }
        }

        while !pendingIndices.isEmpty && isConverting {
            let batchCount = min(maxConcurrency, pendingIndices.count)
            let currentBatch = Array(pendingIndices.prefix(batchCount))
            pendingIndices.removeFirst(batchCount)

            if currentBatch.count == 1 {
                await convertItem(at: currentBatch[0])
            } else if currentBatch.count >= 2 {
                let first = currentBatch[0]
                let second = currentBatch[1]
                async let t1: Void = convertItem(at: first)
                async let t2: Void = convertItem(at: second)
                _ = await (t1, t2)
            }
        }
    }

    private func convertItem(at index: Int) async {
        guard index < items.count else { return }
        let item = items[index]
        let itemID = item.id

        let targetExtension: String
        switch item.kind {
        case .video:
            targetExtension = item.videoOptions.preset.targetExtension
        case .image:
            targetExtension = item.imageOptions.format.targetExtension
        }

        let destinationURL = resolveDestinationURL(for: item.fileURL, targetExtension: targetExtension)

        item.status = .converting(progress: 0.05)

        let task = Task {
            do {
                let result: ConversionResult
                switch item.kind {
                case .video:
                    result = try await VideoConverterEngine.convert(
                        sourceURL: item.fileURL,
                        destinationURL: destinationURL,
                        options: item.videoOptions
                    ) { progress in
                        Task { @MainActor in
                            item.status = .converting(progress: progress)
                        }
                    }
                case .image:
                    result = try await ImageConverterEngine.convert(
                        sourceURL: item.fileURL,
                        destinationURL: destinationURL,
                        options: item.imageOptions
                    ) { progress in
                        Task { @MainActor in
                            item.status = .converting(progress: progress)
                        }
                    }
                }

                await MainActor.run {
                    item.status = .completed(result)
                    self.activeTasks.removeValue(forKey: itemID)
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        item.status = .cancelled
                        self.activeTasks.removeValue(forKey: itemID)
                    }
                } else {
                    await MainActor.run {
                        item.status = .failed(error.localizedDescription)
                        self.activeTasks.removeValue(forKey: itemID)
                    }
                }
            }
        }

        activeTasks[itemID] = task
        await task.value
    }

    func resolveDestinationURL(for source: URL, targetExtension: String) -> URL {
        let parentDir: URL
        switch locationMode {
        case .sameFolder:
            parentDir = source.deletingLastPathComponent()
        case .customFolder:
            parentDir = customOutputFolder ?? source.deletingLastPathComponent()
        }

        let originalStem = source.deletingPathExtension().lastPathComponent
        let baseName = "\(originalStem)_converted"
        var candidate = parentDir.appendingPathComponent("\(baseName).\(targetExtension)")

        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentDir.appendingPathComponent("\(baseName)_\(counter).\(targetExtension)")
            counter += 1
        }

        return candidate
    }

    func chooseCustomOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = localized("Select Folder")
        panel.message = localized("Choose the location to save converted files")

        if panel.runModal() == .OK, let selected = panel.url {
            self.customOutputFolder = selected
            self.locationMode = .customFolder
        }
    }

    func openFilePicker(for tab: MediaConverterTab) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = localized("Add")

        switch tab {
        case .videos:
            panel.message = localized("Select videos to convert and compress")
        case .images:
            panel.message = localized("Select images to convert and optimize")
        }

        if panel.runModal() == .OK {
            let targetKind: MediaKind = (tab == .videos) ? .video : .image
            Task {
                await self.addFiles(urls: panel.urls, expectedKind: targetKind)
            }
        }
    }

    func openFolderPicker(for tab: MediaConverterTab) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = localized("Add Folder")

        switch tab {
        case .videos:
            panel.message = localized("Select folder containing videos")
        case .images:
            panel.message = localized("Select folder containing images")
        }

        if panel.runModal() == .OK {
            let targetKind: MediaKind = (tab == .videos) ? .video : .image
            Task {
                await self.addFiles(urls: panel.urls, expectedKind: targetKind)
            }
        }
    }

    private func applyDefaultVideoPresetToPending() {
        for item in items where item.kind == .video && item.status == .pending && !item.isCustomized {
            item.videoOptions.preset = defaultVideoPreset
        }
    }

    private func applyDefaultFastStartToPending() {
        for item in items where item.kind == .video && item.status == .pending && !item.isCustomized {
            item.videoOptions.fastStart = defaultFastStart
        }
    }

    private func applyDefaultImageFormatToPending() {
        for item in items where item.kind == .image && item.status == .pending && !item.isCustomized {
            item.imageOptions.format = defaultImageFormat
        }
    }

    private func applyDefaultImageQualityToPending() {
        for item in items where item.kind == .image && item.status == .pending && !item.isCustomized {
            item.imageOptions.quality = defaultImageQuality
        }
    }

    private func applyDefaultStripEXIFToPending() {
        for item in items where item.kind == .image && item.status == .pending && !item.isCustomized {
            item.imageOptions.stripEXIF = defaultStripEXIF
        }
    }

    private func applyDefaultMaxDimensionToPending() {
        let limit = defaultMaxDimensionPreset.pixelLimit
        for item in items where item.kind == .image && item.status == .pending && !item.isCustomized {
            item.imageOptions.maxDimension = limit
        }
    }
}
