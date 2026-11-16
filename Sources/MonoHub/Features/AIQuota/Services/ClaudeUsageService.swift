import Foundation
import OSLog

nonisolated struct ClaudeUsageResponse: Decodable {
    struct FlexibleCents: Decodable {
        let cents: Double

        private struct MoneyObject: Decodable {
            let amount_minor: Double?
            let exponent: Int?
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self.cents = number
            } else if let obj = try? container.decode(MoneyObject.self), let minor = obj.amount_minor {
                let exp = obj.exponent ?? 2
                self.cents = exp == 2 ? minor : (minor / pow(10.0, Double(exp))) * 100.0
            } else {
                throw DecodingError.typeMismatch(
                    Double.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported money format")
                )
            }
        }
    }

    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?

        private enum CodingKeys: String, CodingKey {
            case utilization, resets_at
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
            self.resets_at = try? c.decodeIfPresent(String.self, forKey: .resets_at)
        }
    }

    struct ExtraUsage: Decodable {
        let is_enabled: Bool?
        let utilization: Double?
        let used_credits: Double?
        let monthly_limit: Double?

        private enum CodingKeys: String, CodingKey {
            case is_enabled, utilization, used_credits, monthly_limit
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.is_enabled = try? c.decodeIfPresent(Bool.self, forKey: .is_enabled)
            self.utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
            self.used_credits = (try? c.decodeIfPresent(FlexibleCents.self, forKey: .used_credits))?.cents
            self.monthly_limit = (try? c.decodeIfPresent(FlexibleCents.self, forKey: .monthly_limit))?.cents
        }
    }

    struct LimitEntry: Decodable {
        let kind: String?
        let percent: Double?
        let resets_at: String?
        let is_active: Bool?

        private enum CodingKeys: String, CodingKey {
            case kind, percent, resets_at, is_active
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            self.percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
            self.resets_at = try? c.decodeIfPresent(String.self, forKey: .resets_at)
            self.is_active = try? c.decodeIfPresent(Bool.self, forKey: .is_active)
        }
    }

    struct SpendInfo: Decodable {
        let used: Double?
        let limit: Double?
        let percent: Double?
        let enabled: Bool?

        private enum CodingKeys: String, CodingKey {
            case used, limit, percent, enabled
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.used = (try? c.decodeIfPresent(FlexibleCents.self, forKey: .used))?.cents
            self.limit = (try? c.decodeIfPresent(FlexibleCents.self, forKey: .limit))?.cents
            self.percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
            self.enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        }
    }

    let five_hour: Window?
    let seven_day: Window?
    let seven_day_sonnet: Window?
    let seven_day_opus: Window?
    let seven_day_cowork: Window?
    let extra_usage: ExtraUsage?
    let limits: [LimitEntry]?
    let spend: SpendInfo?

    private enum CodingKeys: String, CodingKey {
        case five_hour, seven_day, seven_day_sonnet, seven_day_opus, seven_day_cowork, extra_usage, limits, spend
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.five_hour = try? c.decodeIfPresent(Window.self, forKey: .five_hour)
        self.seven_day = try? c.decodeIfPresent(Window.self, forKey: .seven_day)
        self.seven_day_sonnet = try? c.decodeIfPresent(Window.self, forKey: .seven_day_sonnet)
        self.seven_day_opus = try? c.decodeIfPresent(Window.self, forKey: .seven_day_opus)
        self.seven_day_cowork = try? c.decodeIfPresent(Window.self, forKey: .seven_day_cowork)
        self.extra_usage = try? c.decodeIfPresent(ExtraUsage.self, forKey: .extra_usage)
        self.limits = try? c.decodeIfPresent([LimitEntry].self, forKey: .limits)
        self.spend = try? c.decodeIfPresent(SpendInfo.self, forKey: .spend)
    }
}

