import Foundation
import OSLog

actor AnthropicAdminUsageService {
    static let shared = AnthropicAdminUsageService()

    private let url = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let key = resolveKey() else {
            return ProviderStatus(
                provider: .anthropicApi,
                state: .notFound("Admin Key Required"),
                planName: "Not Configured",
                authSource: "Settings",
                actionSuggestion: "Enter an ANTHROPIC_ADMIN_KEY in Settings."
            )
        }

        var request = URLRequest.get(url, timeout: 10.0, userAgent: AppInfo.userAgent)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, http) = try await HTTPClient.shared.data(for: request)

            if http.statusCode == 401 || http.statusCode == 403 {
                return ProviderStatus(
                    provider: .anthropicApi,
                    state: .expired("Invalid Admin Key"),
                    planName: "Console Admin",
                    actionSuggestion: "Verify your Anthropic Admin Key in Settings."
                )
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["data"] as? [[String: Any]] else {
                return ProviderStatus(provider: .anthropicApi, state: .error("HTTP \(http.statusCode)"), planName: "Console Admin")
            }

            var monthSpend: Double = 0.0
            for item in results {
                if let amount = (item["amount"] as? NSNumber)?.doubleValue {
                    monthSpend += amount
                }
            }

            let providerBalance = ProviderBalance(
                amount: monthSpend,
                currency: "USD",
                lines: [.init(label: "Month-to-Date Spend", amount: monthSpend)]
            )

            return ProviderStatus(
                provider: .anthropicApi,
                state: .healthy,
                planName: "Organization Admin",
                authSource: "Admin Key",
                balance: providerBalance,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(provider: .anthropicApi, state: .error(error.localizedDescription), planName: "Console Admin")
        }
    }

    private func resolveKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_ADMIN_KEY"], !env.isEmpty {
            return env
        }
        return Keychain.read(service: "com.joaooliveiratech.monohub.anthropicApi", account: "default")?.secret
            ?? Keychain.read(service: "com.joaooliveiratech.monohub.anthropic_api", account: "default")?.secret
    }
}
