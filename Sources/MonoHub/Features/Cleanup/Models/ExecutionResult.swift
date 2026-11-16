import Foundation

nonisolated struct ExecutionResult: Sendable {
    let success: Bool
    let itemsCount: Int
    let bytesFreed: Int64
    let errors: [String]

    var itemsRemoved: Int { itemsCount }
    var itemsPurged: Int { itemsCount }

    init(success: Bool, itemsCount: Int, bytesFreed: Int64, errors: [String] = []) {
        self.success = success
        self.itemsCount = itemsCount
        self.bytesFreed = bytesFreed
        self.errors = errors
    }

    init(success: Bool, itemsRemoved: Int, bytesFreed: Int64, errors: [String] = []) {
        self.init(success: success, itemsCount: itemsRemoved, bytesFreed: bytesFreed, errors: errors)
    }

    init(success: Bool, itemsPurged: Int, bytesFreed: Int64, errors: [String] = []) {
        self.init(success: success, itemsCount: itemsPurged, bytesFreed: bytesFreed, errors: errors)
    }

    static let maximumListedErrors = 8

    var summaryTitle: String {
        success ? localized("Completed") : (itemsCount > 0 ? localized("Completed with warnings") : localized("Nothing was removed"))
    }

    var summaryMessage: String {
        let freed = itemsCount == 1
            ? localized("1 item removed · %@ freed.", Formatting.bytes(bytesFreed))
            : localized("%d items removed · %@ freed.", itemsCount, Formatting.bytes(bytesFreed))
        guard !errors.isEmpty else { return freed }
        let listed = errors.prefix(Self.maximumListedErrors).joined(separator: "\n")
        let remaining = errors.count - Self.maximumListedErrors
        let suffix = remaining > 0
            ? (remaining == 1 ? "\n" + localized("… and 1 more warning.") : "\n" + localized("… and %d more warnings.", remaining))
            : ""
        return "\(freed)\n\n\(listed)\(suffix)"
    }
}
