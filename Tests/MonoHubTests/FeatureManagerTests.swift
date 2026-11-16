import Foundation
import Testing
@testable import MonoHub

@MainActor
@Suite("Feature toggles")
struct FeatureManagerTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "com.antigravity.monohub.tests.features"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Every feature except External Displays starts enabled on a fresh install")
    func defaultsToEnabled() {
        let manager = FeatureManager(defaults: makeDefaults())
        let expected = Set(HubFeature.allCases.filter { $0 != .displayControl })
        #expect(manager.enabledFeatures == expected)
        #expect(!manager.isEnabled(.displayControl))
    }

    @Test("External Displays is opt-in and stays off unless explicitly enabled")
    func displayControlIsOptIn() {
        let defaults = makeDefaults()
        #expect(!HubFeature.displayControl.isEnabledByDefault)
        #expect(!FeatureManager(defaults: defaults).isEnabled(.displayControl))

        let manager = FeatureManager(defaults: defaults)
        manager.setEnabled(.displayControl, true)
        #expect(FeatureManager(defaults: defaults).isEnabled(.displayControl))

        manager.setEnabled(.displayControl, false)
        #expect(!FeatureManager(defaults: defaults).isEnabled(.displayControl))
    }

    @Test("Disabling a feature persists across instances")
    func persistsToggle() {
        let defaults = makeDefaults()
        let manager = FeatureManager(defaults: defaults)
        manager.setEnabled(.dynamicNotch, false)
        manager.setEnabled(.windowSwitcher, false)

        let reloaded = FeatureManager(defaults: defaults)
        #expect(!reloaded.isEnabled(.dynamicNotch))
        #expect(!reloaded.isEnabled(.windowSwitcher))
        #expect(reloaded.isEnabled(.systemMonitor))
    }

    @Test("Sidebar hides pages owned by disabled features only")
    func sidebarAvailability() {
        let manager = FeatureManager(defaults: makeDefaults())
        manager.setEnabled(.cleanupTools, false)

        #expect(!manager.isSidebarItemAvailable(.uninstaller))
        #expect(!manager.isSidebarItemAvailable(.history))
        #expect(manager.isSidebarItemAvailable(.dashboard))
        #expect(manager.isSidebarItemAvailable(.modules))
        #expect(manager.isSidebarItemAvailable(.settings))
        #expect(manager.isSidebarItemAvailable(.notch))
    }

    @Test("AI quota owns its page and can be turned off")
    func aiQuotaFeature() {
        let manager = FeatureManager(defaults: makeDefaults())
        #expect(SidebarItem.aiQuota.feature == .aiQuota)
        manager.setEnabled(.aiQuota, false)
        #expect(!manager.isSidebarItemAvailable(.aiQuota))
        #expect(manager.isSidebarItemAvailable(.windowTiling))
    }

    @Test("External Displays owns its page and can be turned off")
    func displayControlFeature() {
        let manager = FeatureManager(defaults: makeDefaults())
        #expect(SidebarItem.displayControl.feature == .displayControl)
        manager.setEnabled(.displayControl, false)
        #expect(!manager.isSidebarItemAvailable(.displayControl))
        #expect(manager.isSidebarItemAvailable(.monitor))
    }

    @Test("Every feature-owned page belongs to exactly one feature")
    func uniqueOwnership() {
        let owned = HubFeature.allCases.flatMap(\.sidebarItems)
        #expect(owned.count == Set(owned).count)
        for item in [SidebarItem.dashboard, .modules, .settings] {
            #expect(item.feature == nil)
        }
    }
}
