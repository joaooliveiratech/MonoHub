import AppKit
import Foundation
import SwiftUI

nonisolated enum ProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude = "Anthropic Claude"
    case antigravity = "Google Antigravity"
    case codex = "OpenAI Codex"
    case copilot = "GitHub Copilot"
    case cursor = "Cursor"
    case openrouter = "OpenRouter"
    case grok = "xAI Grok"
    case supergrok = "SuperGrok"
    case commandcode = "Command Code"
    case nous = "Nous Research"
    case anthropicApi = "Anthropic Console API"
    case deepseek = "DeepSeek"
    case kimi = "Moonshot Kimi"
    case zai = "Z.ai GLM"
    case deepinfra = "DeepInfra"
    case minimax = "MiniMax"
    case ollama = "Ollama Cloud"
    case kilo = "Kilo"
    case novita = "Novita"
    case moonshot = "Moonshot AI"
    case orcarouter = "OrcaRouter"
    case modelstudio = "Alibaba Model Studio"
    case opencodeGo = "OpenCode Go"
    case kiro = "Kiro CLI"

    var id: String {
        switch self {
        case .claude: "claude"
        case .antigravity: "antigravity"
        case .codex: "codex"
        case .copilot: "copilot"
        case .cursor: "cursor"
        case .openrouter: "openrouter"
        case .grok: "grok"
        case .supergrok: "supergrok"
        case .commandcode: "commandcode"
        case .nous: "nous"
        case .anthropicApi: "anthropicApi"
        case .deepseek: "deepseek"
        case .kimi: "kimi"
        case .zai: "zai"
        case .deepinfra: "deepinfra"
        case .minimax: "minimax"
        case .ollama: "ollama"
        case .kilo: "kilo"
        case .novita: "novita"
        case .moonshot: "moonshot"
        case .orcarouter: "orcarouter"
        case .modelstudio: "modelstudio"
        case .opencodeGo: "opencodeGo"
        case .kiro: "kiro"
        }
    }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .cursor: "Cursor"
        case .openrouter: "OpenRouter"
        case .grok: "Grok"
        case .supergrok: "SuperGrok"
        case .commandcode: "Command Code"
        case .nous: "Nous"
        case .anthropicApi: "Anthropic API"
        case .deepseek: "DeepSeek"
        case .kimi: "Kimi"
        case .zai: "GLM"
        case .deepinfra: "DeepInfra"
        case .minimax: "MiniMax"
        case .ollama: "Ollama"
        case .kilo: "Kilo"
        case .novita: "Novita"
        case .moonshot: "Moonshot"
        case .orcarouter: "OrcaRouter"
        case .modelstudio: "ModelStudio"
        case .opencodeGo: "OpenCode"
        case .kiro: "Kiro"
        }
    }

    var shortCode: String {
        switch self {
        case .claude: "cld"
        case .antigravity: "agy"
        case .codex: "cod"
        case .copilot: "cop"
        case .cursor: "csr"
        case .openrouter: "opr"
        case .grok: "grk"
        case .supergrok: "sgr"
        case .commandcode: "cmd"
        case .nous: "nos"
        case .anthropicApi: "ant"
        case .deepseek: "dsk"
        case .kimi: "kmi"
        case .zai: "glm"
        case .deepinfra: "din"
        case .minimax: "mmx"
        case .ollama: "olm"
        case .kilo: "klo"
        case .novita: "nov"
        case .moonshot: "mst"
        case .orcarouter: "orc"
        case .modelstudio: "bld"
        case .opencodeGo: "ocg"
        case .kiro: "kro"
        }
    }

    var usesAPIKey: Bool {
        switch self {
        case .claude, .antigravity, .codex, .copilot, .cursor, .supergrok, .commandcode, .modelstudio, .kiro:
            false
        case .openrouter, .grok, .nous, .anthropicApi, .deepseek, .kimi, .zai, .deepinfra, .minimax, .ollama, .kilo, .novita, .moonshot, .orcarouter, .opencodeGo:
            true
        }
    }

    var terminalCommand: String? {
        switch self {
        case .claude: "claude"
        case .antigravity: "agy"
        case .codex: "codex"
        case .copilot: "gh"
        case .cursor: "cursor"
        case .supergrok: "grok"
        case .commandcode: "commandcode"
        case .kimi: "kimi"
        case .modelstudio: "bl"
        case .kiro: "kiro-cli"
        case .ollama: "ollama"
        default: nil
        }
    }

    var loginCommand: String? {
        switch self {
        case .claude: "claude"
        case .antigravity: "agy"
        case .codex: "codex login"
        case .copilot: "gh auth login --web"
        case .cursor: "cursor"
        case .supergrok: "grok login"
        case .commandcode: "commandcode"
        case .kimi: "kimi login"
        case .modelstudio: "bl auth login --console"
        case .kiro: "kiro-cli login"
        default: nil
        }
    }

    @MainActor
    var brandIcon: NSImage {
        switch self {
        case .claude: OfficialBrandIcons.claude
        case .antigravity: OfficialBrandIcons.antigravity
        case .codex: OfficialBrandIcons.codex
        case .copilot: OfficialBrandIcons.copilot
        case .cursor: OfficialBrandIcons.cursor
        case .openrouter: OfficialBrandIcons.openrouter
        case .grok: OfficialBrandIcons.grok
        case .supergrok: OfficialBrandIcons.supergrok
        case .commandcode: OfficialBrandIcons.commandcode
        case .nous: OfficialBrandIcons.nous
        case .anthropicApi: OfficialBrandIcons.anthropicApi
        case .deepseek: OfficialBrandIcons.deepseek
        case .kimi: OfficialBrandIcons.kimi
        case .zai: OfficialBrandIcons.zai
        case .deepinfra: OfficialBrandIcons.deepinfra
        case .minimax: OfficialBrandIcons.minimax
        case .ollama: OfficialBrandIcons.ollama
        case .kilo: OfficialBrandIcons.kilo
        case .novita: OfficialBrandIcons.novita
        case .moonshot: OfficialBrandIcons.moonshot
        case .orcarouter: OfficialBrandIcons.orcarouter
        case .modelstudio: OfficialBrandIcons.modelstudio
        case .opencodeGo: OfficialBrandIcons.opencodeGo
        case .kiro: OfficialBrandIcons.kiro
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .antigravity: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .codex: Color(red: 0.06, green: 0.64, blue: 0.50)
        case .copilot: Color(red: 0.15, green: 0.65, blue: 0.95)
        case .cursor: Color(red: 0.55, green: 0.25, blue: 0.90)
        case .openrouter: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .grok: Color(red: 0.85, green: 0.85, blue: 0.85)
        case .supergrok: Color(red: 0.95, green: 0.70, blue: 0.20)
        case .commandcode: Color(red: 0.10, green: 0.80, blue: 0.60)
        case .nous: Color(red: 0.90, green: 0.30, blue: 0.40)
        case .anthropicApi: Color(red: 0.80, green: 0.40, blue: 0.30)
        case .deepseek: Color(red: 0.30, green: 0.42, blue: 1.00)
        case .kimi: Color(red: 0.55, green: 0.40, blue: 0.95)
        case .zai: Color(red: 0.20, green: 0.60, blue: 0.86)
        case .deepinfra: Color(red: 0.20, green: 0.55, blue: 0.85)
        case .minimax: Color(red: 0.85, green: 0.30, blue: 0.70)
        case .ollama: Color(red: 0.90, green: 0.90, blue: 0.90)
        case .kilo: Color(red: 0.40, green: 0.70, blue: 0.30)
        case .novita: Color(red: 0.30, green: 0.80, blue: 0.85)
        case .moonshot: Color(red: 0.60, green: 0.45, blue: 0.95)
        case .orcarouter: Color(red: 0.25, green: 0.65, blue: 0.75)
        case .modelstudio: Color(red: 0.95, green: 0.50, blue: 0.15)
        case .opencodeGo: Color(red: 0.10, green: 0.70, blue: 0.50)
        case .kiro: Color(red: 0.85, green: 0.55, blue: 0.20)
        }
    }
}

