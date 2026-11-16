import Foundation
import Observation
import OSLog

nonisolated enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case ringValue
    case ringOnly
    case iconStacked
    case labelStacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringValue: return localized("Ring and value")
        case .ringOnly: return localized("Ring only")
        case .iconStacked: return localized("Icon over value")
        case .labelStacked: return localized("Label over value")
        }
    }

    var systemImage: String {
        switch self {
        case .ringValue: "circle.dashed"
        case .ringOnly: "circle"
        case .iconStacked: "rectangle.split.1x2"
        case .labelStacked: "textformat"
        }
    }
}

nonisolated enum DefaultsKey {
    static let refreshInterval = "MonoHub_aiQuota_refresh_interval"
    static let displayMode = "MonoHub_aiQuota_display_mode"
    static let enabledProviders = "MonoHub_aiQuota_enabled_providers"
    static let notificationsEnabled = "MonoHub_aiQuota_notifications_enabled"
    static let warningThreshold = "MonoHub_aiQuota_warning_threshold"
    static let antigravityCLIEnabled = "MonoHub_aiQuota_antigravity_cli_enabled"
    static let providerOrder = "MonoHub_aiQuota_provider_order"
    static let alertColors = "MonoHub_aiQuota_alert_colors"
    static let showInMenuBar = "MonoHub_aiQuota_show_in_menu_bar"
}

@MainActor
@Observable
final class QuotaPreferencesManager {
    static let shared = QuotaPreferencesManager()

    private typealias Key = DefaultsKey

    let availableIntervals: [(label: String, seconds: TimeInterval)] = [
        ("1m", 60),
        ("5m", 300),
        ("15m", 900),
        ("30m", 1800)
    ]

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    var warningThreshold: Double {
        didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) }
    }

    var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            defaults.set(refreshInterval, forKey: Key.refreshInterval)
            QuotaManager.shared.refreshIntervalChanged(to: refreshInterval)
        }
    }

    var antigravityCLIEnabled: Bool {
        didSet {
            guard antigravityCLIEnabled != oldValue else { return }
            defaults.set(antigravityCLIEnabled, forKey: Key.antigravityCLIEnabled)
            Task { await QuotaManager.shared.refresh(provider: .antigravity, force: true) }
        }
    }

    var displayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: Key.displayMode)
            AIQuotaStatusItemController.shared.updateImage()
        }
    }

    var alertColors: Bool {
        didSet {
            defaults.set(alertColors, forKey: Key.alertColors)
            AIQuotaStatusItemController.shared.updateImage()
        }
    }

    var showInMenuBar: Bool {
        didSet {
            defaults.set(showInMenuBar, forKey: Key.showInMenuBar)
            AIQuotaStatusItemController.shared.setVisible(showInMenuBar)
        }
    }

    private(set) var providerOrder: [ProviderType] {
        didSet { defaults.set(providerOrder.map(\.id), forKey: Key.providerOrder) }
    }

    var enabledProviders: [ProviderType] {
        didSet {
            defaults.set(enabledProviders.map(\.id), forKey: Key.enabledProviders)
            AIQuotaStatusItemController.shared.updateImage()
        }
    }

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    private init() {
        let defaults = UserDefaults.standard

        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        antigravityCLIEnabled = defaults.object(forKey: Key.antigravityCLIEnabled) as? Bool ?? true

        let storedThreshold = defaults.double(forKey: Key.warningThreshold)
        warningThreshold = storedThreshold > 0 ? storedThreshold : 80.0

        let storedInterval = defaults.double(forKey: Key.refreshInterval)
        refreshInterval = storedInterval > 0 ? storedInterval : 300.0

        displayMode = defaults.string(forKey: Key.displayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .ringValue

        alertColors = defaults.object(forKey: Key.alertColors) as? Bool ?? true
        showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true

        var order = (defaults.stringArray(forKey: Key.providerOrder) ?? [])
            .compactMap { id in ProviderType.allCases.first { $0.id == id } }
        for provider in ProviderType.allCases where !order.contains(provider) {
            order.append(provider)
        }
        providerOrder = order

        let storedProviders = (defaults.stringArray(forKey: Key.enabledProviders) ?? [])
            .compactMap { id in ProviderType.allCases.first { $0.id == id } }
        let enabled = storedProviders.isEmpty ? [.claude, .antigravity] : storedProviders
        enabledProviders = order.filter { enabled.contains($0) }
    }

    func isProviderEnabled(_ provider: ProviderType) -> Bool {
        enabledProviders.contains(provider)
    }

    func toggleProvider(_ provider: ProviderType) {
        if let index = enabledProviders.firstIndex(of: provider) {
            guard enabledProviders.count > 1 else { return }
            enabledProviders.remove(at: index)
        } else {
            enabledProviders = providerOrder.filter { enabledProviders.contains($0) || $0 == provider }
            Task { await QuotaManager.shared.refresh(provider: provider, force: true) }
        }
    }

    func moveProviders(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = providerOrder
        let moving = source.map { reordered[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let insertion = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: min(max(insertion, 0), reordered.count))
        applyOrder(reordered)
    }

    func moveProvider(_ provider: ProviderType, onto target: ProviderType) {
        applyOrder(providerOrder.moving(provider, onto: target))
    }

    func moveProviderUp(_ provider: ProviderType) {
        shiftProvider(provider, by: -1)
    }

    func moveProviderDown(_ provider: ProviderType) {
        shiftProvider(provider, by: 1)
    }

    private func shiftProvider(_ provider: ProviderType, by step: Int) {
        guard let index = providerOrder.firstIndex(of: provider) else { return }
        let visible = providerOrder.indices.filter { enabledProviders.contains(providerOrder[$0]) || $0 == index }
        guard let position = visible.firstIndex(of: index) else { return }
        let target = position + step
        guard visible.indices.contains(target) else { return }
        var reordered = providerOrder
        reordered.swapAt(index, visible[target])
        applyOrder(reordered)
    }

    private func applyOrder(_ order: [ProviderType]) {
        providerOrder = order
        let enabled = Set(enabledProviders)
        enabledProviders = order.filter { enabled.contains($0) }
    }
}
