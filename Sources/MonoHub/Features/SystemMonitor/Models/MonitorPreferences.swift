import Foundation

@Observable
@MainActor
final class MonitorPreferences {
    static let shared = MonitorPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isMenuBarEnabled = "MonoHub_isMenuBarEnabled"
        static let enabledModules = "MonoHub_enabledModules"
        static let moduleOrder = "MonoHub_moduleOrder"
        static let displayStyles = "MonoHub_displayStyles"
        static let refreshInterval = "MonoHub_refreshInterval"
        static let pauseWhenSleeping = "MonoHub_pauseWhenSleeping"
        static let useDynamicColors = "MonoHub_useDynamicColors"
        static let showPercentSymbol = "MonoHub_showPercentSymbol"
        static let prominentPercentage = "MonoHub_prominentPercentage"
        static let topProcessesCount = "MonoHub_topProcessesCount"
        static let showTopProcessesCPU = "MonoHub_showTopProcessesCPU"
        static let showTopProcessesRAM = "MonoHub_showTopProcessesRAM"
        static let showTopProcessesGPU = "MonoHub_showTopProcessesGPU"
        static let showTopProcessesBattery = "MonoHub_showTopProcessesBattery"
        static let showTopProcessesDisk = "MonoHub_showTopProcessesDisk"
    }

    var isMenuBarEnabled: Bool {
        didSet { defaults.set(isMenuBarEnabled, forKey: Keys.isMenuBarEnabled) }
    }

    var enabledModules: Set<ModuleType> {
        didSet {
            defaults.set(enabledModules.map(\.rawValue), forKey: Keys.enabledModules)
        }
    }

    var moduleOrder: [ModuleType] {
        didSet {
            defaults.set(moduleOrder.map(\.rawValue), forKey: Keys.moduleOrder)
        }
    }

    var displayStyles: [String: String] {
        didSet { defaults.set(displayStyles, forKey: Keys.displayStyles) }
    }

    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    var pauseWhenSleeping: Bool {
        didSet { defaults.set(pauseWhenSleeping, forKey: Keys.pauseWhenSleeping) }
    }

    var useDynamicColors: Bool {
        didSet { defaults.set(useDynamicColors, forKey: Keys.useDynamicColors) }
    }

    var showPercentSymbol: Bool {
        didSet { defaults.set(showPercentSymbol, forKey: Keys.showPercentSymbol) }
    }

    var prominentPercentage: Bool {
        didSet { defaults.set(prominentPercentage, forKey: Keys.prominentPercentage) }
    }

    var topProcessesCount: Int {
        didSet { defaults.set(topProcessesCount, forKey: Keys.topProcessesCount) }
    }

    var showTopProcessesCPU: Bool {
        didSet { defaults.set(showTopProcessesCPU, forKey: Keys.showTopProcessesCPU) }
    }

    var showTopProcessesRAM: Bool {
        didSet { defaults.set(showTopProcessesRAM, forKey: Keys.showTopProcessesRAM) }
    }

    var showTopProcessesGPU: Bool {
        didSet { defaults.set(showTopProcessesGPU, forKey: Keys.showTopProcessesGPU) }
    }

    var showTopProcessesBattery: Bool {
        didSet { defaults.set(showTopProcessesBattery, forKey: Keys.showTopProcessesBattery) }
    }

    var showTopProcessesDisk: Bool {
        didSet { defaults.set(showTopProcessesDisk, forKey: Keys.showTopProcessesDisk) }
    }

    private init() {
        self.isMenuBarEnabled = defaults.object(forKey: Keys.isMenuBarEnabled) == nil ? true : defaults.bool(forKey: Keys.isMenuBarEnabled)

        if let stored = defaults.stringArray(forKey: Keys.enabledModules) {
            let modules = stored.compactMap { ModuleType(rawValue: $0) }
            self.enabledModules = Set(modules.isEmpty ? [.cpu, .ram, .network, .battery] : modules)
        } else {
            self.enabledModules = [.cpu, .ram, .network, .battery]
        }

        if let storedOrder = defaults.stringArray(forKey: Keys.moduleOrder) {
            var loaded = storedOrder.compactMap { ModuleType(rawValue: $0) }
            for module in ModuleType.allCases where !loaded.contains(module) {
                loaded.append(module)
            }
            self.moduleOrder = loaded
        } else {
            self.moduleOrder = ModuleType.allCases.sorted { $0.defaultOrder < $1.defaultOrder }
        }

        self.displayStyles = defaults.dictionary(forKey: Keys.displayStyles) as? [String: String] ?? [:]
        let storedInterval = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = storedInterval > 0 ? storedInterval.clamped(to: 1...10) : 2.0

        self.pauseWhenSleeping = defaults.object(forKey: Keys.pauseWhenSleeping) == nil ? true : defaults.bool(forKey: Keys.pauseWhenSleeping)
        self.useDynamicColors = defaults.object(forKey: Keys.useDynamicColors) == nil ? true : defaults.bool(forKey: Keys.useDynamicColors)
        self.showPercentSymbol = defaults.object(forKey: Keys.showPercentSymbol) == nil ? true : defaults.bool(forKey: Keys.showPercentSymbol)
        self.prominentPercentage = defaults.object(forKey: Keys.prominentPercentage) == nil ? true : defaults.bool(forKey: Keys.prominentPercentage)
        self.topProcessesCount = defaults.object(forKey: Keys.topProcessesCount) == nil ? 5 : defaults.integer(forKey: Keys.topProcessesCount).clamped(to: 0...10)
        self.showTopProcessesCPU = defaults.object(forKey: Keys.showTopProcessesCPU) == nil ? true : defaults.bool(forKey: Keys.showTopProcessesCPU)
        self.showTopProcessesRAM = defaults.object(forKey: Keys.showTopProcessesRAM) == nil ? true : defaults.bool(forKey: Keys.showTopProcessesRAM)
        self.showTopProcessesGPU = defaults.object(forKey: Keys.showTopProcessesGPU) == nil ? true : defaults.bool(forKey: Keys.showTopProcessesGPU)
        self.showTopProcessesBattery = defaults.object(forKey: Keys.showTopProcessesBattery) == nil ? true : defaults.bool(forKey: Keys.showTopProcessesBattery)
        self.showTopProcessesDisk = defaults.object(forKey: Keys.showTopProcessesDisk) == nil ? true : defaults.bool(forKey: Keys.showTopProcessesDisk)
    }

    func displayStyle(for module: ModuleType) -> DisplayStyle {
        if let raw = displayStyles[module.rawValue],
           let style = DisplayStyle(rawValue: raw),
           module.availableStyles.contains(style) {
            return style
        }
        return module.defaultStyle
    }

    func setDisplayStyle(_ style: DisplayStyle, for module: ModuleType) {
        var copy = displayStyles
        copy[module.rawValue] = style.rawValue
        self.displayStyles = copy
    }

    func isModuleEnabled(_ module: ModuleType) -> Bool {
        enabledModules.contains(module)
    }

    func toggleModule(_ module: ModuleType) {
        if enabledModules.contains(module) {
            if enabledModules.count > 1 {
                enabledModules.remove(module)
            }
        } else {
            enabledModules.insert(module)
        }
    }

    var isMenuBarActive: Bool {
        isMenuBarEnabled && FeatureManager.shared.isEnabled(.systemMonitor)
    }

    var orderedEnabledModules: [ModuleType] {
        guard isMenuBarActive else { return [] }
        return moduleOrder.filter { enabledModules.contains($0) }
    }

    func moveModules(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = moduleOrder
        let moving = source.map { reordered[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let insertion = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: insertion.clamped(to: 0...reordered.count))
        moduleOrder = reordered
    }

    func moveModule(_ module: ModuleType, onto target: ModuleType) {
        moduleOrder = moduleOrder.moving(module, onto: target)
    }

    func moveModuleUp(_ module: ModuleType) {
        guard let idx = moduleOrder.firstIndex(of: module), idx > 0 else { return }
        if enabledModules.contains(module),
           let prevEnabledIdx = moduleOrder[..<idx].lastIndex(where: { enabledModules.contains($0) }) {
            let item = moduleOrder.remove(at: idx)
            moduleOrder.insert(item, at: prevEnabledIdx)
            return
        }
        moduleOrder.swapAt(idx, idx - 1)
    }

    func moveModuleDown(_ module: ModuleType) {
        guard let idx = moduleOrder.firstIndex(of: module), idx < moduleOrder.count - 1 else { return }
        if enabledModules.contains(module),
           let nextEnabledIdx = moduleOrder[(idx + 1)...].firstIndex(where: { enabledModules.contains($0) }) {
            let item = moduleOrder.remove(at: idx)
            moduleOrder.insert(item, at: nextEnabledIdx)
            return
        }
        moduleOrder.swapAt(idx, idx + 1)
    }

    func applyPresetToAll(_ style: DisplayStyle) {
        var copy = displayStyles
        for mod in ModuleType.allCases where mod.availableStyles.contains(style) {
            copy[mod.rawValue] = style.rawValue
        }
        self.displayStyles = copy
    }
}
