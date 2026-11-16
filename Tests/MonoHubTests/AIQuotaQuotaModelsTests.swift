import Foundation
import Testing
@testable import MonoHub

@Suite("Quota Models Tests")
struct QuotaModelsTests {
    @Test("All 24 provider short codes and IDs are unique")
    func testUniqueCodesAndIDs() {
        let allProviders = ProviderType.allCases
        #expect(allProviders.count == 24)

        let ids = Set(allProviders.map(\.id))
        #expect(ids.count == 24)

        let shortCodes = Set(allProviders.map(\.shortCode))
        #expect(shortCodes.count == 24)
    }

    @Test("BankedCredit expiration within 48h detection")
    func testBankedCreditExpiringSoon() {
        let now = Date()
        let expiringIn24h = BankedCredit(amount: 5, expiresAt: now.addingTimeInterval(24 * 3600), label: "Test")
        #expect(expiringIn24h.isExpiringSoon == true)

        let expiringIn72h = BankedCredit(amount: 5, expiresAt: now.addingTimeInterval(72 * 3600), label: "Test")
        #expect(expiringIn72h.isExpiringSoon == false)

        let noExpiry = BankedCredit(amount: 5, expiresAt: nil, label: "Test")
        #expect(noExpiry.isExpiringSoon == false)
    }

    @Test("Near limit state calculation")
    func testNearLimitState() {
        #expect(ProviderStatus.nearLimitState(peak: 40.0) == .healthy)
        #expect(ProviderStatus.nearLimitState(peak: 89.9) == .healthy)
        #expect(ProviderStatus.nearLimitState(peak: 90.0) == .warning("Near Limit"))
        #expect(ProviderStatus.nearLimitState(peak: 100.0) == .warning("Near Limit"))
    }

    @Test("QuotaWindow effectiveUsedPercent clamping")
    func testQuotaWindowClamping() {
        let windowOver = QuotaWindow(name: "Test", usedPercent: 120.0)
        #expect(windowOver.effectiveUsedPercent == 100.0)

        let windowUnder = QuotaWindow(name: "Test", usedPercent: -10.0)
        #expect(windowUnder.effectiveUsedPercent == 0.0)
    }

    @Test("QuotaWindow preserva ID customizado e modelos incluídos (Argon / Gemini / Claude)")
    func testQuotaWindowCustomIdAndModels() {
        let argonWindow = QuotaWindow(
            id: "gemini-argon-wtu-weekly",
            name: "Gemini 4 Argon · Weekly",
            usedPercent: 81.3,
            includedModels: "Gemini 4 Argon (Medium, High, Low)"
        )
        #expect(argonWindow.id == "gemini-argon-wtu-weekly")
        #expect(argonWindow.name == "Gemini 4 Argon · Weekly")
        #expect(argonWindow.includedModels == "Gemini 4 Argon (Medium, High, Low)")

        let geminiWindow = QuotaWindow(
            id: "gemini-weekly",
            name: "Gemini (Flash & Pro) · Weekly",
            usedPercent: 1.2,
            includedModels: "Gemini 3.8 Flash, Gemini Pro"
        )
        #expect(geminiWindow.id == "gemini-weekly")
        #expect(argonWindow.id != geminiWindow.id)
    }

    @Test("Parser de modelos CLI do Antigravity extrai Gemini 4 Argon e categoriza famílias")
    func testAntigravityCLIModelsParser() {
        let sampleOutput = """
        gemini-4-argon-medium     Gemini 4 Argon (Medium)
        gemini-4-argon-high       Gemini 4 Argon (High)
        gemini-4-argon-low        Gemini 4 Argon (Low)
        gemini-3.8-flash-high     Gemini 3.8 Flash (High)
        gemini-3.8-flash-medium   Gemini 3.8 Flash (Medium)
        gemini-3.8-flash-low      Gemini 3.8 Flash (Low)
        claude-opus-5-5-low       Claude Opus 5.5 (Low)
        claude-opus-5-5-medium    Claude Opus 5.5 (Medium)
        claude-opus-5-5-high      Claude Opus 5.5 (High)
        claude-sonnet-5-5-low     Claude Sonnet 5.5 (Low)
        claude-sonnet-5-5-medium  Claude Sonnet 5.5 (Medium)
        claude-sonnet-5-5-high    Claude Sonnet 5.5 (High)
        gpt-oss-120b-medium       GPT-OSS 120B (Medium)
        """

        let models = AntigravityUsageService.parseCLIModels(output: sampleOutput)
        #expect(!models.isEmpty)

        let argon = models.first { $0.displayName == "Gemini 4 Argon" }
        #expect(argon != nil)
        #expect(argon?.isNew == true)
        #expect(argon?.family == "Argon")

        let flash = models.first { $0.displayName == "Gemini 3.8 Flash" }
        #expect(flash != nil)
        #expect(flash?.isNew == false)
        #expect(flash?.family == "Gemini")

        let opus = models.first { $0.displayName == "Claude Opus 5.5" }
        #expect(opus != nil)
        #expect(opus?.family == "Claude")

        let sonnet = models.first { $0.displayName == "Claude Sonnet 5.5" }
        #expect(sonnet != nil)
        #expect(sonnet?.family == "Claude")

        let gpt = models.first { $0.displayName == "GPT-OSS 120B" }
        #expect(gpt != nil)
        #expect(gpt?.family == "Open-Source")
    }

