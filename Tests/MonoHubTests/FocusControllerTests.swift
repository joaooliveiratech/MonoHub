import Foundation
import Testing
@testable import MonoHub

@Suite("Focus Controller")
struct FocusControllerTests {
    @Test func parsesBundleIDLists() {
        let ids = FocusController.parseBundleIDs(" com.a.b, com.c.d;\ncom.e.f ,, ")
        #expect(ids == ["com.a.b", "com.c.d", "com.e.f"])
    }

    @Test @MainActor func inactiveWhenDisabled() {
        let prefs = NotchPreferences.shared
        let old = prefs.focusModeEnabled
        prefs.focusModeEnabled = false
        FocusController.shared.setActive(true)
        #expect(FocusController.shared.isEngaged == false)
        prefs.focusModeEnabled = old
    }
}