nonisolated enum ProviderState: Equatable, Sendable {
    case idle
    case loading
    case healthy
    case warning(String)
    case expired(String)
    case error(String)
    case notFound(String)

    var isError: Bool {
        switch self {
        case .expired, .error, .notFound: true
        default: false
        }
    }

    var statusBadgeTitle: String {
        switch self {
        case .idle: "Waiting"
        case .loading: "Updating"
        case .healthy: "Live"
        case .warning(let reason): reason
        case .expired(let reason): reason.isEmpty ? "Expired" : reason
        case .error(let reason): reason.isEmpty ? "Error" : reason
        case .notFound(let reason): reason.isEmpty ? "Not Connected" : reason
        }
    }

    var statusSymbol: String {
        switch self {
        case .idle, .loading: "clock"
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .expired: "key.slash"
        case .error: "xmark.octagon.fill"
        case .notFound: "link.badge.plus"
        }
    }

    var statusBadgeColor: Color {
        switch self {
        case .idle, .loading, .notFound: .secondary
        case .healthy: .green
        case .warning: .orange
        case .expired, .error: .red
        }
    }
}

nonisolated struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
    let resetAfterSeconds: Int64?
    let limitWindowSeconds: Int64?
    let includedModels: String?

    init(
        id: String? = nil,
        name: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        resetAfterSeconds: Int64? = nil,
        limitWindowSeconds: Int64? = nil,
        includedModels: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.usedPercent = usedPercent.clamped(to: 0.0...100.0)
        self.resetsAt = resetsAt
        self.resetAfterSeconds = resetAfterSeconds
        self.limitWindowSeconds = limitWindowSeconds
        self.includedModels = includedModels
    }

    var effectiveUsedPercent: Double {
        if let resetsAt, resetsAt <= Date() { return 0.0 }
        return usedPercent
    }

    var isSession: Bool {
        if let limitWindowSeconds { return limitWindowSeconds <= 6 * 3600 }
        return name.localizedCaseInsensitiveContains("session")
    }

    func formattedReset(now: Date = Date()) -> String {
        if let resetsAt {
            let remaining = resetsAt.timeIntervalSince(now)
            guard remaining > 0 else { return "Renewing now" }

            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60

            if hours >= 24 {
                let day = resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                return "Resets in \(hours / 24)d \(hours % 24)h · \(day)"
            }
            let clock = resetsAt.formatted(date: .omitted, time: .shortened)
            return hours > 0
                ? "Resets in \(hours)h \(minutes)m · \(clock)"
                : "Resets in \(max(1, minutes))m · \(clock)"
        }

        if let resetAfterSeconds, resetAfterSeconds > 0 {
            let hours = resetAfterSeconds / 3600
            let minutes = (resetAfterSeconds % 3600) / 60
            return hours > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(max(1, minutes))m"
        }

        return "Continuous reset"
    }

    var pacing: WindowPacing? {
        WindowPacing.calculate(
            usedPercent: effectiveUsedPercent,
            resetsAt: resetsAt,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}

nonisolated struct BankedCredit: Identifiable, Equatable, Sendable, Codable {
    var id: String { "\(amount)_\(expiresAt?.timeIntervalSince1970 ?? 0)_\(label)" }
    let amount: Double
    let expiresAt: Date?
    let label: String

    init(amount: Double, expiresAt: Date? = nil, label: String = "Banked Reset Credit") {
        self.amount = amount
        self.expiresAt = expiresAt
        self.label = label
    }

    var isExpiringSoon: Bool {
        guard let expiresAt else { return false }
        let remaining = expiresAt.timeIntervalSince(Date())
        return remaining > 0 && remaining <= 48 * 3600
    }
}

nonisolated struct ProviderBalance: Equatable, Sendable, Codable {
    struct Line: Equatable, Sendable, Codable {
        let label: String
        let amount: Double
    }

    let amount: Double
    let currency: String
    let lines: [Line]

    var formatted: String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    var compact: String {
        let digits = abs(amount) >= 100 ? 0 : 2
        return amount.formatted(.currency(code: currency).precision(.fractionLength(digits)))
    }

    func formatted(_ value: Double) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }
}

