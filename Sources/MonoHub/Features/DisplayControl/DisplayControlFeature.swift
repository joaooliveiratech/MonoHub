import Foundation
import Observation
import Synchronization

nonisolated enum DisplayControlGate {
    private static let state = Atomic<Bool>(false)

    static var isOpen: Bool { state.load(ordering: .acquiring) }

    static func setOpen(_ open: Bool) {
        state.store(open, ordering: .releasing)
    }
}

@MainActor
enum DisplayControlFeature: FeatureModule {
    private(set) static var isActive = false

    static func activate() {
        guard !isActive else { return }
        isActive = true
        DisplayControlGate.setOpen(true)
        ExternalDisplayManager.shared.start()
    }

    static func deactivate() {
        guard isActive else { return }
        isActive = false

        ExternalDisplayManager.shared.stop()
        DisplayControlGate.setOpen(false)
    }
}
