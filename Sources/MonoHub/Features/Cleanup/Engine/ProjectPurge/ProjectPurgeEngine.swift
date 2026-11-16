import Foundation

nonisolated enum ProjectPurgeEngine {
    static let artifactMarkers: [String: [String]] = [
        "node_modules": ["package.json"],
        ".build": ["Package.swift"],
        "target": ["Cargo.toml", "pom.xml", "build.sbt"],
        "dist": ["package.json", "pyproject.toml", "setup.py"],
        "build": [
            "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
            "package.json", "CMakeLists.txt", "pyproject.toml", "setup.py"
        ],
        ".venv": [],
        "venv": [],
        "Pods": ["Podfile"],
        ".gradle": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradlew"],
        ".next": ["package.json", "next.config.js", "next.config.mjs", "next.config.ts"],
        ".nuxt": ["package.json", "nuxt.config.ts", "nuxt.config.js"],
        ".turbo": ["turbo.json", "package.json"],
        ".astro": ["package.json", "astro.config.mjs", "astro.config.ts"],
        ".svelte-kit": ["package.json", "svelte.config.js", "svelte.config.ts"],
        ".pytest_cache": ["pyproject.toml", "setup.py", "setup.cfg", "pytest.ini", "tox.ini"],
        ".dart_tool": ["pubspec.yaml"]
    ]

    private static let skippedDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", "Library", "Applications", ".Trash",
        "node_modules", "Pods", "bower_components", "DerivedData"
    ]

    private static let gradleMarkers: Set<String> = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    private static let ignoreConfirmedNames: Set<String> = ["dist", "build"]

    static func isArtifact(named name: String, in projectDirectory: URL, fileManager: FileManager = .default) -> Bool {
        guard let markers = artifactMarkers[name] else { return false }
        if markers.isEmpty {
            return fileManager.fileExists(atPath: projectDirectory.appendingPathComponent(name).appendingPathComponent("pyvenv.cfg").path)
        }
        let present = markers.filter { fileManager.fileExists(atPath: projectDirectory.appendingPathComponent($0).path) }
        guard !present.isEmpty else { return false }
        guard ignoreConfirmedNames.contains(name) else { return true }
        if name == "build", present.contains(where: gradleMarkers.contains) { return true }
        return isIgnoredByGit(name, in: projectDirectory, fileManager: fileManager)
    }

    static func isIgnoredByGit(_ name: String, in projectDirectory: URL, fileManager: FileManager = .default) -> Bool {
        var directory = projectDirectory.standardizedFileURL
        var relativePrefix = ""
        while true {
            let ignoreFile = directory.appendingPathComponent(".gitignore")
            if let content = try? String(contentsOf: ignoreFile, encoding: .utf8),
               ignoreRules(in: content, matches: relativePrefix + name) {
                return true
            }
            let isRepositoryRoot = fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path)
            if isRepositoryRoot || directory.path == "/" { return false }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            relativePrefix = directory.lastPathComponent + "/" + relativePrefix
            directory = parent
        }
    }

    static func ignoreRules(in content: String, matches relativePath: String) -> Bool {
        let name = (relativePath as NSString).lastPathComponent
        var ignored = false
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let isNegation = line.hasPrefix("!")
            var pattern = isNegation ? String(line.dropFirst()) : line
            pattern = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
            if pattern.hasSuffix("/**") { pattern = String(pattern.dropLast(3)) }
            let anchored = pattern.hasPrefix("/")
            if anchored { pattern = String(pattern.dropFirst()) }
            if pattern.hasPrefix("**/") { pattern = String(pattern.dropFirst(3)) }
            let matches = pattern == name && !anchored || pattern == relativePath
            if matches { ignored = !isNegation }
        }
        return ignored
    }

    static func resolvedRoots(_ paths: [String]) -> [URL] {
        var seen = Set<String>()
        return paths.compactMap { raw in
            let expanded = NSString(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            guard !WhitelistManager.shared.isUserWhitelisted(path: url.path) else { return nil }
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }
    }

    struct Discovery: Sendable {
        let projectName: String
        let artifactType: String
        let url: URL
        let lastModified: Date
    }

    private static let traversalKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]

    static func discoverArtifacts(in root: URL, maxDepth: Int, olderThan cutoff: Date?, progress: ProgressReporter = .silent) -> [Discovery] {
        let fileManager = FileManager.default
        let whitelist = WhitelistManager.shared
        var results: [Discovery] = []
        var stack: [(URL, Int)] = [(root, 0)]
        var visited = 0

        while let (directory, depth) = stack.popLast() {
            if Task.isCancelled { return results }
            visited += 1
            progress.report(ScanProgress(message: localized("Scanning %@…", directory.lastPathComponent), completed: visited))

            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(traversalKeys),
                options: []
            ) else { continue }

            for item in contents {
                let name = item.lastPathComponent
                guard let values = try? item.resourceValues(forKeys: traversalKeys),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else { continue }

                if artifactMarkers[name] != nil, isArtifact(named: name, in: directory, fileManager: fileManager) {
                    guard !whitelist.blocksRemoval(of: item.path) else { continue }
                    let modified = values.contentModificationDate ?? Date()
                    if let cutoff, modified > cutoff { continue }
                    results.append(Discovery(
                        projectName: directory.lastPathComponent,
                        artifactType: name,
                        url: item.standardizedFileURL,
                        lastModified: modified
                    ))
                    continue
                }

                guard depth < maxDepth,
                      values.isPackage != true,
                      !name.hasPrefix("."),
                      !skippedDirectoryNames.contains(name) else { continue }
                stack.append((item, depth + 1))
            }
        }
        return results
    }

    @concurrent
    static func scanProjects(
        at paths: [String],
        maxDepth: Int = 4,
        minimumAgeDays: Int = 0,
        progress: ProgressReporter = .silent
    ) async -> [ProjectArtifact] {
        let depth = min(max(maxDepth, 1), 8)
        let cutoff = minimumAgeDays > 0 ? Date().addingTimeInterval(-Double(minimumAgeDays) * 86_400) : nil
        var discoveries: [Discovery] = []
        for root in resolvedRoots(paths) {
            if Task.isCancelled { return [] }
            discoveries += discoverArtifacts(in: root, maxDepth: depth, olderThan: cutoff, progress: progress)
        }

        let total = discoveries.count
        let sizes = await DirectorySize.allocatedSizes(of: discoveries.map(\.url)) { done in
            progress.report(ScanProgress(message: localized("Calculating sizes…"), completed: done, total: total))
        }
        if Task.isCancelled { return [] }

        return discoveries.map { discovery in
            ProjectArtifact(
                projectName: discovery.projectName,
                artifactType: discovery.artifactType,
                path: discovery.url,
                size: sizes[discovery.url] ?? 0,
                lastModified: discovery.lastModified
            )
        }
        .sorted { $0.size > $1.size }
    }

    static func purge(artifacts: [ProjectArtifact], scanPaths: [String], options: CleanupOptions) async -> RemovalReport {
        let roots = resolvedRoots(scanPaths)
        var rejected: [String] = []
        let targets = artifacts.compactMap { artifact -> RemovalTarget? in
            let url = artifact.path.standardizedFileURL
            guard isArtifact(named: url.lastPathComponent, in: url.deletingLastPathComponent()) else {
                rejected.append(localized("%@: no longer appears to be a build artifact; skipped.", artifact.itemName))
                return nil
            }
            return RemovalTarget(url: url, displayName: artifact.itemName, size: artifact.size, allowedRoots: roots)
        }
        var report = await CleanupExecutor.execute(
            targets,
            options: options,
            action: localized("Project Build Purge"),
            details: { report in localized("Removed %d build directories", report.removedURLs.count) }
        )
        report.errors.insert(contentsOf: rejected, at: 0)
        return report
    }
}
