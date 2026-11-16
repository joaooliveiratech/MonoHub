import Foundation
import OSLog

actor CopilotUsageService {
    static let shared = CopilotUsageService()

    private let rateLimitURL = URL(string: "https://api.github.com/rate_limit")!
    private let userURL = URL(string: "https://api.github.com/user")!

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let token = resolveToken() else {
            return ProviderStatus(
                provider: .copilot,
                state: .notFound("GitHub Token Required"),
                planName: "Not Configured",
                authSource: "Settings",
                actionSuggestion: "Set your GITHUB_COPILOT_TOKEN in Settings > API Keys."
            )
        }

        var userRequest = URLRequest.get(userURL, timeout: 10.0, bearer: token, userAgent: AppInfo.userAgent)
        userRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        userRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (userData, userHttp) = try await HTTPClient.shared.data(for: userRequest)

            if userHttp.statusCode == 401 || userHttp.statusCode == 403 {
                return ProviderStatus(
                    provider: .copilot,
                    state: .expired("Token Expired"),
                    planName: "GitHub",
                    authSource: "Settings",
                    actionSuggestion: "Your GitHub token is invalid or expired. Update it in Settings."
                )
            }

            guard userHttp.statusCode == 200 else {
                return ProviderStatus(
                    provider: .copilot,
                    state: .error("HTTP \(userHttp.statusCode)"),
                    planName: "GitHub",
                    authSource: "Settings"
                )
            }

            let userJson = (try? JSONSerialization.jsonObject(with: userData)) as? [String: Any]
            let planObj = userJson?["plan"] as? [String: Any]
            let planNameRaw = (planObj?["name"] as? String)?.capitalized ?? "Developer"
            let planName = "GitHub \(planNameRaw)"

            var rateRequest = URLRequest.get(rateLimitURL, timeout: 10.0, bearer: token, userAgent: AppInfo.userAgent)
            rateRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            rateRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (rateData, rateHttp) = try await HTTPClient.shared.data(for: rateRequest)
            guard rateHttp.statusCode == 200,
                  let rateJson = (try? JSONSerialization.jsonObject(with: rateData)) as? [String: Any],
                  let resources = rateJson["resources"] as? [String: Any] else {
                return ProviderStatus(
                    provider: .copilot,
                    state: .healthy,
                    planName: planName,
                    authSource: "API Token",
                    lastUpdated: Date()
                )
            }

            var windows: [QuotaWindow] = []

            if let core = resources["core"] as? [String: Any] {
                let limit = (core["limit"] as? NSNumber)?.doubleValue ?? 5000.0
                let remaining = (core["remaining"] as? NSNumber)?.doubleValue ?? limit
                let resetEpoch = (core["reset"] as? NSNumber)?.doubleValue ?? 0.0
                let resetsAt = resetEpoch > 0 ? Date(timeIntervalSince1970: resetEpoch) : nil
                let used = max(0.0, limit - remaining)
                let pct = limit > 0 ? (used / limit) * 100.0 : 0.0
                windows.append(QuotaWindow(name: "REST API Quota", usedPercent: pct, resetsAt: resetsAt))
            }

            if let search = resources["search"] as? [String: Any] {
                let limit = (search["limit"] as? NSNumber)?.doubleValue ?? 30.0
                let remaining = (search["remaining"] as? NSNumber)?.doubleValue ?? limit
                let resetEpoch = (search["reset"] as? NSNumber)?.doubleValue ?? 0.0
                let resetsAt = resetEpoch > 0 ? Date(timeIntervalSince1970: resetEpoch) : nil
                let used = max(0.0, limit - remaining)
                let pct = limit > 0 ? (used / limit) * 100.0 : 0.0
                windows.append(QuotaWindow(name: "Search API Quota", usedPercent: pct, resetsAt: resetsAt))
            }

            let peak = windows.map(\.usedPercent).max() ?? 0.0
            return ProviderStatus(
                provider: .copilot,
                state: ProviderStatus.nearLimitState(peak: peak),
                planName: planName,
                authSource: "GitHub API",
                windows: windows,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(
                provider: .copilot,
                state: .error(error.localizedDescription),
                planName: "GitHub",
                authSource: "Settings"
            )
        }
    }

    private func resolveToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["GITHUB_COPILOT_TOKEN"], !env.isEmpty {
            return env
        }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !env.isEmpty {
            return env
        }
        if let item = Keychain.read(service: "com.joaooliveiratech.monohub.copilot", account: "default"), !item.secret.isEmpty {
            return item.secret
        }
        return nil
    }
}