    @Test("LiveActivityCenter não ativa cota de IA se o recurso estiver desativado no FeatureManager")
    @MainActor
    func testAIQuotaDisabledInFeatureManager() {
        let isEnabledBefore = FeatureManager.shared.isEnabled(.aiQuota)
        FeatureManager.shared.setEnabled(.aiQuota, false)

        #expect(FeatureManager.shared.isEnabled(.aiQuota) == false)
        #expect(LiveActivityCenter.isAIQuotaActive() == false)

        FeatureManager.shared.setEnabled(.aiQuota, isEnabledBefore)
    }

    @Test("ClaudeUsageService decodifica payload completo da Anthropic e normaliza jitter de resets_at")
    func testClaudeUsageDecodeAndNormalization() {
        let json = """
        {
          "five_hour": { "utilization": 20.0, "resets_at": "2099-11-07T18:59:59.782461+00:00" },
          "seven_day": { "utilization": 46.0, "resets_at": "2099-11-11T17:00:00.412891+00:00" },
          "seven_day_sonnet": { "utilization": 3.0, "resets_at": "2099-11-09T21:59:59.910000+00:00" },
          "seven_day_opus": null,
          "seven_day_cowork": { "utilization": 12.0, "resets_at": "2099-11-10T12:00:00+00:00" },
          "extra_usage": { "is_enabled": true, "monthly_limit": 2000, "used_credits": 550, "utilization": 27.5 },
          "spend": { "used": 550, "limit": 2000, "percent": 27.5, "enabled": true }
        }
        """.data(using: .utf8)!

        let credential = ClaudeCredential(
            accessToken: "sk-ant-oat01-test",
            refreshToken: nil,
            expiresAtMilliseconds: nil,
            plan: "Claude Max",
            sourceLabel: "Claude Code Keychain",
            accountDetail: "Tier: Default Claude Max 5x",
            rawJSON: nil
        )

        let status = ClaudeUsageService.decodeUsage(json, credential: credential)
        #expect(status.state == .healthy)
        #expect(status.primaryUsagePercent == 20.0)
        #expect(status.peakUsagePercent == 46.0)
        #expect(status.windows.count == 5)
        #expect(status.balance?.amount == 14.5)

        let sessionReset = status.windows.first(where: { $0.name == "Session" })?.resetsAt
        let weeklyReset = status.windows.first(where: { $0.name == "Weekly" })?.resetsAt
        #expect(sessionReset != nil)
        #expect(weeklyReset != nil)
        if let sessionReset {
            #expect(Int(sessionReset.timeIntervalSince1970) % 60 == 0)
        }
        if let weeklyReset {
            #expect(Int(weeklyReset.timeIntervalSince1970) % 60 == 0)
        }
    }

