import Foundation
import OSLog

nonisolated private struct DeepSeekBalanceResponse: Decodable {
    struct BalanceInfo: Decodable {
        let currency: String?
        let total_balance: String?
        let granted_balance: String?
        let topped_up_balance: String?
    }

    let is_available: Bool?
    let balance_infos: [BalanceInfo]?
}

actor DeepSeekUsageService {
    static let shared = DeepSeekUsageService()

    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    private let http = HTTPClient(timeout: 6.0, resourceTimeout: 8.0)
    private let decoder = JSONDecoder()

    func fetchUsage() async -> ProviderStatus {
        guard let key = await APIKeyLookup.key(for: .deepseek, environment: ["DEEPSEEK_API_KEY"]) else {
            return APIKeyLookup.missingKeyStatus(for: .deepseek, planName: "DeepSeek API")
        }

        var request = URLRequest.get(Self.balanceURL, timeout: 6.0)
        request.setBearer(key.value)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await http.send(request)
            guard response.statusCode == 200 else {
                return APIKeyLookup.httpFailureStatus(for: .deepseek, code: response.statusCode, source: key.source)
            }
            guard let decoded = try? decoder.decode(DeepSeekBalanceResponse.self, from: data),
                  let infos = decoded.balance_infos, !infos.isEmpty else {
                return APIKeyLookup.unreadableStatus(for: .deepseek, source: key.source)
            }

            let preferred = infos.first { $0.currency == "USD" } ?? infos[0]
            let currency = preferred.currency ?? "USD"
            let balance = ProviderBalance(
                amount: Double(preferred.total_balance ?? "") ?? 0,
                currency: currency,
                lines: [
                    ("Topped Up", preferred.topped_up_balance),
                    ("Granted", preferred.granted_balance)
                ].compactMap { label, value in
                    Double(value ?? "").map { ProviderBalance.Line(label: label, amount: $0) }
                }
            )

            return ProviderStatus(
                provider: .deepseek,
                state: decoded.is_available == false || balance.amount <= 0 ? .warning("No Balance") : .healthy,
                planName: "DeepSeek API",
                authSource: key.source,
                balance: balance,
                accountDetail: infos.count > 1 ? "\(infos.count) currencies" : nil,
                lastUpdated: Date()
            )
        } catch {
            Log.quota.debug("deepseek balance request failed: \(error.localizedDescription, privacy: .public)")
            return APIKeyLookup.offlineStatus(for: .deepseek, source: key.source, error: error)
        }
    }
}

nonisolated enum APIKeyLookup {
    struct Key: Sendable {
        let value: String
        let source: String
    }

    static func key(for provider: ProviderType, environment names: [String]) async -> Key? {
        let stored = await CredentialStore.shared.apiKey(for: provider)
        if !stored.isEmpty {
            return Key(value: stored, source: "Keychain")
        }
        let environment = ProcessInfo.processInfo.environment
        for name in names {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return Key(value: value, source: "$\(name)")
            }
        }
        return nil
    }

    static func missingKeyStatus(for provider: ProviderType, planName: String) -> ProviderStatus {
        ProviderStatus(
            provider: provider,
            state: .notFound("Not Connected"),
            planName: planName,
            authSource: "Missing",
            errorMessage: "No \(provider.displayName) API key.",
            actionSuggestion: "Add your \(provider.displayName) API key in Settings › API Keys.",
            lastUpdated: Date()
        )
    }

    static func httpFailureStatus(for provider: ProviderType, code: Int, source: String) -> ProviderStatus {
        let isAuth = code == 401 || code == 403
        return ProviderStatus(
            provider: provider,
            state: isAuth ? .expired("Key Rejected") : .error("HTTP \(code)"),
            planName: provider.rawValue,
            authSource: source,
            errorMessage: isAuth ? "\(provider.displayName) rejected the API key." : "\(provider.displayName) returned HTTP \(code).",
            actionSuggestion: isAuth ? "Check the key in Settings › API Keys." : nil,
            lastUpdated: Date()
        )
    }

    static func unreadableStatus(for provider: ProviderType, source: String) -> ProviderStatus {
        ProviderStatus(
            provider: provider,
            state: .error("Unreadable Response"),
            planName: provider.rawValue,
            authSource: source,
            errorMessage: "The \(provider.displayName) response did not match the expected shape.",
            lastUpdated: Date()
        )
    }

    static func offlineStatus(for provider: ProviderType, source: String, error: any Error) -> ProviderStatus {
        ProviderStatus(
            provider: provider,
            state: .error("Offline"),
            planName: provider.rawValue,
            authSource: source,
            errorMessage: error.localizedDescription,
            lastUpdated: Date()
        )
    }
}
