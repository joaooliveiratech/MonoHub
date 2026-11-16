import Foundation
import Observation

@Observable
@MainActor
final class HUDManager {
    static let shared = HUDManager()

    private(set) var activeHUD: HUDEvent?
    private(set) var isVisible: Bool = false

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {}

    func showHUD(
        type: HUDType,
        value: Float,
        isMuted: Bool = false,
        displayTitle: String? = nil,
        customIconName: String? = nil
    ) {
        guard NotchPreferences.shared.enableSystemHUD else { return }

        activeHUD = HUDEvent(
            type: type,
            value: value,
            isMuted: isMuted,
            displayTitle: displayTitle,
            customIconName: customIconName
        )
        if !isVisible {
            isVisible = true
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        if isVisible {
            isVisible = false
        }
        activeHUD = nil
    }
}
