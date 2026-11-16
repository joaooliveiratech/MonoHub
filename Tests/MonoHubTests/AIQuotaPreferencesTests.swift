import Foundation
import Testing
@testable import MonoHub

@MainActor
@Suite("AI quota provider order")
struct AIQuotaPreferencesTests {
    @Test("Moving a provider reorders the menu bar columns")
    func moveReordersEnabledProviders() {
        let prefs = QuotaPreferencesManager.shared
        let originalOrder = prefs.providerOrder
        let originalEnabled = prefs.enabledProviders
        defer {
            prefs.moveProviders(fromOffsets: IndexSet(integersIn: 0..<originalOrder.count), toOffset: 0)
            while prefs.providerOrder != originalOrder, let target = originalOrder.first(where: { prefs.providerOrder.firstIndex(of: $0) != originalOrder.firstIndex(of: $0) }),
                  let from = prefs.providerOrder.firstIndex(of: target), let to = originalOrder.firstIndex(of: target) {
                prefs.moveProviders(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            for provider in ProviderType.allCases where prefs.isProviderEnabled(provider) != originalEnabled.contains(provider) {
                prefs.toggleProvider(provider)
            }
        }

        if !prefs.isProviderEnabled(.claude) { prefs.toggleProvider(.claude) }
        if !prefs.isProviderEnabled(.codex) { prefs.toggleProvider(.codex) }

        let claude = prefs.providerOrder.firstIndex(of: .claude)!
        let codex = prefs.providerOrder.firstIndex(of: .codex)!
        if claude < codex {
            prefs.moveProviders(fromOffsets: IndexSet(integer: codex), toOffset: claude)
        }

        let enabled = prefs.enabledProviders
        #expect(enabled.firstIndex(of: .codex)! < enabled.firstIndex(of: .claude)!)
        #expect(enabled == prefs.providerOrder.filter { enabled.contains($0) })
    }
}
