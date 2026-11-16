import Foundation
import OSLog

actor GrokUsageService {
    static let shared = GrokUsageService()

    private let baseURL = "https://management-api.x.ai"

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let key = resolveKey() else {
            return ProviderStatus(
                provider: .grok,
                state: .notFound("Management Key Required"),
                planName: "Not Configured",
                authSource: "Settings",
                actionSuggestion: "Add your xAI Management Key in Settings."
            )
        }

        let validationURL = URL(string: "\(baseURL)/auth/management-keys/validation")!
        let valReq = URLRequest.get(validationURL, timeout: 10.0, bearer: key, userAgent: AppInfo.userAgent)

        do {
            let (data, http) = try await HTTPClient.shared.data(for: valReq)
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let teamId = json["teamId"] as? String ?? (json["team"] as? [String: Any])?["id"] as? String else {
                return ProviderStatus(provider: .grok, state: .error("Validation Failed"), planName: "xAI Grok")
            }

            let balanceURL = URL(string: "\(baseURL)/v1/billing/teams/\(teamId)/prepaid/balance")!
            let balReq = URLRequest.get(balanceURL, timeout: 10.0, bearer: key, userAgent: AppInfo.userAgent)

            let (bData, bHttp) = try await HTTPClient.shared.data(for: balReq)
            guard bHttp.statusCode == 200,
                  let bJson = try? JSONSerialization.jsonObject(with: bData) as? [String: Any] else {
                return ProviderStatus(provider: .grok, state: .error("Balance Fetch Failed"), planName: "xAI Grok")
            }

            let balanceVal = (bJson["balance"] as? NSNumber)?.doubleValue ?? 0.0
            let providerBalance = ProviderBalance(
                amount: balanceVal,
                currency: "USD",
                lines: [.init(label: "Prepaid Credits", amount: balanceVal)]
            )

            return ProviderStatus(
                provider: .grok,
                state: .healthy,
                planName: "xAI Management",
                authSource: "Management Key",
                balance: providerBalance,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(provider: .grok, state: .error(error.localizedDescription), planName: "xAI Grok")
        }
    }

    private func resolveKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["XAI_MANAGEMENT_KEY"], !env.isEmpty {
            return env
        }
        return Keychain.read(service: "com.joaooliveiratech.monohub.grok", account: "default")?.secret
    }
}
