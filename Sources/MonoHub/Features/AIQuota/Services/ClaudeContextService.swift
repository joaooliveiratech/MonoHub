import Foundation
import OSLog

nonisolated struct ClaudeContextSession: Identifiable, Sendable, Equatable {
    var id: String { sessionId }
    let sessionId: String
    let projectName: String
    let modelName: String
    let activeInputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalContextTokens: Int
    let contextLimit: Int
    let contextPercent: Double
    let lastPrompt: String?
    let modifiedAt: Date

    var formattedTokens: String {
        let currentK = totalContextTokens >= 1_000_000
            ? String(format: "%.1fM", Double(totalContextTokens) / 1_000_000.0)
            : "\(totalContextTokens / 1_000)k"
        let limitK = contextLimit >= 1_000_000
            ? String(format: "%.0fM", Double(contextLimit) / 1_000_000.0)
            : "\(contextLimit / 1_000)k"
        return "\(currentK) / \(limitK)"
    }
}

public actor ClaudeContextService {
    static let shared = ClaudeContextService()

    private let fileManager = FileManager.default
    private let projectsURL: URL

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        projectsURL = home.appendingPathComponent(".claude/projects")
    }

    func fetchRecentSessions(limit: Int = 3) -> [ClaudeContextSession] {
        guard fileManager.fileExists(atPath: projectsURL.path) else { return [] }

        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidateFiles: [(url: URL, modified: Date, project: String)] = []

        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            let rawName = dir.lastPathComponent
            let projectName = Self.cleanProjectName(rawName)

            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                if let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    candidateFiles.append((url: file, modified: modDate, project: projectName))
                }
            }
        }

        candidateFiles.sort { $0.modified > $1.modified }

        var results: [ClaudeContextSession] = []
        for candidate in candidateFiles.prefix(limit * 2) {
            if let session = Self.parseSession(fileURL: candidate.url, modified: candidate.modified, projectName: candidate.project) {
                results.append(session)
                if results.count >= limit { break }
            }
        }

        return results
    }

    nonisolated static func cleanProjectName(
        _ raw: String,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    ) -> String {
        let encodedHome = homePath
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "-")
        var remainder = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if !encodedHome.isEmpty, remainder.hasPrefix(encodedHome) {
            remainder = String(remainder.dropFirst(encodedHome.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        } else if remainder.hasPrefix("Users-") {
            let parts = remainder.split(separator: "-", maxSplits: 2).map(String.init)
            if parts.count == 3 {
                remainder = parts[2]
            }
        }

        if let resolved = resolveDiskProjectName(slug: remainder, baseDir: URL(fileURLWithPath: homePath)) {
            return resolved
        }

        let containerPrefixes = ["dev-", "work-", "projects-", "repos-", "src-", "code-", "Documents-", "Desktop-"]
        var stripped = true
        while stripped {
            stripped = false
            for prefix in containerPrefixes where remainder.lowercased().hasPrefix(prefix.lowercased()) {
                let candidate = String(remainder.dropFirst(prefix.count))
                if !candidate.isEmpty {
                    remainder = candidate
                    stripped = true
                    break
                }
            }
        }

        return remainder.isEmpty ? raw : remainder
    }

    private nonisolated static func resolveDiskProjectName(slug: String, baseDir: URL) -> String? {
        guard !slug.isEmpty else { return nil }
        let fm = FileManager.default
        let parts = slug.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return nil }

        var currentURL = baseDir
        var index = 0
        while index < parts.count {

            let remainingSlug = parts[index...].joined(separator: "-")
            let directCandidate = currentURL.appendingPathComponent(remainingSlug)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: directCandidate.path, isDirectory: &isDir), isDir.boolValue {
                return remainingSlug
            }

            var matchedNext = false
            for end in index..<parts.count {
                let segment = parts[index...end].joined(separator: "-")
                let nextURL = currentURL.appendingPathComponent(segment)
                if fm.fileExists(atPath: nextURL.path, isDirectory: &isDir), isDir.boolValue {
                    currentURL = nextURL
                    index = end + 1
                    matchedNext = true
                    break
                }
            }
            if !matchedNext {
                return nil
            }
        }
        return currentURL.lastPathComponent
    }

    nonisolated static func parseSession(fileURL: URL, modified: Date, projectName: String) -> ClaudeContextSession? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        let sessionId = fileURL.deletingPathExtension().lastPathComponent

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return nil
        }
        guard fileSize > 0 else { return nil }

        let chunkSizes: [UInt64] = fileSize <= 256 * 1024
            ? [fileSize]
            : [256 * 1024, min(fileSize, 2 * 1024 * 1024)]

        var latestUsage: [String: Any]?
        var latestModel: String?
        var lastPrompt: String?

        for maxBytes in chunkSizes {
            let tailBytes = min(fileSize, maxBytes)
            let startOffset = fileSize - tailBytes
            do {
                try handle.seek(toOffset: startOffset)
            } catch {
                return nil
            }
            guard let tailData = try? handle.readToEnd() else { return nil }

            let text = String(decoding: tailData, as: UTF8.self)
            var lines = text.components(separatedBy: "\n")
            if startOffset > 0, !lines.isEmpty {
                lines.removeFirst()
            }

            for line in lines.reversed() where !line.isEmpty {
                let needsUsage = latestUsage == nil && line.contains("\"usage\":")
                let needsPrompt = lastPrompt == nil && (line.contains("\"lastPrompt\":") || line.contains("\"last-prompt\""))
                guard needsUsage || needsPrompt else { continue }

                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    continue
                }

                if lastPrompt == nil, let prompt = json["lastPrompt"] as? String, !prompt.isEmpty {
                    lastPrompt = prompt
                }

                if latestUsage == nil,
                   let msg = json["message"] as? [String: Any],
                   let usage = msg["usage"] as? [String: Any] {
                    latestUsage = usage
                    latestModel = msg["model"] as? String
                }

                if latestUsage != nil && lastPrompt != nil {
                    break
                }
            }

            if latestUsage != nil {
                break
            }
        }

        guard let usage = latestUsage else { return nil }

        let inputTokens = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
        let outputTokens = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
        let cacheCreation = (usage["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
        let totalActive = inputTokens + outputTokens + cacheCreation + cacheRead
        guard totalActive > 0 else { return nil }

        let model = latestModel ?? "claude-sonnet"
        let limit = contextLimit(forModel: model, totalTokens: totalActive)
        let percent = min(max((Double(totalActive) / Double(limit)) * 100.0, 0.0), 100.0)

        return ClaudeContextSession(
            sessionId: sessionId,
            projectName: projectName,
            modelName: friendlyModelName(model),
            activeInputTokens: inputTokens,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            totalContextTokens: totalActive,
            contextLimit: limit,
            contextPercent: percent,
            lastPrompt: lastPrompt,
            modifiedAt: modified
        )
    }

    nonisolated static func contextLimit(forModel model: String, totalTokens: Int) -> Int {
        if totalTokens > 200_000 { return 1_000_000 }
        let lower = model.lowercased()
        let oneMillionIndicators = [
            "1m",
            "opus-5", "sonnet-5",
            "opus-4-8", "sonnet-4-8",
            "opus-4-7", "sonnet-4-7",
            "opus-4-6", "sonnet-4-6"
        ]
        if oneMillionIndicators.contains(where: { lower.contains($0) }) {
            return 1_000_000
        }
        return 200_000
    }

    nonisolated static func friendlyModelName(_ raw: String) -> String {
        let lower = raw.lowercased()
        let family: String? = if lower.contains("opus") {
            "Opus"
        } else if lower.contains("sonnet") {
            "Sonnet"
        } else if lower.contains("haiku") {
            "Haiku"
        } else {
            nil
        }
        guard let family else { return raw }

        let rawParts = lower
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
        var numeric: [String] = []
        let ignored: Set<String> = ["opus", "sonnet", "haiku", "latest"]
        for partSub in rawParts {
            let token = String(partSub)
            if ignored.contains(token) || token.hasPrefix("202") { continue }
            if token.count <= 2, Int(token) != nil {
                numeric.append(token)
                if numeric.count == 2 { break }
            }
        }
        if numeric.count == 2 {
            return "\(family) \(numeric[0]).\(numeric[1])"
        } else if numeric.count == 1 {
            return "\(family) \(numeric[0])"
        }
        return family
    }
}
