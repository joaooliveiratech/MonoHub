import Foundation

nonisolated struct QuotaSnapshotDTO: Codable, Sendable {
    struct WindowDTO: Codable, Sendable {
        let id: String?
        let name: String
        let usedPercent: Double
        let resetsAt: Date?
        let resetAfterSeconds: Int64?
        let limitWindowSeconds: Int64?
        let includedModels: String?
    }

    let providerId: String
    let planName: String
    let authSource: String
    let windows: [WindowDTO]
    let balance: ProviderBalance?
    let accountDetail: String?
    let lastUpdated: Date?

    func toStatus() -> ProviderStatus? {
        guard let provider = ProviderType.allCases.first(where: { $0.id == providerId }) else { return nil }
        let quotaWindows = windows.map {
            QuotaWindow(
                id: $0.id,
                name: $0.name,
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                resetAfterSeconds: $0.resetAfterSeconds,
                limitWindowSeconds: $0.limitWindowSeconds,
                includedModels: $0.includedModels
            )
        }
        return ProviderStatus(
            provider: provider,
            state: .warning("Cached"),
            planName: planName,
            authSource: authSource,
            windows: quotaWindows,
            balance: balance,
            errorMessage: nil,
            actionSuggestion: nil,
            accountDetail: accountDetail?.contains("@") == true ? nil : accountDetail,
            lastUpdated: lastUpdated
        )
    }

    static func from(status: ProviderStatus) -> QuotaSnapshotDTO {
        let windowDTOs = status.windows.map {
            WindowDTO(
                id: $0.id,
                name: $0.name,
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                resetAfterSeconds: $0.resetAfterSeconds,
                limitWindowSeconds: $0.limitWindowSeconds,
                includedModels: $0.includedModels
            )
        }
        return QuotaSnapshotDTO(
            providerId: status.provider.id,
            planName: status.planName,
            authSource: status.authSource,
            windows: windowDTOs,
            balance: status.balance,
            accountDetail: status.accountDetail?.contains("@") == true ? nil : status.accountDetail,
            lastUpdated: status.lastUpdated
        )
    }
}

actor QuotaSnapshotStore {
    static let shared = QuotaSnapshotStore()

    private static let directoryName = "MonoAiBar"
    private static let fileName = "quota_snapshots.json"

    private static var fileURL: URL {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName, isDirectory: true)
        return baseDir.appendingPathComponent(fileName)
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated static func loadSnapshotsSync() -> [ProviderType: ProviderStatus] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dtos = try? decoder.decode([QuotaSnapshotDTO].self, from: data) else {
            return [:]
        }

        var results: [ProviderType: ProviderStatus] = [:]
        for dto in dtos {
            if let status = dto.toStatus() {
                results[status.provider] = status
            }
        }
        return results
    }

    func save(statuses: [ProviderType: ProviderStatus]) {
        let activeSnapshots = statuses.values
            .filter(\.hasReading)
            .map { QuotaSnapshotDTO.from(status: $0) }
        guard !activeSnapshots.isEmpty else { return }

        let url = Self.fileURL
        let directory = url.deletingLastPathComponent()

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        guard let data = try? encoder.encode(activeSnapshots) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }
}
