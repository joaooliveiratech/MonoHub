import Foundation
import OSLog

nonisolated struct ClaudeCredential: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAtMilliseconds: Int64?
    let plan: String
    let sourceLabel: String
    let accountDetail: String?
    let rawJSON: String?

    var isExpired: Bool {
        guard let expiresAtMilliseconds else { return false }
        return expiresAtMilliseconds <= Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1000)
    }
}

nonisolated enum ClaudeLookup: Sendable {
    case found(ClaudeCredential)
    case needsKeychainApproval
    case missing
}

actor CredentialStore {
    static let shared = CredentialStore()

    enum Service {
        static let claudeCode = "Claude Code-credentials"
        static let claudeSession = "com.joaooliveiratech.monohub.claude.session"
        static let customClaudeToken = "com.joaooliveiratech.monohub.claude.custom"
        static let legacyClaudeCache = "com.joaooliveiratech.monohub.claude"

        static func apiKey(for provider: ProviderType) -> String {
            "com.joaooliveiratech.monohub.\(provider.id)"
        }
    }

    private static let account = NSUserName()
    private static let cacheTTL: TimeInterval = 900.0

    private var cachedClaude: ClaudeCredential?
    private var cachedClaudeAt: Date?
    private var lastCLISecurityCheckAt: Date?
    private var didMigrateLegacyStorage = false

    private init() {}

    func claudeCredential(forceReload: Bool = false) async -> ClaudeLookup {
        migrateLegacyStorageIfNeeded()

        if let userSupplied = userSuppliedClaudeCredential() {
            return .found(userSupplied)
        }
        if let fromSettings = claudeCredentialFromSettingsFiles() {
            return .found(fromSettings)
        }
        if let fromEnvironment = claudeCredentialFromEnvironment() {
            return .found(fromEnvironment)
        }
        if !forceReload,
           let cachedClaude,
           !cachedClaude.isExpired,
           let cachedClaudeAt,
           Date().timeIntervalSince(cachedClaudeAt) < Self.cacheTTL {
            return .found(cachedClaude)
        }

        var candidates: [ClaudeCredential] = []

        let fileCreds = claudeCredentialsFromFiles()
        if let validFileCred = fileCreds.first(where: { !$0.isExpired }) {
            remember(validFileCred)
            return .found(validFileCred)
        }
        candidates.append(contentsOf: fileCreds)

        if let item = Keychain.read(service: Service.claudeSession),
           let credential = parse(secret: item.secret, sourceLabel: "Claude Code Local") {
            if !credential.isExpired {
                cachedClaude = credential
                cachedClaudeAt = Date()
                return .found(credential)
            }
            candidates.append(credential)
        }

        let shouldQueryCLI = forceReload
            || lastCLISecurityCheckAt.map { Date().timeIntervalSince($0) >= 300.0 } ?? true
        if shouldQueryCLI {
            lastCLISecurityCheckAt = Date()
            if let cliCred = await claudeCredentialFromCLI() {
                if !cliCred.isExpired {
                    remember(cliCred)
                    return .found(cliCred)
                }
                candidates.append(cliCred)
            }
        }

        let expiredWithRefresh = candidates
            .filter { ($0.refreshToken ?? "").isEmpty == false }
            .sorted { ($0.expiresAtMilliseconds ?? 0) > ($1.expiresAtMilliseconds ?? 0) }

        for candidate in expiredWithRefresh {
            if let renewed = await refreshSessionIfNeeded(for: candidate) {
                return .found(renewed)
            }
        }

        let usable = candidates.filter { !$0.isExpired }
        if let freshest = usable.max(by: { ($0.expiresAtMilliseconds ?? .max) < ($1.expiresAtMilliseconds ?? .max) }) {
            cachedClaude = freshest
            cachedClaudeAt = Date()
            return .found(freshest)
        }

        return .missing
    }

    func reloadClaudeFromLiveSources(excludingToken: String? = nil) async -> ClaudeCredential? {
        cachedClaude = nil
        cachedClaudeAt = nil

        if let cliCred = await claudeCredentialFromCLI(),
           !cliCred.isExpired,
           cliCred.accessToken != excludingToken {
            remember(cliCred)
            return cliCred
        }

        for fileCred in claudeCredentialsFromFiles() where !fileCred.isExpired && fileCred.accessToken != excludingToken {
            remember(fileCred)
            return fileCred
        }

        return nil
    }

    func refreshSessionIfNeeded(for credential: ClaudeCredential) async -> ClaudeCredential? {
        if let live = await reloadClaudeFromLiveSources(excludingToken: credential.accessToken) {
            return live
        }
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty,
              let rawJSON = credential.rawJSON else { return nil }
        return await renewToken(refreshToken: refreshToken, rawJSON: rawJSON, sourceLabel: credential.sourceLabel)
    }

    private func renewToken(refreshToken: String, rawJSON: String, sourceLabel: String) async -> ClaudeCredential? {
        let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
        var request = URLRequest(url: tokenURL, timeoutInterval: 8.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "refresh_token": refreshToken
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData

        guard let (data, response) = try? await HTTPClient.shared.send(request),
              response.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String else {
            return nil
        }

        let newRefresh = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 28800.0
        let newExpiresAt = Int64(Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000)

        guard var root = (try? JSONSerialization.jsonObject(with: rawJSON.data(using: .utf8) ?? Data())) as? [String: Any] else {
            return nil
        }
        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = newAccess
        oauth["refreshToken"] = newRefresh
        oauth["expiresAt"] = newExpiresAt
        root["claudeAiOauth"] = oauth

        guard let updatedData = try? JSONSerialization.data(withJSONObject: root),
              let updatedString = String(data: updatedData, encoding: .utf8) else {
            return nil
        }

        _ = await writeClaudeCredentialToCLI(secret: updatedString)
        writeClaudeCredentialToLocalFile(secret: updatedString)

        if let renewed = parse(secret: updatedString, sourceLabel: sourceLabel) {
            remember(renewed)
            return renewed
        }
        return nil
    }

    private static var securityEnvironment: [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return [
            "PATH": "/usr/bin:/bin",
            "HOME": home,
            "USER": account,
            "LOGNAME": account
        ]
    }

    private func claudeCredentialFromCLI() async -> ClaudeCredential? {
        let executable = URL(fileURLWithPath: "/usr/bin/security")
        guard CommandRunner.isTrustedExecutable(executable) else { return nil }
        do {
            let data = try await CommandRunner.run(
                executable: executable,
                arguments: ["find-generic-password", "-s", Service.claudeCode, "-w"],
                workingDirectory: FileManager.default.temporaryDirectory,
                environment: Self.securityEnvironment,
                timeout: .seconds(4),
                maximumOutputBytes: 65536
            )
            guard let rawText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawText.isEmpty else { return nil }
            let text = Self.decodeSecurityOutput(rawText)
            return parse(secret: text, sourceLabel: "Claude Code Keychain")
        } catch {
            return nil
        }
    }

    nonisolated static func decodeSecurityOutput(_ raw: String) -> String {
        if raw.hasPrefix("{") || raw.hasPrefix("sk-ant-") {
            return raw
        }
        let clean = raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
        guard clean.count >= 4, clean.count.isMultiple(of: 2) else { return raw }
        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return raw }
            bytes.append(byte)
            index = next
        }
        if let decoded = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !decoded.isEmpty {
            return decoded
        }
        return raw
    }

    private func writeClaudeCredentialToCLI(secret: String) async -> Bool {
        let executable = URL(fileURLWithPath: "/usr/bin/security")
        guard CommandRunner.isTrustedExecutable(executable) else { return false }
        do {
            _ = try await CommandRunner.run(
                executable: executable,
                arguments: ["add-generic-password", "-U", "-s", Service.claudeCode, "-a", Self.account, "-w", secret],
                workingDirectory: FileManager.default.temporaryDirectory,
                environment: Self.securityEnvironment,
                timeout: .seconds(4),
                maximumOutputBytes: 1024
            )
            return true
        } catch {
            return false
        }
    }

    private func writeClaudeCredentialToLocalFile(secret: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appending(path: ".claude")
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let credentialsURL = claudeDir.appending(path: ".credentials.json")
        guard let data = secret.data(using: .utf8) else { return }
        try? data.write(to: credentialsURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialsURL.path(percentEncoded: false)
        )
    }

    func invalidateClaudeCache() {
        cachedClaude = nil
        cachedClaudeAt = nil
        Keychain.delete(service: Service.claudeSession)
    }

    func customClaudeToken() -> String {
        Keychain.read(service: Service.customClaudeToken)?.secret ?? ""
    }

    func setCustomClaudeToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Service.customClaudeToken)
        } else {
            Keychain.write(service: Service.customClaudeToken, account: Self.account, secret: trimmed)
        }
        cachedClaude = nil
        cachedClaudeAt = nil
    }

    func resyncClaude() async -> Bool {
        cachedClaude = nil
        cachedClaudeAt = nil
        if case .found = await claudeCredential(forceReload: true) { return true }
        return false
    }

    private func remember(_ credential: ClaudeCredential) {
        cachedClaude = credential
        cachedClaudeAt = Date()
        var payload: [String: Any] = ["accessToken": credential.accessToken, "plan": credential.plan]
        if let refresh = credential.refreshToken { payload["refreshToken"] = refresh }
        if let expiresAt = credential.expiresAtMilliseconds { payload["expiresAt"] = expiresAt }
        if let detail = credential.accountDetail { payload["accountDetail"] = detail }
        if let raw = credential.rawJSON { payload["rawJSON"] = raw }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        Keychain.write(service: Service.claudeSession, account: Self.account, secret: text)
    }

    func apiKey(for provider: ProviderType) -> String {
        migrateLegacyStorageIfNeeded()
        return Keychain.read(service: Service.apiKey(for: provider))?.secret ?? ""
    }

    func setAPIKey(_ key: String, for provider: ProviderType) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Service.apiKey(for: provider))
        } else {
            Keychain.write(service: Service.apiKey(for: provider), account: Self.account, secret: trimmed)
        }
    }

    private func userSuppliedClaudeCredential() -> ClaudeCredential? {
        let token = customClaudeToken()
        guard !token.isEmpty else { return nil }

        let looksLikeOAuth = token.hasPrefix("sk-ant-oat") || token.hasPrefix("sk-ant-sso") || token.count > 60
        return ClaudeCredential(
            accessToken: token,
            refreshToken: nil,
            expiresAtMilliseconds: nil,
            plan: looksLikeOAuth ? "Claude OAuth (Custom)" : "Claude API Key",
            sourceLabel: "Settings",
            accountDetail: nil,
            rawJSON: nil
        )
    }

    private func claudeCredentialsFromFiles() -> [ClaudeCredential] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: ".claude/.credentials.json"),
            home.appending(path: ".claude/credentials.json")
        ].compactMap { url in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return parse(secret: text, sourceLabel: url.lastPathComponent)
        }
    }

    private func claudeCredentialFromSettingsFiles() -> ClaudeCredential? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appending(path: ".claude/settings.json"),
            home.appending(path: ".claude.json")
        ]

        for url in files {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let environment = root["env"] as? [String: Any] else { continue }

            for key in ["CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_TOKEN"] {
                guard let raw = environment[key] as? String else { continue }
                let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { continue }
                return ClaudeCredential(
                    accessToken: token,
                    refreshToken: nil,
                    expiresAtMilliseconds: nil,
                    plan: key == "CLAUDE_CODE_OAUTH_TOKEN" ? "Claude OAuth (Long-Lived)" : "Claude Token",
                    sourceLabel: "\(url.lastPathComponent) (env)",
                    accountDetail: nil,
                    rawJSON: nil
                )
            }
        }
        return nil
    }

    private func claudeCredentialFromEnvironment() -> ClaudeCredential? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            ("CLAUDE_CODE_OAUTH_TOKEN", "Claude OAuth (Long-Lived)"),
            ("CLAUDE_CODE_TOKEN", "Claude Token")
        ]

        for (key, plan) in candidates {
            guard let raw = environment[key] else { continue }
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            return ClaudeCredential(
                accessToken: token,
                refreshToken: nil,
                expiresAtMilliseconds: nil,
                plan: plan,
                sourceLabel: "$\(key)",
                accountDetail: nil,
                rawJSON: nil
            )
        }
        return nil
    }

    private func parse(secret: String, sourceLabel: String) -> ClaudeCredential? {
        guard let data = secret.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            guard secret.hasPrefix("sk-ant-") else { return nil }
            return ClaudeCredential(
                accessToken: secret,
                refreshToken: nil,
                expiresAtMilliseconds: nil,
                plan: "Claude OAuth",
                sourceLabel: sourceLabel,
                accountDetail: nil,
                rawJSON: nil
            )
        }

        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let accessToken = (oauth["accessToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else { return nil }

        let refreshToken = (oauth["refreshToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (root["refreshToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let plan: String
        if let stored = oauth["plan"] as? String, !stored.isEmpty {
            plan = stored
        } else if let subscription = oauth["subscriptionType"] as? String, !subscription.isEmpty {
            plan = "Claude \(subscription.capitalized)"
        } else {
            plan = "Claude Account"
        }

        let detail: String?
        if let raw = oauth["accountDetail"] as? String, !raw.contains("@"), !raw.isEmpty {
            detail = raw
        } else {
            detail = (oauth["rateLimitTier"] as? String).map { tier in
                "Tier: " + tier.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        return ClaudeCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMilliseconds: (oauth["expiresAt"] as? NSNumber)?.int64Value,
            plan: plan,
            sourceLabel: sourceLabel,
            accountDetail: detail,
            rawJSON: (root["rawJSON"] as? String) ?? secret
        )
    }

    private func migrateLegacyStorageIfNeeded() {
        guard !didMigrateLegacyStorage else { return }
        didMigrateLegacyStorage = true

        let defaults = UserDefaults.standard
        let legacyDefaults = [
            ("monobar_custom_claude_token", Service.customClaudeToken),
            ("monobar_codex_api_key", Service.apiKey(for: .codex))
        ]
        for (defaultsKey, service) in legacyDefaults {
            guard let value = defaults.string(forKey: defaultsKey) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed.isEmpty || Keychain.write(service: service, account: Self.account, secret: trimmed) else {
                Log.credentials.error("keeping \(defaultsKey, privacy: .public): keychain write failed")
                continue
            }
            defaults.removeObject(forKey: defaultsKey)
            Log.credentials.notice("migrated \(defaultsKey, privacy: .public) out of UserDefaults")
        }

        for obsoleteKey in [
            "monobar_grok_api_key",
            "monobar_deepseek_api_key",
            "monobar_mint_api_key",
            "monobar_kimi_api_key"
        ] where defaults.object(forKey: obsoleteKey) != nil {
            defaults.removeObject(forKey: obsoleteKey)
            Log.credentials.notice("removed obsolete \(obsoleteKey, privacy: .public) from UserDefaults")
        }

        Keychain.delete(service: Service.legacyClaudeCache)
        if let legacyFile = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "MonoAiBar/claude_credentials.json"),
           FileManager.default.fileExists(atPath: legacyFile.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: legacyFile)
            Log.credentials.notice("removed legacy Claude refresh-token cache")
        }
    }
}
