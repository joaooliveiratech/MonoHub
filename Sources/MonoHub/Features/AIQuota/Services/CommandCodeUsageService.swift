import Foundation
import OSLog

actor CommandCodeUsageService {
    static let shared = CommandCodeUsageService()

    private let creditsURL = URL(string: "https://api.commandcode.ai/alpha/billing/credits")!

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let token = resolveToken() else {
            return ProviderStatus(
                provider: .commandcode,
                state: .notFound("Command Code Login Required"),
                planName: "Not Connected",
                authSource: "Local CLI",
                actionSuggestion: "Run `commandcode` or sign in to Command Code CLI."
            )
        }

        let request = URLRequest.get(creditsURL, timeout: 10.0, bearer: token, userAgent: AppInfo.userAgent)

        do {
            let (data, http) = try await HTTPClient.shared.data(for: request)

            if http.statusCode == 401 || http.statusCode == 403 {
                return ProviderStatus(
                    provider: .commandcode,
                    state: .expired("Token Expired"),
                    planName: "Command Code",
                    actionSuggestion: "Run `commandcode` in terminal to refresh your session."
                )
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderStatus(provider: .commandcode, state: .error("HTTP \(http.statusCode)"), planName: "Command Code")
            }

            var windows: [QuotaWindow] = []
            if let fiveHour = json["fiveHour"] as? [String: Any],
               let spent = (fiveHour["spent"] as? NSNumber)?.doubleValue,
               let cap = (fiveHour["cap"] as? NSNumber)?.doubleValue, cap > 0 {
                let pct = (spent / cap) * 100.0
                windows.append(QuotaWindow(name: "5-Hour Window", usedPercent: pct))
            }

            if let weekly = json["weekly"] as? [String: Any],
               let spent = (weekly["spent"] as? NSNumber)?.doubleValue,
               let cap = (weekly["cap"] as? NSNumber)?.doubleValue, cap > 0 {
                let pct = (spent / cap) * 100.0
                windows.append(QuotaWindow(name: "Weekly Window", usedPercent: pct))
            }

            let peak = windows.map(\.usedPercent).max() ?? 0.0
            return ProviderStatus(
                provider: .commandcode,
                state: ProviderStatus.nearLimitState(peak: peak),
                planName: "Command Code",
                authSource: "Local CLI",
                windows: windows,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(provider: .commandcode, state: .error(error.localizedDescription), planName: "Command Code")
        }
    }

    private func resolveToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["COMMANDCODE_API_KEY"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".commandcode/auth.json"),
            home.appendingPathComponent(".pi/agent/auth.json")
        ]
        for url in paths {
            if let data = try? Data(contentsOf: url),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let token = (json["accessToken"] as? String) ?? (json["token"] as? String), !token.isEmpty {
                return token
            }
        }
        return Keychain.read(service: "com.joaooliveiratech.monohub.commandcode", account: "default")?.secret
    }
}
