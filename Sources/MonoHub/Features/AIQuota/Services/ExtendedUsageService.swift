import Foundation
import OSLog

actor ExtendedUsageService {
    static let shared = ExtendedUsageService()

    private init() {}

    func fetchUsage(for provider: ProviderType) async -> ProviderStatus {
        switch provider {
        case .nous:
            return await fetchNous()
        case .supergrok:
            return await fetchSuperGrok()
        case .deepinfra:
            return await fetchDeepInfra()
        case .minimax:
            return await fetchMiniMax()
        case .ollama:
            return await fetchOllama()
        case .kilo:
            return await fetchKilo()
        case .novita:
            return await fetchNovita()
        case .moonshot:
            return await fetchMoonshot()
        case .orcarouter:
            return await fetchOrcaRouter()
        case .modelstudio:
            return await fetchModelStudio()
        case .opencodeGo:
            return await fetchOpenCodeGo()
        case .kiro:
            return await fetchKiro()
        default:
            return ProviderStatus.initial(for: provider)
        }
    }

    private func fetchNous() async -> ProviderStatus {
        guard let key = resolveKey(service: "nous", envVar: "NOUS_API_KEY") else {
            return notFound(provider: .nous, message: "NOUS_API_KEY Required")
        }
        let url = URL(string: "https://portal.nousresearch.com/api/oauth/account")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .nous)
        }
        let subUsage = (json["subscription_usage"] as? NSNumber)?.doubleValue ?? 0.0
        let subCredits = (json["subscription_credits"] as? NSNumber)?.doubleValue ?? 100.0
        let usedPct = subCredits > 0 ? (subUsage / subCredits) * 100.0 : 0.0

        let windows = [QuotaWindow(name: "Subscription Credits", usedPercent: usedPct)]
        return ProviderStatus(
            provider: .nous,
            state: .healthy,
            planName: "Nous Portal",
            authSource: "API Key",
            windows: windows,
            lastUpdated: Date()
        )
    }

    private func fetchSuperGrok() async -> ProviderStatus {
        let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        var token = resolveKey(service: "supergrok", envVar: "GROK_AUTH_TOKEN")
        if token == nil, let data = try? Data(contentsOf: authURL),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            token = json["access_token"] as? String ?? json["token"] as? String
        }

        guard let token else {
            return notFound(provider: .supergrok, message: "Run `grok login` or set token")
        }

        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!
        guard let json = await getJSON(url: url, bearer: token) else {
            return errorStatus(provider: .supergrok)
        }

        var windows: [QuotaWindow] = []
        if let weekly = json["weekly_usage"] as? NSNumber {
            windows.append(QuotaWindow(name: "Weekly Included", usedPercent: weekly.doubleValue))
        }

        var banked: [BankedCredit] = []
        if let resets = json["banked_resets"] as? [[String: Any]] {
            for item in resets {
                let amount = (item["amount"] as? NSNumber)?.doubleValue ?? 1.0
                let expiry = ISO8601.date(from: item["expires_at"] as? String)
                banked.append(BankedCredit(amount: amount, expiresAt: expiry, label: "Banked Reset"))
            }
        }

        return ProviderStatus(
            provider: .supergrok,
            state: .healthy,
            planName: "SuperGrok",
            authSource: "Grok Login",
            windows: windows,
            bankedCredits: banked,
            lastUpdated: Date()
        )
    }

    private func fetchDeepInfra() async -> ProviderStatus {
        guard let key = resolveKey(service: "deepinfra", envVar: "DEEPINFRA_API_KEY") else {
            return notFound(provider: .deepinfra, message: "DEEPINFRA_API_KEY Required")
        }
        let url = URL(string: "https://api.deepinfra.com/payment/checklist")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .deepinfra)
        }
        let balance = (json["balance"] as? NSNumber)?.doubleValue ?? 0.0
        return ProviderStatus(
            provider: .deepinfra,
            state: .healthy,
            planName: "Prepaid",
            authSource: "API Key",
            balance: ProviderBalance(amount: balance, currency: "USD", lines: [.init(label: "Available", amount: balance)]),
            lastUpdated: Date()
        )
    }

    private func fetchMiniMax() async -> ProviderStatus {
        guard let key = resolveKey(service: "minimax", envVar: "MINIMAX_API_KEY") else {
            return notFound(provider: .minimax, message: "MINIMAX_API_KEY Required")
        }
        let url = URL(string: "https://api.minimax.io/v1/token_plan/remains")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .minimax)
        }
        var windows: [QuotaWindow] = []
        if let current = json["current_interval_percent"] as? NSNumber {
            windows.append(QuotaWindow(name: "Token Plan Interval", usedPercent: current.doubleValue))
        }
        return ProviderStatus(
            provider: .minimax,
            state: .healthy,
            planName: "Token Plan",
            authSource: "API Key",
            windows: windows,
            lastUpdated: Date()
        )
    }

    private func fetchOllama() async -> ProviderStatus {
        guard let key = resolveKey(service: "ollama", envVar: "OLLAMA_API_KEY") else {
            return notFound(provider: .ollama, message: "OLLAMA_API_KEY Required")
        }
        let url = URL(string: "https://ollama.com/api/usage")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .ollama)
        }
        var windows: [QuotaWindow] = []
        if let sessionPct = (json["session_percent"] as? NSNumber)?.doubleValue {
            windows.append(QuotaWindow(name: "Session Usage", usedPercent: sessionPct))
        }
        if let weeklyPct = (json["weekly_percent"] as? NSNumber)?.doubleValue {
            windows.append(QuotaWindow(name: "Weekly Usage", usedPercent: weeklyPct))
        }
        return ProviderStatus(
            provider: .ollama,
            state: .healthy,
            planName: "Ollama Cloud",
            authSource: "API Key",
            windows: windows,
            lastUpdated: Date()
        )
    }

    private func fetchKilo() async -> ProviderStatus {
        guard let key = resolveKey(service: "kilo", envVar: "KILO_API_KEY") else {
            return notFound(provider: .kilo, message: "KILO_API_KEY Required")
        }
        let url = URL(string: "https://api.kilo.ai/api/profile/balance")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .kilo)
        }
        let balance = (json["balance"] as? NSNumber)?.doubleValue ?? 0.0
        return ProviderStatus(
            provider: .kilo,
            state: .healthy,
            planName: "Kilo Profile",
            authSource: "API Key",
            balance: ProviderBalance(amount: balance, currency: "USD", lines: [.init(label: "Balance", amount: balance)]),
            lastUpdated: Date()
        )
    }

    private func fetchNovita() async -> ProviderStatus {
        guard let key = resolveKey(service: "novita", envVar: "NOVITA_API_KEY") else {
            return notFound(provider: .novita, message: "NOVITA_API_KEY Required")
        }
        let url = URL(string: "https://api.novita.ai/openapi/v1/billing/balance/detail")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .novita)
        }
        let balance = ((json["data"] as? [String: Any])?["amount"] as? NSNumber)?.doubleValue ?? 0.0
        return ProviderStatus(
            provider: .novita,
            state: .healthy,
            planName: "Novita AI",
            authSource: "API Key",
            balance: ProviderBalance(amount: balance, currency: "USD", lines: [.init(label: "Balance", amount: balance)]),
            lastUpdated: Date()
        )
    }

    private func fetchMoonshot() async -> ProviderStatus {
        guard let key = resolveKey(service: "moonshot", envVar: "MOONSHOT_API_KEY") else {
            return notFound(provider: .moonshot, message: "MOONSHOT_API_KEY Required")
        }
        let url = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .moonshot)
        }
        let balance = ((json["data"] as? [String: Any])?["available_balance"] as? NSNumber)?.doubleValue ?? 0.0
        return ProviderStatus(
            provider: .moonshot,
            state: .healthy,
            planName: "Moonshot",
            authSource: "API Key",
            balance: ProviderBalance(amount: balance, currency: "USD", lines: [.init(label: "Balance", amount: balance)]),
            lastUpdated: Date()
        )
    }

    private func fetchOrcaRouter() async -> ProviderStatus {
        guard let key = resolveKey(service: "orcarouter", envVar: "ORCAROUTER_API_KEY") else {
            return notFound(provider: .orcarouter, message: "ORCAROUTER_API_KEY Required")
        }
        let url = URL(string: "https://api.orcarouter.ai/v1/dashboard/billing/subscription")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .orcarouter)
        }
        let balance = (json["hard_limit_usd"] as? NSNumber)?.doubleValue ?? 0.0
        return ProviderStatus(
            provider: .orcarouter,
            state: .healthy,
            planName: "OrcaRouter",
            authSource: "API Key",
            balance: ProviderBalance(amount: balance, currency: "USD", lines: [.init(label: "Limit", amount: balance)]),
            lastUpdated: Date()
        )
    }

    private func fetchModelStudio() async -> ProviderStatus {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bailian/config.json")
        guard let data = try? Data(contentsOf: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return notFound(provider: .modelstudio, message: "Run `bl auth login --console`")
        }
        let plan = (json["plan"] as? String) ?? "Model Studio"
        return ProviderStatus(
            provider: .modelstudio,
            state: .healthy,
            planName: plan,
            authSource: "CLI Login",
            lastUpdated: Date()
        )
    }

    private func fetchOpenCodeGo() async -> ProviderStatus {
        guard let key = resolveKey(service: "opencodeGo", envVar: "OPENCODE_GO_API_KEY")
            ?? resolveKey(service: "opencode-go", envVar: "OPENCODE_GO_API_KEY") else {
            return notFound(provider: .opencodeGo, message: "OPENCODE_GO_API_KEY Required")
        }
        let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!
        guard let json = await getJSON(url: url, bearer: key) else {
            return errorStatus(provider: .opencodeGo)
        }
        var windows: [QuotaWindow] = []
        if let pct = (json["percent"] as? NSNumber)?.doubleValue {
            windows.append(QuotaWindow(name: "Quota Pool", usedPercent: pct))
        }
        return ProviderStatus(
            provider: .opencodeGo,
            state: .healthy,
            planName: "OpenCode Go",
            authSource: "API Key",
            windows: windows,
            lastUpdated: Date()
        )
    }

    private func fetchKiro() async -> ProviderStatus {
        let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kiro/credentials.json")
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            return notFound(provider: .kiro, message: "Run `kiro-cli login`")
        }
        return ProviderStatus(
            provider: .kiro,
            state: .healthy,
            planName: "Kiro CLI",
            authSource: "Local CLI",
            lastUpdated: Date()
        )
    }

    private func getJSON(url: URL, bearer: String) async -> [String: Any]? {
        let request = URLRequest.get(url, timeout: 10.0, bearer: bearer, userAgent: AppInfo.userAgent)

        guard let (data, http) = try? await HTTPClient.shared.data(for: request),
              http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func notFound(provider: ProviderType, message: String) -> ProviderStatus {
        ProviderStatus(
            provider: provider,
            state: .notFound(message),
            planName: "Not Configured",
            authSource: "Settings",
            actionSuggestion: message
        )
    }

    private func errorStatus(provider: ProviderType) -> ProviderStatus {
        ProviderStatus(provider: provider, state: .error("Network / Schema Error"), planName: provider.displayName)
    }

    private func resolveKey(service: String, envVar: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[envVar], !env.isEmpty {
            return env
        }
        return Keychain.read(service: "com.joaooliveiratech.monohub.\(service)", account: "default")?.secret
    }
}