actor ClaudeUsageService {
    static let shared = ClaudeUsageService()

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let defaultBackoff: TimeInterval = 60

    private let http = HTTPClient(timeout: 6.0, resourceTimeout: 8.0)
    private let decoder = JSONDecoder()

    private var backoffUntil: Date?

    func fetchUsage(force: Bool = false) async -> ProviderStatus {
        if force {
            backoffUntil = nil
        }
        switch await CredentialStore.shared.claudeCredential(forceReload: force) {
        case .missing, .needsKeychainApproval:
            return ProviderStatus(
                provider: .claude,
                state: .notFound("Token Required"),
                planName: "Claude Code",
                authSource: "Long-Lived Token",
                errorMessage: "Connect using a 1-year token to avoid macOS Keychain prompts.",
                actionSuggestion: "Run `claude setup-token` in terminal or configure in Settings.",
                lastUpdated: Date()
            )
        case .found(let credential):
            return await requestUsage(with: credential, retryingAfterReload: true)
        }
    }

    private func requestUsage(with credential: ClaudeCredential, retryingAfterReload: Bool) async -> ProviderStatus {
        if let backoffUntil, backoffUntil > Date() {
            return rateLimitedStatus(credential: credential)
        }
        guard !credential.isExpired else {
            if let renewed = await CredentialStore.shared.refreshSessionIfNeeded(for: credential) {
                return await requestUsage(with: renewed, retryingAfterReload: false)
            }
            return expiredStatus(credential: credential)
        }

        var request = URLRequest.get(Self.usageURL, timeout: 6.0, bearer: credential.accessToken, userAgent: AppInfo.userAgent)
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await http.send(request)

            switch response.statusCode {
            case 200:
                backoffUntil = nil
                return Self.decodeUsage(data, credential: credential, decoder: decoder)

            case 401, 403:
                await CredentialStore.shared.invalidateClaudeCache()
                if retryingAfterReload {

                    if let reloaded = await CredentialStore.shared.reloadClaudeFromLiveSources(excludingToken: credential.accessToken) {
                        return await requestUsage(with: reloaded, retryingAfterReload: false)
                    }

                    if let renewed = await CredentialStore.shared.refreshSessionIfNeeded(for: credential) {
                        return await requestUsage(with: renewed, retryingAfterReload: false)
                    }
                }
                return expiredStatus(credential: credential)

            case 429:
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                backoffUntil = Date().addingTimeInterval(max(30, retryAfter ?? Self.defaultBackoff))
                return rateLimitedStatus(credential: credential)

            default:
                return ProviderStatus(
                    provider: .claude,
                    state: .error("HTTP \(response.statusCode)"),
                    planName: credential.plan,
                    authSource: credential.sourceLabel,
                    errorMessage: "Anthropic returned HTTP \(response.statusCode).",
                    lastUpdated: Date()
                )
            }
        } catch {
            Log.quota.debug("claude usage request failed: \(error.localizedDescription, privacy: .public)")
            return ProviderStatus(
                provider: .claude,
                state: .error("Offline"),
                planName: credential.plan,
                authSource: credential.sourceLabel,
                errorMessage: error.localizedDescription,
                lastUpdated: Date()
            )
        }
    }

    private func expiredStatus(credential: ClaudeCredential) -> ProviderStatus {
        ProviderStatus(
            provider: .claude,
            state: .expired("Session Expired"),
            planName: credential.plan,
            authSource: credential.sourceLabel,
            errorMessage: "The Claude Code session token has expired.",
            actionSuggestion: "Open `claude` once; it renews the session and MonoHub picks it up.",
            accountDetail: credential.accountDetail,
            lastUpdated: Date()
        )
    }

    private func rateLimitedStatus(credential: ClaudeCredential) -> ProviderStatus {
        ProviderStatus(
            provider: .claude,
            state: .warning("Rate Limited"),
            planName: credential.plan,
            authSource: credential.sourceLabel,
            errorMessage: "Anthropic is throttling quota lookups.",
            actionSuggestion: backoffUntil.map { "Next attempt \($0.formatted(date: .omitted, time: .shortened))." },
            accountDetail: credential.accountDetail,
            lastUpdated: Date()
        )
    }

    nonisolated static func normalizeResetDate(_ date: Date?) -> Date? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince1970
        let nearestMinute = (seconds / 60.0).rounded() * 60.0
        if abs(seconds - nearestMinute) <= 2.0 {
            return Date(timeIntervalSince1970: nearestMinute)
        }
        return date
    }

    nonisolated static func decodeUsage(
        _ data: Data,
        credential: ClaudeCredential,
        decoder: JSONDecoder = JSONDecoder()
    ) -> ProviderStatus {
        guard let decoded = try? decoder.decode(ClaudeUsageResponse.self, from: data) else {
            return ProviderStatus(
                provider: .claude,
                state: .error("Unreadable Response"),
                planName: credential.plan,
                authSource: credential.sourceLabel,
                errorMessage: "Anthropic's usage payload did not match the expected shape.",
                lastUpdated: Date()
            )
        }

        var windows = [
            ("Session", decoded.five_hour, Int64(5 * 3600)),
            ("Weekly", decoded.seven_day, Int64(7 * 86_400)),
            ("Weekly · Sonnet", decoded.seven_day_sonnet, Int64(7 * 86_400)),
            ("Weekly · Opus", decoded.seven_day_opus, Int64(7 * 86_400)),
            ("Weekly · Cowork", decoded.seven_day_cowork, Int64(7 * 86_400))
        ].compactMap { name, window, span -> QuotaWindow? in
            guard let utilization = window?.utilization else { return nil }
            return QuotaWindow(
                name: name,
                usedPercent: utilization,
                resetsAt: normalizeResetDate(ISO8601.date(from: window?.resets_at)),
                limitWindowSeconds: span
            )
        }

        if let limits = decoded.limits {
            var existingNames = Set(windows.map(\.name))
            for entry in limits {
                guard let kind = entry.kind, let percent = entry.percent else { continue }
                if entry.is_active == false && kind != "session" && kind != "weekly_all" && percent == 0 {
                    continue
                }
                let mapped: (name: String, span: Int64)? = switch kind {
                case "session": ("Session", Int64(5 * 3600))
                case "weekly_all": ("Weekly", Int64(7 * 86_400))
                case "weekly_sonnet": ("Weekly · Sonnet", Int64(7 * 86_400))
                case "weekly_opus": ("Weekly · Opus", Int64(7 * 86_400))
                case "weekly_cowork": ("Weekly · Cowork", Int64(7 * 86_400))
                default: nil
                }
                if let mapped, !existingNames.contains(mapped.name) {
                    existingNames.insert(mapped.name)
                    windows.append(QuotaWindow(
                        name: mapped.name,
                        usedPercent: percent,
                        resetsAt: normalizeResetDate(ISO8601.date(from: entry.resets_at)),
                        limitWindowSeconds: mapped.span
                    ))
                }
            }
        }

        let extraPercent = (decoded.extra_usage?.is_enabled == true ? decoded.extra_usage?.utilization : nil)
            ?? (decoded.spend?.enabled == true ? decoded.spend?.percent : nil)
        if let extraPercent {
            windows.append(QuotaWindow(name: "Extra Usage", usedPercent: extraPercent, limitWindowSeconds: 30 * 86_400))
        }

        var balance: ProviderBalance?
        if decoded.spend?.enabled == true,
           let used = decoded.spend?.used,
           let limit = decoded.spend?.limit,
           limit > 0 {
            let usedDollars = used / 100.0
            let limitDollars = limit / 100.0
            let remaining = max(0, limitDollars - usedDollars)
            balance = ProviderBalance(
                amount: remaining,
                currency: "USD",
                lines: [
                    .init(label: "Used this month", amount: usedDollars),
                    .init(label: "Monthly limit", amount: limitDollars)
                ]
            )
        } else if decoded.extra_usage?.is_enabled == true,
                  let used = decoded.extra_usage?.used_credits,
                  let limit = decoded.extra_usage?.monthly_limit,
                  limit > 0 {
            let usedDollars = used / 100.0
            let limitDollars = limit / 100.0
            let remaining = max(0, limitDollars - usedDollars)
            balance = ProviderBalance(
                amount: remaining,
                currency: "USD",
                lines: [
                    .init(label: "Used this month", amount: usedDollars),
                    .init(label: "Monthly limit", amount: limitDollars)
                ]
            )
        }

        var status = ProviderStatus(
            provider: .claude,
            state: .healthy,
            planName: credential.plan,
            authSource: credential.sourceLabel,
            windows: windows,
            balance: balance,
            accountDetail: credential.accountDetail,
            lastUpdated: Date()
        )
        status.state = ProviderStatus.nearLimitState(peak: status.peakUsagePercent)
        return status
    }
}
