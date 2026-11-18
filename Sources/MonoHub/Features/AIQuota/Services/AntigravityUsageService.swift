import Foundation
import OSLog

nonisolated struct AntigravityModelInfo: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let displayName: String
    let family: String
    let isNew: Bool
}

nonisolated private struct QuotaSummaryResponse: Decodable {
    struct Payload: Decodable {
        struct Group: Decodable {
            struct Bucket: Decodable {
                let bucketId: String?
                let displayName: String?
                let description: String?
                let window: String?
                let remainingFraction: Double?
                let resetTime: String?
            }

            let displayName: String?
            let description: String?
            let buckets: [Bucket]?
        }

        let groups: [Group]?
    }

    let response: Payload?
    let groups: [Payload.Group]?

    var effectiveGroups: [Payload.Group]? {
        response?.groups ?? groups
    }
}

nonisolated private struct UserStatusResponse: Decodable {
    struct Status: Decodable {
        struct Tier: Decodable {
            let name: String?
        }
        struct Plan: Decodable {
            struct Info: Decodable {
                let planName: String?
            }
            let planInfo: Info?
        }

        let userTier: Tier?
        let planStatus: Plan?
    }

    let userStatus: Status?
}

nonisolated private struct CLIUsageResponse: Decodable {
    struct Command: Decodable {
        struct Payload: Decodable {
            struct Group: Decodable {
                struct Bucket: Decodable {
                    let id: String?
                    let name: String?
                    let description: String?
                    let window: String?
                    let remaining_fraction: Double?
                    let reset_time: String?
                }

                let name: String?
                let description: String?
                let buckets: [Bucket]?
            }

            let groups: [Group]?
        }

        let name: String?
        let data: Payload?
    }

    let status: String?
    let command: Command?
}

