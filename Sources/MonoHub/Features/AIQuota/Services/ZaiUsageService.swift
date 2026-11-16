import Foundation
import OSLog

actor ZaiUsageService {
    static let shared = ZaiUsageService()

    private static let endpoints = [
        URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
        URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    ]

    private let http = HTTPClient(timeout: 6.0, resourceTimeout: 8.0)
    private var preferredEndpoint = 0

    func fetchUsage() async -> ProviderStatus {
        guard let key = await APIKeyLookup.key(for: .zai, environment: ["ZAI_API_KEY", "Z_AI_API_KEY", "GLM_API_KEY"]) else {
            return APIKeyLookup.missingKeyStatus(for: .zai, planName: "GLM Coding Plan")
        }

        var lastCode = 0
        let order = [preferredEndpoint] + Self.endpoints.indices.filter { $0 != preferredEndpoint }
        for index in order {
            var request = URLRequest.get(Self.endpoints[index], timeout: 6.0)
            request.setBearer(key.value)
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await http.send(request)
                lastCode = response.statusCode
                guard response.statusCode == 200, let status = decode(data, source: key.source) else { continue }
                preferredEndpoint = index
                return status
            } catch {
                Log.quota.debug("z.ai quota request failed: \(error.localizedDescription, privacy: .public)")
                if index == order.last {
                    return APIKeyLookup.offlineStatus(for: .zai, source: key.source, error: error)
                }
            }
        }

        return lastCode == 200
            ? APIKeyLookup.unreadableStatus(for: .zai, source: key.source)
            : APIKeyLookup.httpFailureStatus(for: .zai, code: lastCode, source: key.source)
    }

    private func decode(_ data: Data, source: String) -> ProviderStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool != false,
              let payload = root["data"] as? [String: Any],
              let limits = payload["limits"] as? [[String: Any]] else { return nil }

        let windows = limits.compactMap(Self.window(from:))
            .sorted { ($0.limitWindowSeconds ?? .max) < ($1.limitWindowSeconds ?? .max) }
        guard !windows.isEmpty else { return nil }

        let plan = ["planName", "plan", "plan_type", "packageName", "level"]
            .lazy
            .compactMap { payload[$0] as? String }
            .first { !$0.isEmpty }

        var status = ProviderStatus(
            provider: .zai,
            state: .healthy,
            planName: plan.map { "GLM Coding \($0)" } ?? "GLM Coding Plan",
            authSource: source,
            windows: windows,
            lastUpdated: Date()
        )
        status.state = ProviderStatus.nearLimitState(peak: status.peakUsagePercent)
        return status
    }

    private static func window(from limit: [String: Any]) -> QuotaWindow? {
        guard let type = limit["type"] as? String,
              ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type),
              let unit = FlexibleNumber.double(limit["unit"]).map(Int.init),
              let number = FlexibleNumber.double(limit["number"]),
              var percent = FlexibleNumber.double(limit["percentage"]) else { return nil }

        if let total = FlexibleNumber.double(limit["usage"]), total > 0,
           let used = FlexibleNumber.double(limit["currentValue"]) {
            percent = used / total * 100
        }

        let resetsAt = FlexibleNumber.double(limit["nextResetTime"]).map { Date(timeIntervalSince1970: $0 / 1000) }

        if type == "TIME_LIMIT" {
            return QuotaWindow(name: "MCP · Monthly", usedPercent: percent, resetsAt: resetsAt, limitWindowSeconds: 30 * 86_400)
        }

        let minutesPerUnit: Double? = switch unit {
        case 1: 1440
        case 3: 60
        case 5: 1
        case 6: 10_080
        default: nil
        }
        guard let minutesPerUnit else { return nil }
        let seconds = Int64(number * minutesPerUnit * 60)

        let name: String = switch seconds {
        case ...(6 * 3600): "Session"
        case (6 * 86_400)..<(8 * 86_400): "Weekly"
        case (28 * 86_400)...: "Monthly"
        default: "\(seconds / 3600)-Hour Window"
        }
        return QuotaWindow(name: name, usedPercent: percent, resetsAt: resetsAt, limitWindowSeconds: seconds)
    }
}
