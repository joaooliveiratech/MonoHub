import Foundation
import OSLog

actor FileWatcher {
    static let shared = FileWatcher()

    private var sources: [any DispatchSourceFileSystemObject] = []
    private var watchedPaths: Set<String> = []
    private var debounceTasks: [ProviderType: Task<Void, Never>] = [:]
    private var onFileChange: (@Sendable (ProviderType) -> Void)?

    private init() {}

    func start(onFileChange: @escaping @Sendable (ProviderType) -> Void) async {
        self.onFileChange = onFileChange
        stop()

        let enabled = await MainActor.run {
            Set(QuotaPreferencesManager.shared.enabledProviders)
        }
        guard !enabled.isEmpty else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeProjects = home.appending(path: ".claude/projects")
        let targets: [(ProviderType, URL)] = [
            (.claude, home.appending(path: ".claude")),
            (.claude, home.appending(path: ".claude/sessions")),
            (.claude, claudeProjects),
            (.codex, home.appending(path: ".codex")),
            (.codex, home.appending(path: ".codex/sessions")),
            (.antigravity, home.appending(path: ".gemini")),
            (.antigravity, home.appending(path: ".gemini/antigravity-cli/presence")),
            (.kimi, home.appending(path: ".kimi-code/credentials")),
            (.kimi, home.appending(path: ".kimi/credentials"))
        ]

        for (provider, folderURL) in targets where enabled.contains(provider) {
            watch(directory: folderURL, provider: provider, isProjectRoot: folderURL == claudeProjects)
        }

        if enabled.contains(.claude) {
            watchRecentClaudeProjectDirs(in: claudeProjects)
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        watchedPaths.removeAll()
        for (_, task) in debounceTasks {
            task.cancel()
        }
        debounceTasks.removeAll()
    }

    private func watchRecentClaudeProjectDirs(in projectsRoot: URL, maxDirectories: Int = 5) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sortedDirs = urls.compactMap { url -> (URL, Date)? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { return nil }
            return (url, values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxDirectories)

        for (dirURL, _) in sortedDirs {
            watch(directory: dirURL, provider: .claude)
        }
    }

    private func watch(directory: URL, provider: ProviderType, isProjectRoot: Bool = false) {
        let path = directory.path(percentEncoded: false)
        guard !watchedPaths.contains(path), FileManager.default.fileExists(atPath: path) else { return }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedPaths.insert(path)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { [weak self] in
                if isProjectRoot {
                    await self?.watchRecentClaudeProjectDirs(in: directory)
                }
                await self?.handleTrigger(for: provider)
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        sources.append(source)
    }

    private var lastTriggerTime: [ProviderType: Date] = [:]
    private let minimumReactiveInterval: TimeInterval = 60.0

    private func handleTrigger(for provider: ProviderType) {
        let now = Date()
        if let last = lastTriggerTime[provider], now.timeIntervalSince(last) < minimumReactiveInterval {
            return
        }

        debounceTasks[provider]?.cancel()
        debounceTasks[provider] = Task { [weak self] in

            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await self?.notifyFileChange(for: provider)
        }
    }

    private func notifyFileChange(for provider: ProviderType) {
        lastTriggerTime[provider] = Date()
        Log.quota.notice("file change detected for \(provider.id, privacy: .public); triggering reactive refresh")
        onFileChange?(provider)
    }
}