actor AntigravityUsageService {
    static let shared = AntigravityUsageService()

    static let defaultModels: [AntigravityModelInfo] = [
        AntigravityModelInfo(id: "gemini-4-argon", displayName: "Gemini 4 Argon", family: "Argon", isNew: true),
        AntigravityModelInfo(id: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash", family: "Gemini", isNew: false),
        AntigravityModelInfo(id: "gemini-pro", displayName: "Gemini Pro", family: "Gemini", isNew: false),
        AntigravityModelInfo(id: "claude-opus-5-5", displayName: "Claude Opus 5.5", family: "Claude", isNew: false),
        AntigravityModelInfo(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5", family: "Claude", isNew: false),
        AntigravityModelInfo(id: "gpt-oss-120b", displayName: "GPT-OSS 120B", family: "Open-Source", isNew: false)
    ]

    private struct Endpoint: Sendable, Equatable {
        let pid: pid_t
        let port: Int
        let csrfToken: String

        var baseURL: String { "http://127.0.0.1:\(port)" }
    }

    private struct Bucket {
        let group: String
        let groupDescription: String?
        let identifier: String?
        let displayName: String?
        let bucketDescription: String?
        let window: String?
        let remainingFraction: Double
        let resetTime: String?
    }

    private static let quotaRPC = "exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let statusRPC = "exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let maximumProbes = 8
    private static let emptyBody = Data("{}".utf8)
    private static let cliMinimumSpacing: Duration = .seconds(90)
    private static let cliTimeout: Duration = .seconds(25)

    private let http = HTTPClient(timeout: 1.5, resourceTimeout: 2.5)
    private let decoder = JSONDecoder()

    private var lastEndpoint: Endpoint?
    private var knownPlan = "Google AI"
    private var lastCLIRun: ContinuousClock.Instant?
    private var lastCLIStatus: ProviderStatus?
    private var cliInFlight: Task<ProviderStatus?, Never>?

    init() {
        Self.removeLegacySessionFile()
    }

    func fetchUsage(allowCLI: Bool) async -> ProviderStatus {
        if let status = await fetchFromLanguageServer() {
            return status
        }
        if allowCLI, let status = await fetchFromCLI() {
            return status
        }
        return offlineStatus(cliAvailable: Self.cliExecutable() != nil, allowCLI: allowCLI)
    }

    private func fetchFromLanguageServer() async -> ProviderStatus? {
        if let lastEndpoint, ProcessInspector.isAlive(lastEndpoint.pid) {
            if let status = await probe(lastEndpoint) { return status }
        }
        lastEndpoint = nil

        for server in ProcessInspector.findLanguageServers() {
            guard let token = csrfToken(for: server) else { continue }
            for port in candidatePorts(for: server) {
                let endpoint = Endpoint(pid: server.pid, port: port, csrfToken: token)
                if let status = await probe(endpoint) {
                    lastEndpoint = endpoint
                    return status
                }
            }
        }
        return nil
    }

    private func csrfToken(for server: ProcessInspector.Match) -> String? {
        if let token = server.value(forFlag: "--csrf_token"), !token.isEmpty {
            return token
        }
        guard server.isCommandLineClient else { return nil }

        if let token = ProcessInfo.processInfo.environment["ANTIGRAVITY_CSRF_TOKEN"], !token.isEmpty {
            return token
        }
        for child in ProcessInspector.childPIDs(of: server.pid) {
            if let token = ProcessInspector.commandLine(of: child)?.environmentValue("ANTIGRAVITY_CSRF_TOKEN"),
               !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private func candidatePorts(for server: ProcessInspector.Match) -> [Int] {
        let bridgePort = (server.value(forFlag: "--client_port").flatMap { Int($0) })
            ?? (server.value(forFlag: "--host_bridge_url").flatMap { URL(string: $0)?.port })

        var ordered: [Int] = []
        var seen: Set<Int> = []

        func append(_ port: Int) {
            guard (1024...65535).contains(port), seen.insert(port).inserted else { return }
            ordered.append(port)
        }

        if let bridgePort {
            for offset in [17, 18, 1, 2, 3, 4] {
                append(bridgePort + offset)
            }
        }

        let listening = ProcessInspector.listeningTCPPorts(of: server.pid)
        let prioritized = bridgePort.map { bridge in
            listening.sorted { abs($0 - bridge) < abs($1 - bridge) }
        } ?? listening.sorted(by: >)

        for port in prioritized {
            append(port)
        }
        return Array(ordered.prefix(Self.maximumProbes))
    }

    private func probe(_ endpoint: Endpoint) async -> ProviderStatus? {
        guard let url = URL(string: "\(endpoint.baseURL)/\(Self.quotaRPC)") else { return nil }

        var request = URLRequest.postJSON(url, body: Self.emptyBody, timeout: 1.5)
        request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        guard let (data, response) = try? await http.send(request),
              response.statusCode == 200,
              let groups = (try? decoder.decode(QuotaSummaryResponse.self, from: data))?.effectiveGroups,
              !groups.isEmpty else { return nil }

        let buckets = groups.flatMap { group in
            (group.buckets ?? []).compactMap { bucket -> Bucket? in
                guard let remaining = bucket.remainingFraction else { return nil }
                return Bucket(
                    group: group.displayName ?? "Models",
                    groupDescription: group.description,
                    identifier: bucket.bucketId,
                    displayName: bucket.displayName,
                    bucketDescription: bucket.description,
                    window: bucket.window,
                    remainingFraction: remaining,
                    resetTime: bucket.resetTime
                )
            }
        }
        guard !buckets.isEmpty else { return nil }

        await refreshIdentity(from: endpoint)
        return status(from: buckets, source: "Local RPC (127.0.0.1:\(endpoint.port))")
    }

    private func refreshIdentity(from endpoint: Endpoint) async {
        guard let url = URL(string: "\(endpoint.baseURL)/\(Self.statusRPC)") else { return }

        var request = URLRequest.postJSON(url, body: Self.emptyBody, timeout: 1.5)
        request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        guard let (data, response) = try? await http.send(request),
              response.statusCode == 200,
              let status = (try? decoder.decode(UserStatusResponse.self, from: data))?.userStatus else { return }

        if let tier = status.userTier?.name, !tier.isEmpty {
            knownPlan = tier
        } else if let planName = status.planStatus?.planInfo?.planName, !planName.isEmpty {
            knownPlan = planName
        }
    }

    private func fetchFromCLI() async -> ProviderStatus? {
        if let cliInFlight {
            return await cliInFlight.value
        }
        if let lastCLIRun, let lastCLIStatus, ContinuousClock.now - lastCLIRun < Self.cliMinimumSpacing {
            return lastCLIStatus
        }
        guard let executable = Self.cliExecutable() else { return nil }

        let task = Task { await self.runCLI(executable) }
        cliInFlight = task
        let status = await task.value
        cliInFlight = nil
        lastCLIRun = .now
        lastCLIStatus = status
        return status
    }

    private func runCLI(_ executable: URL) async -> ProviderStatus? {
        guard let workspace = Self.probeWorkspace() else { return nil }

        let data: Data
        do {
            data = try await CommandRunner.run(
                executable: executable,
                arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s", "--log-file", "/dev/null"],
                workingDirectory: workspace,
                environment: Self.cliEnvironment(),
                timeout: Self.cliTimeout,
                maximumOutputBytes: HTTPClient.maximumPayloadBytes
            )
        } catch {
            Log.quota.notice("agy usage probe failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let decoded = try? decoder.decode(CLIUsageResponse.self, from: data),
              decoded.status == "SUCCESS",
              let groups = decoded.command?.data?.groups else { return nil }

        let buckets = groups.flatMap { group in
            (group.buckets ?? []).compactMap { bucket -> Bucket? in
                guard let remaining = bucket.remaining_fraction else { return nil }
                return Bucket(
                    group: group.name ?? "Models",
                    groupDescription: group.description,
                    identifier: bucket.id,
                    displayName: bucket.name,
                    bucketDescription: bucket.description,
                    window: bucket.window,
                    remainingFraction: remaining,
                    resetTime: bucket.reset_time
                )
            }
        }
        guard !buckets.isEmpty else { return nil }

        return status(from: buckets, source: "agy CLI")
    }

    static func cliExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/agy"),
            URL(filePath: "/opt/homebrew/bin/agy"),
            URL(filePath: "/usr/local/bin/agy"),
            home.appending(path: ".antigravity/bin/agy")
        ]
        return candidates.first(where: CommandRunner.isTrustedExecutable)
    }

    private static func cliEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "TERM": "dumb",
            "NO_COLOR": "1"
        ]
        if let temporary = inherited["TMPDIR"] {
            environment["TMPDIR"] = temporary
        }
        return environment
    }

    private static func probeWorkspace() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = support
            .appending(path: "MonoAiBar", directoryHint: .isDirectory)
            .appending(path: "agy-workspace", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return directory
        } catch {
            return nil
        }
    }

    private func status(from buckets: [Bucket], source: String) -> ProviderStatus {
        var sessions: [QuotaWindow] = []
        var weeklies: [QuotaWindow] = []

        for bucket in buckets {
            let isWeekly = bucket.window == "weekly" || bucket.identifier?.hasSuffix("weekly") == true
            let windowName = Self.windowName(group: bucket.group, fallback: bucket.displayName, isWeekly: isWeekly)
            let models = Self.modelsDescription(group: bucket.group, fallback: bucket.groupDescription ?? bucket.bucketDescription)
            let windowId = bucket.identifier ?? "\(bucket.group)-\(bucket.window ?? (isWeekly ? "weekly" : "session"))"

            let window = QuotaWindow(
                id: windowId,
                name: windowName,
                usedPercent: (1.0 - bucket.remainingFraction) * 100.0,
                resetsAt: ISO8601.date(from: bucket.resetTime),
                limitWindowSeconds: isWeekly ? 7 * 86_400 : 5 * 3600,
                includedModels: models
            )

            let isArgon = bucket.group.localizedCaseInsensitiveContains("argon") || (bucket.identifier?.localizedCaseInsensitiveContains("argon") == true)
            let isGemini = !isArgon && bucket.group.localizedCaseInsensitiveContains("gemini")

            if isWeekly {
                if isArgon {
                    weeklies.insert(window, at: 0)
                } else if isGemini {
                    weeklies.insert(window, at: weeklies.isEmpty ? 0 : min(1, weeklies.count))
                } else {
                    weeklies.append(window)
                }
            } else {
                if isGemini {
                    sessions.insert(window, at: 0)
                } else {
                    sessions.append(window)
                }
            }
        }

        var status = ProviderStatus(
            provider: .antigravity,
            state: .healthy,
            planName: knownPlan,
            authSource: source,
            windows: sessions + weeklies,
            accountDetail: nil,
            lastUpdated: Date()
        )
        status.state = ProviderStatus.nearLimitState(peak: status.peakUsagePercent)
        return status
    }

    private static func windowName(group: String, fallback: String?, isWeekly: Bool) -> String {
        let span = isWeekly ? "Weekly" : "Session"
        if group.localizedCaseInsensitiveContains("argon") {
            return "Gemini 4 Argon · \(span)"
        }
        if group.localizedCaseInsensitiveContains("gemini") {
            return "Gemini (Flash & Pro) · \(span)"
        }
        if group.localizedCaseInsensitiveContains("claude") || group.localizedCaseInsensitiveContains("gpt") {
            return "Claude & GPT (Opus, Sonnet) · \(span)"
        }
        return "\(fallback ?? group) · \(span)"
    }

    private static func modelsDescription(group: String, fallback: String?) -> String {
        if group.localizedCaseInsensitiveContains("argon") {
            return "Gemini 4 Argon (Medium, High, Low)"
        }
        if group.localizedCaseInsensitiveContains("gemini") {
            return "Gemini 3.8 Flash, Gemini Pro"
        }
        if group.localizedCaseInsensitiveContains("claude") || group.localizedCaseInsensitiveContains("gpt") {
            return "Claude Opus 5.5, Claude Sonnet 5.5, GPT-OSS 120B"
        }
        if let fallback, !fallback.isEmpty {
            if fallback.hasPrefix("Models within this group: ") {
                return fallback.replacingOccurrences(of: "Models within this group: ", with: "")
            }
            return fallback
        }
        return group
    }

    private var cachedModels: [AntigravityModelInfo] = defaultModels
    private var lastModelsFetch: ContinuousClock.Instant?

    func fetchAvailableModels() async -> [AntigravityModelInfo] {
        if let lastModelsFetch, ContinuousClock.now - lastModelsFetch < .seconds(300), !cachedModels.isEmpty {
            return cachedModels
        }
        guard let executable = Self.cliExecutable(), let workspace = Self.probeWorkspace() else {
            return cachedModels
        }
        await refreshAvailableModels(executable: executable, workspace: workspace)
        return cachedModels
    }

    private func refreshAvailableModelsIfNeeded(executable: URL, workspace: URL) async {
        if let lastModelsFetch, ContinuousClock.now - lastModelsFetch < .seconds(300) {
            return
        }
        await refreshAvailableModels(executable: executable, workspace: workspace)
    }

    private func refreshAvailableModels(executable: URL, workspace: URL) async {
        do {
            let data = try await CommandRunner.run(
                executable: executable,
                arguments: ["models"],
                workingDirectory: workspace,
                environment: Self.cliEnvironment(),
                timeout: .seconds(8),
                maximumOutputBytes: 64 * 1024
            )
            if let output = String(data: data, encoding: .utf8) {
                let parsed = Self.parseCLIModels(output: output)
                if !parsed.isEmpty {
                    cachedModels = parsed
                    lastModelsFetch = .now
                }
            }
        } catch {
            Log.quota.notice("agy models fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func parseCLIModels(output: String) -> [AntigravityModelInfo] {
        let lines = output.components(separatedBy: .newlines)
        var seenNames = Set<String>()
        var models: [AntigravityModelInfo] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("Fetching available models") else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let id = parts[0]
            let fullDisplayName = parts.dropFirst().joined(separator: " ")

            var baseName = fullDisplayName
            for suffix in [" (Medium)", " (High)", " (Low)", " (medium)", " (high)", " (low)"] {
                if baseName.hasSuffix(suffix) {
                    baseName = String(baseName.dropLast(suffix.count))
                }
            }

            guard seenNames.insert(baseName).inserted else { continue }

            let family: String
            let isNew: Bool
            if baseName.localizedCaseInsensitiveContains("argon") {
                family = "Argon"
                isNew = true
            } else if baseName.localizedCaseInsensitiveContains("gemini") {
                family = "Gemini"
                isNew = false
            } else if baseName.localizedCaseInsensitiveContains("claude") {
                family = "Claude"
                isNew = false
            } else {
                family = "Open-Source"
                isNew = false
            }

            models.append(AntigravityModelInfo(id: id, displayName: baseName, family: family, isNew: isNew))
        }

        if seenNames.contains("Gemini 3.8 Flash") && !seenNames.contains("Gemini Pro") {
            models.append(AntigravityModelInfo(id: "gemini-pro", displayName: "Gemini Pro", family: "Gemini", isNew: false))
        }

        return models.isEmpty ? defaultModels : models
    }

    private func offlineStatus(cliAvailable: Bool, allowCLI: Bool) -> ProviderStatus {
        let suggestion: String
        if !cliAvailable {
            suggestion = "Install the `agy` CLI so MonoHub can read quota while Antigravity is closed."
        } else if !allowCLI {
            suggestion = "Open Antigravity, or turn on “Read quota through agy” in Settings."
        } else {
            suggestion = "Run `agy` once in a terminal to sign in."
        }

        return ProviderStatus(
            provider: .antigravity,
            state: .idle,
            planName: knownPlan,
            authSource: "Offline",
            errorMessage: "Neither the Antigravity app nor the agy CLI answered.",
            actionSuggestion: suggestion,
            accountDetail: nil,
            lastUpdated: Date()
        )
    }

    private static func removeLegacySessionFile() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let legacy = support.appending(path: "MonoAiBar/antigravity_session.json")
        try? FileManager.default.removeItem(at: legacy)
        UserDefaults.standard.removeObject(forKey: "MonoHub_aiQuota_last_antigravity_port")
    }
}