nonisolated struct ProviderStatus: Identifiable, Equatable, Sendable {
    var id: String { provider.id }
    let provider: ProviderType
    var state: ProviderState
    var planName: String
    var authSource: String
    var windows: [QuotaWindow]
    var balance: ProviderBalance?
    var bankedCredits: [BankedCredit]
    var tankLimit: Double?
    var errorMessage: String?
    var actionSuggestion: String?
    var accountDetail: String?
    var lastUpdated: Date?

    init(
        provider: ProviderType,
        state: ProviderState = .idle,
        planName: String = "Unknown",
        authSource: String = "Automatic",
        windows: [QuotaWindow] = [],
        balance: ProviderBalance? = nil,
        bankedCredits: [BankedCredit] = [],
        tankLimit: Double? = nil,
        errorMessage: String? = nil,
        actionSuggestion: String? = nil,
        accountDetail: String? = nil,
        lastUpdated: Date? = nil
    ) {
        self.provider = provider
        self.state = state
        self.planName = planName
        self.authSource = authSource
        self.windows = windows
        self.balance = balance
        self.bankedCredits = bankedCredits
        self.tankLimit = tankLimit
        self.errorMessage = errorMessage
        self.actionSuggestion = actionSuggestion
        self.accountDetail = accountDetail
        self.lastUpdated = lastUpdated
    }

    var hasReading: Bool {
        !windows.isEmpty || balance != nil
    }

    var primaryUsagePercent: Double? {
        guard !windows.isEmpty else { return nil }
        let peak = peakUsagePercent
        if peak >= 85.0 {
            return peak
        }
        let sessionMax = windows.filter(\.isSession).map(\.effectiveUsedPercent).max()
        if provider == .antigravity, (sessionMax ?? 0) <= 1.0, peak > 1.0 {
            return peak
        }
        return sessionMax ?? windows.first?.effectiveUsedPercent
    }

    var peakUsagePercent: Double {
        windows.map(\.effectiveUsedPercent).max() ?? 0.0
    }

    var headlineValue: String? {
        if let percent = primaryUsagePercent { return "\(Int(percent.rounded()))%" }
        return balance?.compact
    }

    static func initial(for provider: ProviderType) -> ProviderStatus {
        ProviderStatus(provider: provider, state: .idle, planName: "Checking…", authSource: "Local")
    }

    static func nearLimitState(peak: Double) -> ProviderState {
        peak >= 90.0 ? .warning("Near Limit") : .healthy
    }
}

nonisolated extension Color {
    static func usageColor(for percent: Double) -> Color {
        switch percent {
        case 90.0...: .red
        case 70.0..<90.0: .orange
        default: .green
        }
    }
}

nonisolated enum ISO8601 {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = (try? fractional.parse(string)) ?? (try? whole.parse(string)) {
            return date
        }
        return trimmingExtraFractionDigits(string).flatMap { try? fractional.parse($0) }
    }

    private static func trimmingExtraFractionDigits(_ string: String) -> String? {
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let fraction = string[string.index(after: dot)...].prefix { $0.isNumber }
        guard fraction.count > 3 else { return nil }
        let suffix = string[fraction.endIndex...]
        return String(string[...dot]) + fraction.prefix(3) + suffix
    }
}

nonisolated enum FlexibleNumber {
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}
