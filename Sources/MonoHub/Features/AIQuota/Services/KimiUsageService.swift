import Foundation
import OSLog

actor KimiUsageService {
    static let shared = KimiUsageService()

    private struct Token: Sendable {
        let value: String
        let source: String
        let isAPIKey: Bool
    }

    private static let codingHosts = [
        URL(string: "https://api.kimi.com/coding/v1/usages")!,
        URL(string: "https://api.kimi.ai/coding/v1/usages")!
    ]
    private static let balanceURL = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
    private static let membershipNames = ["LEVEL_BASIC": "Moderato"]

    private let http = HTTPClient(timeout: 6.0, resourceTimeout: 8.0)

    func fetchUsage() async -> ProviderStatus {
        guard let token = await loadToken() else {
            return ProviderStatus(
                provider: .kimi,
                state: .notFound("Not Connected"),
                planName: "Kimi Code",
                authSource: "Missing",
                errorMessage: "No Kimi Code session and no API key in Settings.",
                actionSuggestion: "Run `kimi login`, or add a Kimi API key in Settings › API Keys.",
                lastUpdated: Date()
            )
        }

        let hosts = token.isAPIKey ? Self.codingHosts : [Self.codingHosts[0]]
        var lastCode = 0
        for host in hosts {
            do {
                let (data, response) = try await send(host, token: token)
                lastCode = response.statusCode
                if response.statusCode == 200, let status = decodeCodingUsage(data, source: token.source) {
                    return status
                }
            } catch {
                Log.quota.debug("kimi usage request failed: \(error.localizedDescription, privacy: .public)")
                if !token.isAPIKey {
                    return APIKeyLookup.offlineStatus(for: .kimi, source: token.source, error: error)
                }
            }
        }

        if token.isAPIKey, let status = await fetchPlatformBalance(token: token) {
            return status
        }

        if !token.isAPIKey, lastCode == 401 {
            return ProviderStatus(
                provider: .kimi,
                state: .expired("Session Expired"),
                planName: "Kimi Code",
                authSource: token.source,
                errorMessage: "The Kimi Code session token has expired.",
                actionSuggestion: "Open `kimi` once to renew the session.",
                lastUpdated: Date()
            )
        }
        return lastCode == 200 || lastCode == 0
            ? APIKeyLookup.unreadableStatus(for: .kimi, source: token.source)
            : APIKeyLookup.httpFailureStatus(for: .kimi, code: lastCode, source: token.source)
    }

    private func send(_ url: URL, token: Token) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest.get(url, timeout: 6.0)
        request.setBearer(token.value)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await http.send(request)
    }

    private func decodeCodingUsage(_ data: Data, source: String) -> ProviderStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var windows: [QuotaWindow] = []

        if let pools = root["usages"] as? [String: Any] {
            let known: [(key: String, name: String, seconds: Int64)] = [
                ("limit_5h", "Session", 5 * 3600),
                ("limit_7d", "Weekly", 7 * 86_400),
                ("limit_month_total", "Monthly", 30 * 86_400)
            ]
            for pool in known {
                guard let entry = pools[pool.key] as? [String: Any],
                      let ratio = FlexibleNumber.double(entry["used_ratio"]) else { continue }
                windows.append(QuotaWindow(
                    name: pool.name,
                    usedPercent: min(1, ratio) * 100,
                    resetsAt: Self.resetDate(in: entry),
                    limitWindowSeconds: pool.seconds
                ))
            }
        }

        if windows.isEmpty {
            for limit in root["limits"] as? [[String: Any]] ?? [] {
                guard let detail = limit["detail"] as? [String: Any],
                      let percent = Self.percent(in: detail) else { continue }
                let seconds = Self.windowSeconds(limit["window"] as? [String: Any])
                windows.append(QuotaWindow(
                    name: seconds.map { $0 <= 6 * 3600 ? "Session" : "\($0 / 3600)-Hour Window" } ?? "Rate Window",
                    usedPercent: percent,
                    resetsAt: Self.resetDate(in: detail),
                    limitWindowSeconds: seconds
                ))
            }
            if let usage = root["usage"] as? [String: Any], let percent = Self.percent(in: usage) {
                windows.append(QuotaWindow(
                    name: "Weekly",
                    usedPercent: percent,
                    resetsAt: Self.resetDate(in: usage),
                    limitWindowSeconds: 7 * 86_400
                ))
            }
        }

        guard !windows.isEmpty else { return nil }

        let level = ((root["user"] as? [String: Any])?["membership"] as? [String: Any])?["level"] as? String
        var status = ProviderStatus(
            provider: .kimi,
            state: .healthy,
            planName: level.map { "Kimi Code \(Self.membershipName($0))" } ?? "Kimi Code",
            authSource: source,
            windows: windows,
            lastUpdated: Date()
        )
        status.state = ProviderStatus.nearLimitState(peak: status.peakUsagePercent)
        return status
    }

    private func fetchPlatformBalance(token: Token) async -> ProviderStatus? {
        guard let (data, response) = try? await send(Self.balanceURL, token: token),
              response.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let available = FlexibleNumber.double(payload["available_balance"]) else { return nil }

        let balance = ProviderBalance(
            amount: available,
            currency: "USD",
            lines: [("Cash", "cash_balance"), ("Voucher", "voucher_balance")].compactMap { label, key in
                FlexibleNumber.double(payload[key]).map { ProviderBalance.Line(label: label, amount: $0) }
            }
        )
        return ProviderStatus(
            provider: .kimi,
            state: available <= 0 ? .warning("No Balance") : .healthy,
            planName: "Moonshot API",
            authSource: token.source,
            balance: balance,
            lastUpdated: Date()
        )
    }

    private func loadToken() async -> Token? {
        if let key = await APIKeyLookup.key(for: .kimi, environment: ["KIMI_API_KEY", "MOONSHOT_API_KEY"]) {
            return Token(value: key.value, source: key.source, isAPIKey: true)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let customHome = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        let candidates = [customHome, home.appending(path: ".kimi-code"), home.appending(path: ".kimi")]
            .compactMap { $0?.appending(path: "credentials/kimi-code.json") }

        for url in candidates {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = root["access_token"] as? String, !accessToken.isEmpty else { continue }
            if let expiresAt = FlexibleNumber.double(root["expires_at"]), expiresAt <= Date().timeIntervalSince1970 + 60 {
                return Token(value: accessToken, source: "kimi CLI (expired)", isAPIKey: false)
            }
            return Token(value: accessToken, source: "kimi CLI", isAPIKey: false)
        }
        return nil
    }

    private static func membershipName(_ level: String) -> String {
        membershipNames[level] ?? level.replacingOccurrences(of: "LEVEL_", with: "").capitalized
    }

    private static func percent(in detail: [String: Any]) -> Double? {
        guard let limit = FlexibleNumber.double(detail["limit"]), limit > 0 else { return nil }
        if let used = FlexibleNumber.double(detail["used"]) {
            return used / limit * 100
        }
        return FlexibleNumber.double(detail["remaining"]).map { (limit - $0) / limit * 100 }
    }

    private static func resetDate(in entry: [String: Any]) -> Date? {
        for key in ["resetTime", "resetAt", "reset_time", "reset_at"] {
            if let text = entry[key] as? String, let date = ISO8601.date(from: text) {
                return date
            }
            if let seconds = FlexibleNumber.double(entry[key]) {
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            }
        }
        return nil
    }

    private static func windowSeconds(_ window: [String: Any]?) -> Int64? {
        guard let window, let duration = FlexibleNumber.double(window["duration"]) else { return nil }
        let unit: Double = switch window["timeUnit"] as? String {
        case "TIME_UNIT_MINUTE": 60
        case "TIME_UNIT_HOUR": 3600
        case "TIME_UNIT_DAY": 86_400
        default: 60
        }
        return Int64(duration * unit)
    }
}
