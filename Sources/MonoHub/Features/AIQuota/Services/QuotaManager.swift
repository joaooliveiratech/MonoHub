import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class QuotaManager {
    static let shared = QuotaManager()

    private(set) var statuses: [ProviderType: ProviderStatus]
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?

    @ObservationIgnored
    private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored
    private var wakeDebounce: Task<Void, Never>?
    @ObservationIgnored
    private var resetBoundaryTask: Task<Void, Never>?
    @ObservationIgnored
    private var interval: TimeInterval = 300.0
    @ObservationIgnored
    private var previousPeakByWindow: [String: Double] = [:]
    @ObservationIgnored
    private var lastFetchByProvider: [ProviderType: Date] = [:]
    @ObservationIgnored
    private var inFlightProviders: Set<ProviderType> = []
    @ObservationIgnored
    private var workspaceObservers: [any NSObjectProtocol] = []
    @ObservationIgnored
    private var distributedObservers: [any NSObjectProtocol] = []
    @ObservationIgnored
    private var isScreenAsleep = false
    @ObservationIgnored
    private var isSessionLocked = false
    @ObservationIgnored
    private var isRunning = false

    private static let staleAfter: TimeInterval = 20.0

    private init() {
        let initial: [ProviderType: ProviderStatus] = Dictionary(
            uniqueKeysWithValues: ProviderType.allCases.map { ($0, ProviderStatus.initial(for: $0)) }
        )
        let cached = QuotaSnapshotStore.loadSnapshotsSync()
        statuses = initial.merging(cached) { _, new in new }
        interval = 300.0
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        interval = QuotaPreferencesManager.shared.refreshInterval
        observeSleepAndWake()
        startRefreshLoop()
        startFileWatcher()
        scheduleNextResetBoundary()
        Task { await refreshAll(force: true) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshLoop?.cancel()
        refreshLoop = nil
        wakeDebounce?.cancel()
        wakeDebounce = nil
        resetBoundaryTask?.cancel()
        resetBoundaryTask = nil
        inFlightProviders.removeAll()
        isRefreshing = false
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributed.removeObserver(observer)
        }
        distributedObservers.removeAll()
        isScreenAsleep = false
        isSessionLocked = false
        Task { await FileWatcher.shared.stop() }
    }

    private func startFileWatcher() {
        Task { [weak self] in
            await FileWatcher.shared.start { [weak self] provider in
                Task { @MainActor [weak self] in
                    await self?.refresh(provider: provider)
                }
            }
        }
    }

    func status(for provider: ProviderType) -> ProviderStatus {
        statuses[provider] ?? .initial(for: provider)
    }

    func usageText(for provider: ProviderType) -> String {
        let status = status(for: provider)
        if let value = status.headlineValue { return value }
        return status.state.isError ? "!" : "--"
    }

    func refreshAllIfStale() async {
        guard isRunning else { return }
        let now = Date()
        let staleProviders = QuotaPreferencesManager.shared.enabledProviders.filter { provider in
            guard !inFlightProviders.contains(provider) else { return false }
            guard let last = lastFetchByProvider[provider] else { return true }
            return now.timeIntervalSince(last) >= Self.staleAfter
        }
        guard !staleProviders.isEmpty else { return }
        await refreshProviders(staleProviders, force: false)
    }

    func refreshAll(force: Bool = false) async {
        guard isRunning else { return }
        let now = Date()
        let active = QuotaPreferencesManager.shared.enabledProviders.filter { provider in
            !inFlightProviders.contains(provider) && (force || isDue(provider, now: now))
        }
        guard !active.isEmpty else { return }
        await refreshProviders(active, force: force)
    }

    func refresh(provider: ProviderType, force: Bool = false) async {
        guard isRunning,
              QuotaPreferencesManager.shared.isProviderEnabled(provider),
              !inFlightProviders.contains(provider),
              force || isDue(provider, now: Date()) else { return }
        await refreshProviders([provider], force: force)
    }

    private func refreshProviders(_ providers: [ProviderType], force: Bool) async {
        let now = Date()
        for provider in providers {
            inFlightProviders.insert(provider)
            lastFetchByProvider[provider] = now
        }
        isRefreshing = !inFlightProviders.isEmpty
        defer {
            for provider in providers {
                inFlightProviders.remove(provider)
            }
            isRefreshing = !inFlightProviders.isEmpty
        }

        let allowCLI = QuotaPreferencesManager.shared.antigravityCLIEnabled
        let fetched = await withTaskGroup(of: (ProviderType, ProviderStatus).self) { group in
            for provider in providers {
                group.addTask { (provider, await Self.fetch(provider, allowCLI: allowCLI, force: force)) }
            }
            var results: [(ProviderType, ProviderStatus)] = []
            results.reserveCapacity(providers.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        for (provider, status) in fetched {
            let resolved = retainingLastKnownGood(status, for: provider)
            statuses[provider] = resolved
            let windows = resolved.windows
                .map { "\($0.name)=\(Int($0.effectiveUsedPercent))%" }
                .joined(separator: ", ")
            Log.quota.info(
                "\(provider.id, privacy: .public): \(String(describing: resolved.state), privacy: .public) via \(resolved.authSource, privacy: .public) [\(windows, privacy: .public)]"
            )
            checkWindowResets(resolved: resolved)
        }
        lastRefreshed = Date()
        notifyIfNearLimit()
        AIQuotaStatusItemController.shared.updateImage()
        scheduleNextResetBoundary()
        persistSnapshots()
    }

    private func scheduleNextResetBoundary() {
        resetBoundaryTask?.cancel()
        resetBoundaryTask = nil
        guard isRunning else { return }

        let now = Date()
        var earliest: (provider: ProviderType, date: Date)?
        for provider in QuotaPreferencesManager.shared.enabledProviders {
            guard let status = statuses[provider] else { continue }
            for window in status.windows {
                guard let resetsAt = window.resetsAt, resetsAt > now else { continue }
                if earliest == nil || resetsAt < earliest!.date {
                    earliest = (provider, resetsAt)
                }
            }
        }

        guard let target = earliest else { return }
        let delay = max(1.0, target.date.timeIntervalSince(now) + 1.0)

        guard delay <= 6 * 3600 else { return }

        resetBoundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1.0))
            guard !Task.isCancelled, let self else { return }
            AIQuotaStatusItemController.shared.updateImage()
            await self.refresh(provider: target.provider, force: true)
        }
    }

    private func checkWindowResets(resolved: ProviderStatus) {
        guard FeatureManager.shared.isEnabled(.aiQuota),
              QuotaPreferencesManager.shared.isProviderEnabled(resolved.provider) else { return }
        for window in resolved.windows {
            let key = "\(resolved.provider.id)|\(window.name)"
            let current = window.effectiveUsedPercent
            if let previous = previousPeakByWindow[key], previous >= 65.0, current <= 15.0 {
                LiveActivityCenter.shared.quotaDidReset(provider: resolved.provider.displayName, window: window.name)
                if QuotaPreferencesManager.shared.notificationsEnabled {
                    Task {
                        await NotificationService.shared.notifyReset(status: resolved, window: window)
                    }
                }
            }
            previousPeakByWindow[key] = current
        }
    }

    func refreshIntervalChanged(to newInterval: TimeInterval) {
        interval = newInterval
        guard isRunning else { return }
        startRefreshLoop()
    }

    private func isDue(_ provider: ProviderType, now: Date) -> Bool {
        guard let last = lastFetchByProvider[provider] else { return true }
        return now.timeIntervalSince(last) >= Self.minimumSpacing(for: provider)
    }

    private static func minimumSpacing(for provider: ProviderType) -> TimeInterval {
        switch provider {
        case .claude, .antigravity, .codex: 12.0
        default: 25.0
        }
    }

    private static func fetch(_ provider: ProviderType, allowCLI: Bool, force: Bool = false) async -> ProviderStatus {
        switch provider {
        case .claude: await ClaudeUsageService.shared.fetchUsage(force: force)
        case .antigravity: await AntigravityUsageService.shared.fetchUsage(allowCLI: allowCLI)
        case .codex: await CodexUsageService.shared.fetchUsage()
        case .copilot: await CopilotUsageService.shared.fetchUsage()
        case .cursor: await CursorUsageService.shared.fetchUsage()
        case .openrouter: await OpenRouterUsageService.shared.fetchUsage()
        case .grok: await GrokUsageService.shared.fetchUsage()
        case .commandcode: await CommandCodeUsageService.shared.fetchUsage()
        case .anthropicApi: await AnthropicAdminUsageService.shared.fetchUsage()
        case .deepseek: await DeepSeekUsageService.shared.fetchUsage()
        case .kimi: await KimiUsageService.shared.fetchUsage()
        case .zai: await ZaiUsageService.shared.fetchUsage()
        default:
            await ExtendedUsageService.shared.fetchUsage(for: provider)
        }
    }

    private func notifyIfNearLimit() {
        guard FeatureManager.shared.isEnabled(.aiQuota),
              QuotaPreferencesManager.shared.notificationsEnabled else { return }
        let enabled = Set(QuotaPreferencesManager.shared.enabledProviders)
        let snapshot = statuses.values.filter { enabled.contains($0.provider) }
        let threshold = QuotaPreferencesManager.shared.warningThreshold
        Task { await NotificationService.shared.notifyIfNeeded(statuses: snapshot, threshold: threshold) }
    }

    private func persistSnapshots() {
        let current = statuses
        Task {
            await QuotaSnapshotStore.shared.save(statuses: current)
        }
    }

    private func retainingLastKnownGood(
        _ incoming: ProviderStatus,
        for provider: ProviderType
    ) -> ProviderStatus {
        guard !incoming.hasReading,
              let previous = statuses[provider],
              previous.hasReading else { return incoming }

        var cached = previous
        if case .warning(let reason) = incoming.state {
            cached.state = .warning(reason)
        } else if case .expired(let reason) = incoming.state {
            cached.state = .expired(reason)
        } else {
            cached.state = .warning("Cached")
        }
        cached.errorMessage = incoming.errorMessage
        cached.actionSuggestion = incoming.actionSuggestion
        return cached
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        let period = Duration.seconds(max(interval, 30.0))
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: period, tolerance: period / 10)
                guard !Task.isCancelled else { return }
                await self?.refreshAll()
            }
        }
    }

    private func suspendForSleepOrLock() {
        refreshLoop?.cancel()
        refreshLoop = nil
        wakeDebounce?.cancel()
        wakeDebounce = nil
        resetBoundaryTask?.cancel()
        resetBoundaryTask = nil
        Task { await FileWatcher.shared.stop() }
    }

    private func resumeIfAwakeAndUnlocked() {
        guard isRunning, !isScreenAsleep, !isSessionLocked else { return }
        handleWake()
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isScreenAsleep = true
                    self?.suspendForSleepOrLock()
                }
            })
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isScreenAsleep = false
                    self?.resumeIfAwakeAndUnlocked()
                }
            })
        }

        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionLocked = true
                self?.suspendForSleepOrLock()
            }
        })

        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionLocked = false
                self?.resumeIfAwakeAndUnlocked()
            }
        })

        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionLocked = true
                self?.suspendForSleepOrLock()
            }
        })

        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionLocked = false
                self?.resumeIfAwakeAndUnlocked()
            }
        })

        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let name = (app?.localizedName ?? "").lowercased()
                let bundle = (app?.bundleIdentifier ?? "").lowercased()
                if name.contains("antigravity") || bundle.contains("antigravity") {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(2.0))
                        guard let self, !self.isScreenAsleep, !self.isSessionLocked else { return }
                        await self.refresh(provider: .antigravity, force: true)
                    }
                }
            })
        }
    }

    private func handleWake() {
        guard isRunning else { return }
        wakeDebounce?.cancel()
        startRefreshLoop()
        startFileWatcher()
        scheduleNextResetBoundary()
        wakeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.refreshAll()
        }
    }
}