    @Test("ClaudeUsageService decodifica payload real com spend.used como objeto de moeda (amount_minor)")
    func testClaudeUsageDecodeMoneyObjectInSpend() {
        let json = """
        {
          "five_hour": { "utilization": 58.0, "resets_at": "2099-11-08T14:50:00.208168+00:00", "limit_dollars": null },
          "seven_day": { "utilization": 16.0, "resets_at": "2099-11-14T22:00:00.208185+00:00", "limit_dollars": null },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null },
          "limits": [
            { "kind": "session", "group": "session", "percent": 58, "severity": "normal", "resets_at": "2099-11-08T14:50:00.208168+00:00", "is_active": true },
            { "kind": "weekly_all", "group": "weekly", "percent": 16, "severity": "normal", "resets_at": "2099-11-14T22:00:00.208185+00:00", "is_active": false }
          ],
          "spend": {
            "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
            "limit": null,
            "percent": 0,
            "severity": "normal",
            "enabled": false
          }
        }
        """.data(using: .utf8)!

        let credential = ClaudeCredential(
            accessToken: "sk-ant-oat01-test",
            refreshToken: nil,
            expiresAtMilliseconds: nil,
            plan: "Claude Team",
            sourceLabel: "Claude Code Keychain",
            accountDetail: "Tier: Default Raven",
            rawJSON: nil
        )

        let status = ClaudeUsageService.decodeUsage(json, credential: credential)
        #expect(status.state == .healthy)
        #expect(status.primaryUsagePercent == 58.0)
        #expect(status.peakUsagePercent == 58.0)
        #expect(status.windows.count == 2)
        #expect(status.windows.first(where: { $0.name == "Session" })?.usedPercent == 58.0)
        #expect(status.windows.first(where: { $0.name == "Weekly" })?.usedPercent == 16.0)
    }

    @Test("CredentialStore.decodeSecurityOutput decodifica saída hexadecimal do comando security")
    func testDecodeSecurityHexOutput() {
        let original = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc"}}"#
        let hex = original.utf8.map { String(format: "%02x", $0) }.joined()
        #expect(CredentialStore.decodeSecurityOutput(hex) == original)
        #expect(CredentialStore.decodeSecurityOutput(original) == original)
    }

    @Test("ProviderStatus.primaryUsagePercent prioriza pico crítico ou pool ativo do Antigravity")
    func testPrimaryUsagePercentSmartSelection() {
        let future = Date().addingTimeInterval(3600)

        // 1. Claude normal: Session (20%) < 85%, Weekly (46%) < 85% -> mostra Session (20%)
        let claudeNormal = ProviderStatus(
            provider: .claude,
            state: .healthy,
            windows: [
                QuotaWindow(name: "Session", usedPercent: 20, resetsAt: future, limitWindowSeconds: 5 * 3600),
                QuotaWindow(name: "Weekly", usedPercent: 46, resetsAt: future, limitWindowSeconds: 7 * 86_400)
            ]
        )
        #expect(claudeNormal.primaryUsagePercent == 20.0)

        // 2. Claude com Weekly crítico (>= 85%): destaca o limite crítico no menu bar
        let claudeNearWeeklyLimit = ProviderStatus(
            provider: .claude,
            state: .warning("Near Limit"),
            windows: [
                QuotaWindow(name: "Session", usedPercent: 15, resetsAt: future, limitWindowSeconds: 5 * 3600),
                QuotaWindow(name: "Weekly", usedPercent: 92, resetsAt: future, limitWindowSeconds: 7 * 86_400)
            ]
        )
        #expect(claudeNearWeeklyLimit.primaryUsagePercent == 92.0)

        // 3. Antigravity com Session ocioso (1%) mas Argon/Claude ativo (51%): mostra o pool em uso
        let agyActivePool = ProviderStatus(
            provider: .antigravity,
            state: .healthy,
            windows: [
                QuotaWindow(name: "Gemini Flash & Pro · Session", usedPercent: 1, resetsAt: future, limitWindowSeconds: 5 * 3600),
                QuotaWindow(name: "Gemini 4 Argon · Weekly", usedPercent: 22, resetsAt: future, limitWindowSeconds: 7 * 86_400),
                QuotaWindow(name: "Claude & GPT · Weekly", usedPercent: 51, resetsAt: future, limitWindowSeconds: 7 * 86_400)
            ]
        )
        #expect(agyActivePool.primaryUsagePercent == 51.0)
    }

    @Test("Cofre local AES-GCM salva, lê e remove credenciais sem usar o Keychain do macOS")
    func testLocalEncryptedVaultRoundTrip() {
        let service = "com.antigravity.monohub.test.vault"
        _ = Keychain.delete(service: service)
        #expect(Keychain.read(service: service) == nil)

        #expect(Keychain.write(service: service, account: "user", secret: "sk-ant-oat01-secret") == true)
        let readBack = Keychain.read(service: service, account: "user")
        #expect(readBack?.secret == "sk-ant-oat01-secret")
        #expect(readBack?.account == "user")
        #expect(Keychain.exists(service: service) == true)

        #expect(Keychain.delete(service: service) == true)
        #expect(Keychain.read(service: service) == nil)
    }
}
