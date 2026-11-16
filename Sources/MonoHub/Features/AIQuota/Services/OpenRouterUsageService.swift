import Foundation
import OSLog

actor OpenRouterUsageService {
    static let shared = OpenRouterUsageService()

    private let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let apiKey = resolveKey() else {
            return ProviderStatus(
                provider: .openrouter,
                state: .notFound("API Key Required"),
                planName: "Not Configured",
                authSource: "Settings",
                actionSuggestion: "Enter your OPENROUTER_API_KEY in Settings."
            )
        }

        let request = URLRequest.get(creditsURL, timeout: 10.0, bearer: apiKey, userAgent: AppInfo.userAgent)

        do {
            let (data, http) = try await HTTPClient.shared.data(for: request)

            if http.statusCode == 401 || http.statusCode == 403 {
                return ProviderStatus(
                    provider: .openrouter,
                    state: .expired("Invalid API Key"),
                    planName: "OpenRouter",
                    actionSuggestion: "Verify your OpenRouter API key in Settings."
                )
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else {
                return ProviderStatus(provider: .openrouter, state: .error("HTTP \(http.statusCode)"), planName: "OpenRouter")
            }

            let totalCredits = (dataObj["total_credits"] as? NSNumber)?.doubleValue ?? 0.0
            let totalUsage = (dataObj["total_usage"] as? NSNumber)?.doubleValue ?? 0.0
            let balance = max(0.0, totalCredits - totalUsage)

            var windows: [QuotaWindow] = []
            if totalCredits > 0 {
                let usedPct = min(max((totalUsage / totalCredits) * 100.0, 0.0), 100.0)
                windows.append(QuotaWindow(name: "Credits Pool", usedPercent: usedPct))
            }

            let providerBalance = ProviderBalance(
                amount: balance,
                currency: "USD",
                lines: [
                    .init(label: "Total Purchased", amount: totalCredits),
                    .init(label: "Total Spent", amount: totalUsage)
                ]
            )

            return ProviderStatus(
                provider: .openrouter,
                state: .healthy,
                planName: totalCredits > 0 ? "Credits Account" : "Pay-As-You-Go",
                authSource: "API Key",
                windows: windows,
                balance: providerBalance,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(provider: .openrouter, state: .error(error.localizedDescription), planName: "OpenRouter")
        }
    }

    private func resolveKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !env.isEmpty {
            return env
        }
        return Keychain.read(service: "com.joaooliveiratech.monohub.openrouter", account: "default")?.secret
    }
}
