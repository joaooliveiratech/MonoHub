import Darwin
import Foundation

nonisolated struct VolumeStats: Sendable {
    let totalBytes: Int64
    let freeBytes: Int64
    let availableBytes: Int64
    let usedBytes: Int64

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var formattedTotal: String { Formatting.bytes(totalBytes) }
    var formattedUsed: String { Formatting.bytes(usedBytes) }
    var formattedFree: String { Formatting.bytes(freeBytes) }
    var formattedPercentage: String { Formatting.percentage(usedPercentage) }
}

nonisolated final class DiskAnalyzerEngine: Sendable {
    static let shared = DiskAnalyzerEngine()

    static let defaultThresholdBytes: Int64 = 104_857_600

    private init() {}

    func getVolumeStats(for path: String = "/") -> VolumeStats {
        var stat = statfs()
        guard statfs(path, &stat) == 0 else {
            return VolumeStats(totalBytes: 0, freeBytes: 0, availableBytes: 0, usedBytes: 0)
        }

        let blockSize = Int64(stat.f_bsize)
        let total = Int64(stat.f_blocks) * blockSize
        let free = Int64(stat.f_bfree) * blockSize
        let available = Int64(stat.f_bavail) * blockSize

        return VolumeStats(
            totalBytes: total,
            freeBytes: free,
            availableBytes: available,
            usedBytes: max(0, total - free)
        )
    }

    static var scanDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Downloads", "Documents", "Desktop", "Movies", "Music"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
    ]

    @concurrent
    func scanLargeFiles(thresholdBytes: Int64 = DiskAnalyzerEngine.defaultThresholdBytes, progress: ProgressReporter = .silent) async -> [LargeFileItem] {
        let fileManager = FileManager.default
        let whitelist = WhitelistManager.shared
        var largeFiles: [LargeFileItem] = []
        var visited = 0

        for directory in Self.scanDirectories {
            guard fileManager.fileExists(atPath: directory.path),
                  !whitelist.isUserWhitelisted(path: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: Array(Self.resourceKeys),
                    options: [.skipsPackageDescendants, .skipsHiddenFiles],
                    errorHandler: { _, _ in true }
                  ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                visited += 1
                if visited & 511 == 0 {
                    if Task.isCancelled { return [] }
                    progress.report(ScanProgress(message: localized("Analyzing %@…", directory.lastPathComponent), completed: visited))
                }
                guard let values = try? fileURL.resourceValues(forKeys: Self.resourceKeys) else { continue }
                if values.isDirectory == true {
                    let name = fileURL.lastPathComponent
                    if name == "node_modules" || name == "Pods" || name == "DerivedData" || ProjectPurgeEngine.isArtifact(named: name, in: fileURL.deletingLastPathComponent()) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      fileURL.pathExtension.lowercased() != "icloud" else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= thresholdBytes, !whitelist.blocksRemoval(of: fileURL.path) else { continue }
                largeFiles.append(LargeFileItem(
                    name: fileURL.lastPathComponent,
                    url: fileURL.standardizedFileURL,
                    size: size,
                    fileType: LargeFileType.detect(for: fileURL),
                    lastModified: values.contentModificationDate ?? Date()
                ))
            }
        }

        return largeFiles.sorted { $0.size > $1.size }
    }

    func remove(files: [LargeFileItem], options: CleanupOptions) async -> RemovalReport {
        let roots = Self.scanDirectories
        let targets = files.map {
            RemovalTarget(url: $0.url, displayName: $0.name, size: $0.size, allowedRoots: roots)
        }
        return await CleanupExecutor.execute(
            targets,
            options: options,
            action: localized("Large File Deletion"),
            details: { report in localized("Removed %d large files", report.removedURLs.count) }
        )
    }
}
