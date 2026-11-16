import Foundation
import OSLog

actor CursorUsageService {
    static let shared = CursorUsageService()

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    private let url = URL(string: "https://cursor.com/api/usage-summary")!

    private init() {}

    func fetchUsage() async -> ProviderStatus {
        guard let token = await resolveToken() else {
            return ProviderStatus(
                provider: .cursor,
                state: .notFound("Cursor Login Required"),
                planName: "Not Connected",
                authSource: "Local Session",
                actionSuggestion: "Sign in to Cursor IDE or add your Cursor token in Settings."
            )
        }

        var request = URLRequest.get(url, timeout: 10.0, bearer: token, userAgent: userAgent)
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")

        do {
            let (data, http) = try await HTTPClient.shared.data(for: request)

            if http.statusCode == 401 || http.statusCode == 403 {
                return ProviderStatus(
                    provider: .cursor,
                    state: .expired("Session Expired"),
                    planName: "Cursor",
                    actionSuggestion: "Open Cursor IDE to renew your session."
                )
            }

            guard http.statusCode == 200 else {
                return ProviderStatus(provider: .cursor, state: .error("HTTP \(http.statusCode)"), planName: "Cursor")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderStatus(provider: .cursor, state: .error("Invalid Response"), planName: "Cursor")
            }

            let plan = (json["membershipType"] as? String)?.capitalized ?? "Cursor Pro"
            var windows: [QuotaWindow] = []

            if let composer = json["numRequests"] as? NSNumber, let maxRequests = json["maxRequestUsage"] as? NSNumber, maxRequests.intValue > 0 {
                let used = (composer.doubleValue / maxRequests.doubleValue) * 100.0
                windows.append(QuotaWindow(name: "Composer / Fast", usedPercent: used))
            } else if let gpt4 = json["gpt4"] as? [String: Any],
                      let num = gpt4["numRequests"] as? NSNumber,
                      let maxReq = gpt4["maxRequestUsage"] as? NSNumber, maxReq.intValue > 0 {
                let used = (num.doubleValue / maxReq.doubleValue) * 100.0
                windows.append(QuotaWindow(name: "Fast Requests", usedPercent: used))
            }

            let peak = windows.map(\.usedPercent).max() ?? 0.0
            return ProviderStatus(
                provider: .cursor,
                state: ProviderStatus.nearLimitState(peak: peak),
                planName: plan,
                authSource: "Cursor Session",
                windows: windows,
                lastUpdated: Date()
            )
        } catch {
            return ProviderStatus(provider: .cursor, state: .error(error.localizedDescription), planName: "Cursor")
        }
    }

    private func resolveToken() async -> String? {
        if let env = ProcessInfo.processInfo.environment["CURSOR_ACCESS_TOKEN"], !env.isEmpty {
            return env
        }
        if let item = Keychain.read(service: "com.joaooliveiratech.monohub.cursor", account: "default"), !item.secret.isEmpty {
            return item.secret
        }

        let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/auth.json")
        if let data = try? Data(contentsOf: authURL),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let token = json["accessToken"] as? String, !token.isEmpty {
            return token
        }

        return nil
    }
}
