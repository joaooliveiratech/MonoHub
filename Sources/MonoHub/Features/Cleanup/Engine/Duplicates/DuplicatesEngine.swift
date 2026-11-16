import CryptoKit
import Foundation
import Vision
import AppKit

nonisolated final class DuplicatesEngine: Sendable {
    static let shared = DuplicatesEngine()

    private init() {}

    private static let skippedDirectories: Set<String> = [
        ".git", ".hg", ".svn", "Library", ".Trash", "node_modules", ".build", "target",
        ".venv", "venv", "DerivedData", "Pods", ".gradle", ".cargo", ".rustup",
        ".nvm", ".pyenv", ".cache", ".npm", ".pnpm-store", ".next", ".nuxt", ".turbo"
    ]

    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "webp", "tiff", "bmp"
    ]

    func scanDuplicates(
        folders: [URL],
        minSizeBytes: Int64 = 102400,
        mode: DuplicatesScanMode = .exactHash,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async -> [DuplicateGroup] {
        await Task.detached(priority: .userInitiated) {
            progress?(0.05, localized("Discovering files…"))

            let files = Self.discoverFiles(in: folders, minSizeBytes: minSizeBytes, mode: mode)
            guard !files.isEmpty else { return [] }

            progress?(0.2, localized("Analyzing %d candidates…", files.count))

            switch mode {
            case .exactHash:
                return Self.findExactDuplicates(files: files, progress: progress)
            case .similarPhotos:
                return Self.findSimilarPhotos(files: files, progress: progress)
            }
        }.value
    }

    private struct FileIdentity: Hashable, Sendable {
        let device: dev_t
        let inode: ino_t
    }

    private struct CandidateFile: Sendable {
        let url: URL
        let size: Int64
        let modifiedDate: Date
        let identity: FileIdentity?
    }

    private static func discoverFiles(in roots: [URL], minSizeBytes: Int64, mode: DuplicatesScanMode) -> [CandidateFile] {
        let fm = FileManager.default
        let whitelist = WhitelistManager.shared
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        var candidates: [CandidateFile] = []
        var seenIdentities = Set<FileIdentity>()
        var visited = 0

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                visited += 1
                if visited & 1023 == 0 && Task.isCancelled {
                    return []
                }
                guard !whitelist.blocksRemoval(of: fileURL.path) else { continue }
                guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
                guard values.isSymbolicLink != true else { continue }

                if values.isDirectory == true {
                    if skippedDirectories.contains(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values.isRegularFile == true else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard ext != "icloud" else { continue }
                guard let size = values.fileSize.map(Int64.init), size >= minSizeBytes else { continue }

                var identity: FileIdentity?
                var st = stat()
                if lstat(fileURL.path, &st) == 0 {
                    let id = FileIdentity(device: st.st_dev, inode: st.st_ino)
                    guard seenIdentities.insert(id).inserted else { continue }
                    identity = id
                }

                if mode == .similarPhotos {
                    guard supportedImageExtensions.contains(ext) else { continue }
                }

                candidates.append(CandidateFile(
                    url: fileURL,
                    size: size,
                    modifiedDate: values.contentModificationDate ?? Date(),
                    identity: identity
                ))
            }
        }

        return candidates
    }

    private static func findExactDuplicates(
        files: [CandidateFile],
        progress: (@Sendable (Double, String) -> Void)?
    ) -> [DuplicateGroup] {

        var sizeGroups: [Int64: [CandidateFile]] = [:]
        for file in files {
            sizeGroups[file.size, default: []].append(file)
        }
        let potentialDuplicateSets = sizeGroups.values.filter { $0.count >= 2 }
        guard !potentialDuplicateSets.isEmpty else { return [] }

        progress?(0.4, localized("Checking quick signatures…"))

        var partialHashGroups: [String: [CandidateFile]] = [:]
        for group in potentialDuplicateSets {
            if Task.isCancelled { return [] }
            for file in group {
                if let partial = quickHash(for: file.url, size: file.size) {
                    let key = "\(file.size)-\(partial)"
                    partialHashGroups[key, default: []].append(file)
                }
            }
        }
        let partialMatches = partialHashGroups.values.filter { $0.count >= 2 }
        guard !partialMatches.isEmpty else { return [] }

        progress?(0.7, localized("Computing full SHA-256 signatures…"))

        var fullHashGroups: [String: [CandidateFile]] = [:]
        for group in partialMatches {
            if Task.isCancelled { return [] }
            for file in group {
                if Task.isCancelled { return [] }
                if let full = fullSHA256(for: file.url) {
                    fullHashGroups[full, default: []].append(file)
                }
            }
        }

        progress?(0.95, localized("Organizing results…"))

        var resultGroups: [DuplicateGroup] = []
        for (hash, groupFiles) in fullHashGroups where groupFiles.count >= 2 {
            let sorted = groupFiles.sorted { $0.modifiedDate < $1.modifiedDate }
            let items = sorted.enumerated().map { index, file in
                DuplicateItem(
                    url: file.url,
                    name: file.url.lastPathComponent,
                    path: file.url.deletingLastPathComponent().path,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    hash: hash,
                    isSelected: index > 0
                )
            }

            resultGroups.append(DuplicateGroup(
                id: hash,
                hash: hash,
                items: items,
                sizePerItem: groupFiles[0].size,
                isVisualSimilarity: false
            ))
        }

        return resultGroups.sorted { $0.recoverableSize > $1.recoverableSize }
    }

    private static func quickHash(for url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let head = handle.readData(ofLength: 32768)
        hasher.update(data: head)
        if size > 65536 {
            try? handle.seek(toOffset: UInt64(size - 32768))
            let tail = handle.readData(ofLength: 32768)
            hasher.update(data: tail)
        } else if size > 32768 {
            let rest = handle.readData(ofLength: 32768)
            hasher.update(data: rest)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fullSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            if Task.isCancelled { return false }
            let chunk = handle.readData(ofLength: 524288)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        if Task.isCancelled { return nil }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func findSimilarPhotos(
        files: [CandidateFile],
        progress: (@Sendable (Double, String) -> Void)?
    ) -> [DuplicateGroup] {
        let maxVisionPhotos = 400
        let targetFiles = Array(files.prefix(maxVisionPhotos))

        progress?(0.3, localized("Extracting visual feature prints…"))

        struct PhotoPrint {
            let file: CandidateFile
            let print: VNFeaturePrintObservation
        }

        var prints: [PhotoPrint] = []
        for (i, file) in targetFiles.enumerated() {
            if Task.isCancelled { return [] }
            if i % 10 == 0 {
                let frac = 0.3 + 0.5 * (Double(i) / Double(targetFiles.count))
                progress?(frac, localized("Processing photo %d of %d…", i + 1, targetFiles.count))
            }

            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(url: file.url, options: [:])
            do {
                try handler.perform([request])
                if let observation = request.results?.first as? VNFeaturePrintObservation {
                    prints.append(PhotoPrint(file: file, print: observation))
                }
            } catch {
                continue
            }
        }

        progress?(0.85, localized("Clustering visually similar photos…"))

        var matchedIDs = Set<URL>()
        var clusters: [[CandidateFile]] = []

        for i in 0..<prints.count {
            if Task.isCancelled { return [] }
            let p1 = prints[i]
            if matchedIDs.contains(p1.file.url) { continue }

            var cluster = [p1.file]
            for j in (i + 1)..<prints.count {
                let p2 = prints[j]
                if matchedIDs.contains(p2.file.url) { continue }

                var distance: Float = 0
                do {
                    try p1.print.computeDistance(&distance, to: p2.print)
                    if distance < 0.25 {
                        cluster.append(p2.file)
                        matchedIDs.insert(p2.file.url)
                    }
                } catch {
                    continue
                }
            }

            if cluster.count >= 2 {
                matchedIDs.insert(p1.file.url)
                clusters.append(cluster)
            }
        }

        var resultGroups: [DuplicateGroup] = []
        for cluster in clusters {
            let sorted = cluster.sorted { $0.modifiedDate < $1.modifiedDate }
            let hashId = UUID().uuidString
            let items = sorted.enumerated().map { index, file in
                DuplicateItem(
                    url: file.url,
                    name: file.url.lastPathComponent,
                    path: file.url.deletingLastPathComponent().path,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    hash: hashId,
                    isSelected: index > 0
                )
            }

            resultGroups.append(DuplicateGroup(
                id: hashId,
                hash: hashId,
                items: items,
                sizePerItem: cluster[0].size,
                isVisualSimilarity: true
            ))
        }

        return resultGroups.sorted { $0.recoverableSize > $1.recoverableSize }
    }

    func applySelectionStrategy(_ strategy: DuplicateSelectionStrategy, to groups: inout [DuplicateGroup]) {
        for i in 0..<groups.count {
            var items = groups[i].items
            guard items.count >= 2 else { continue }

            switch strategy {
            case .keepOldest:

                let oldest = items.min(by: { $0.modifiedDate < $1.modifiedDate })
                for j in 0..<items.count {
                    items[j].isSelected = items[j].id != oldest?.id
                }
            case .keepNewest:

                let newest = items.max(by: { $0.modifiedDate < $1.modifiedDate })
                for j in 0..<items.count {
                    items[j].isSelected = items[j].id != newest?.id
                }
            case .keepShortestPath:
                let shortest = items.min(by: { $0.path.count < $1.path.count })
                for j in 0..<items.count {
                    items[j].isSelected = items[j].id != shortest?.id
                }
            }
            groups[i].items = items
        }
    }

    static func sanitizeSelections(in groups: inout [DuplicateGroup]) {
        for i in 0..<groups.count {
            guard !groups[i].items.isEmpty else { continue }
            if groups[i].items.allSatisfy(\.isSelected) {
                groups[i].items[0].isSelected = false
            }
        }
    }

    static func safeItemsToRemove(from groups: [DuplicateGroup]) -> [DuplicateItem] {
        var copy = groups
        sanitizeSelections(in: &copy)
        return copy.flatMap { $0.items.filter(\.isSelected) }
    }

    func removeDuplicates(
        items: [DuplicateItem],
        groups: [DuplicateGroup] = [],
        options: CleanupOptions? = nil
    ) async -> RemovalReport {
        let resolvedOptions: CleanupOptions
        if let options {
            resolvedOptions = options
        } else {
            resolvedOptions = await MainActor.run { CleanupOptions.current }
        }
        let safeItems = groups.isEmpty ? items : Self.safeItemsToRemove(from: groups)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets = safeItems.map { item in
            RemovalTarget(
                url: item.url,
                displayName: item.name,
                size: item.size,
                allowedRoots: [home]
            )
        }
        return await CleanupExecutor.execute(
            targets,
            options: resolvedOptions,
            action: localized("Removed duplicate files")
        ) { report in
            localized("Removed %d items", report.removedURLs.count)
        }
    }
}
