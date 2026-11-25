import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusBarSlot {
    let item: NSStatusItem
    var module: ModuleType
    var lastContent: MenuBarContent?

    init(item: NSStatusItem, module: ModuleType) {
        self.item = item
        self.module = module
    }
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var slots: [StatusBarSlot] = []
    private var panel: MenuBarPanel?
    private var panelModule: ModuleType?
    private var lastDismissal: (module: ModuleType, time: TimeInterval)?
    private var globalClickMonitor: Any?
    private var panelObservers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var occlusionObservers: [any NSObjectProtocol] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var preferencesGeneration = 0
    private(set) var isSetUp = false

    private override init() {
        super.init()
    }

    func setup() {
        guard !isSetUp else { return }
        isSetUp = true
        let engine = SystemMonitorEngine.shared
        engine.onSample = { [weak self] in
            self?.refresh()
        }
        rebuildStatusItems()
        observePreferences()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                StatusItemController.shared.updateRenderHeight()
            }
        }
    }

    func teardown() {
        guard isSetUp else { return }
        isSetUp = false
        preferencesGeneration += 1
        closePanel(animated: false)
        removeDismissMonitors()
        lastDismissal = nil
        SystemMonitorEngine.shared.onSample = nil
        SystemMonitorEngine.shared.setMenuBarVisible(false)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        removeOcclusionObservers()
        for slot in slots {
            NSStatusBar.system.removeStatusItem(slot.item)
        }
        slots.removeAll()
    }

    private func updateRenderHeight() {
        let screen = slots.first?.item.button?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        if MenuBarRenderer.updateAvailableHeight(menuBarHeight - 5) {
            invalidateRenderedContent()
            refresh()
        }
    }

    func rebuildStatusItems() {
        let modules = isSetUp ? MonitorPreferences.shared.orderedEnabledModules : []

        if slots.count == modules.count, !slots.isEmpty {
            for (slot, module) in zip(orderedSlots(), modules) where slot.module != module {
                if slot.module == panelModule {
                    closePanel(animated: false)
                }
                slot.module = module
                slot.lastContent = nil
            }
            refresh()
            return
        }

        closePanel(animated: false)
        for slot in slots {
            NSStatusBar.system.removeStatusItem(slot.item)
        }
        slots.removeAll()

        for module in modules.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.behavior = []
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.imagePosition = .imageOnly
            }
            slots.insert(StatusBarSlot(item: item, module: module), at: 0)
        }

        observeOcclusion()
        updateRenderHeight()
        updateMenuBarVisibility()
        refresh()
    }

    func refresh() {
        guard !slots.isEmpty, SystemMonitorEngine.shared.isMenuBarVisible else { return }
        let prefs = MonitorPreferences.shared
        for slot in slots {
            guard let button = slot.item.button else { continue }
            let content = MenuBarContentFactory.content(for: slot.module, style: prefs.displayStyle(for: slot.module))
            guard content != slot.lastContent else { continue }
            slot.lastContent = content
            let image = MenuBarRenderer.image(for: content)
            let length = image.size.width + MenuBarRenderer.itemPadding * 2
            if abs(slot.item.length - length) > 0.01 {
                slot.item.length = length
            }
            if button.image !== image {
                button.image = image
                button.setAccessibilityLabel(content.accessibilityLabel)
            }
        }
    }

    private func orderedSlots() -> [StatusBarSlot] {
        slots.sorted {
            ($0.item.button?.window?.frame.minX ?? 0) < ($1.item.button?.window?.frame.minX ?? 0)
        }
    }

    private func observePreferences() {
        let generation = preferencesGeneration
        withObservationTracking {
            let prefs = MonitorPreferences.shared
            _ = prefs.isMenuBarActive
            _ = prefs.enabledModules
            _ = prefs.moduleOrder
            _ = prefs.displayStyles
            _ = prefs.useDynamicColors
            _ = prefs.showPercentSymbol
            _ = prefs.prominentPercentage
            _ = prefs.refreshInterval
            _ = prefs.pauseWhenSleeping
            _ = prefs.topProcessesCount
            _ = prefs.showTopProcessesCPU
            _ = prefs.showTopProcessesRAM
            _ = prefs.showTopProcessesGPU
            _ = prefs.showTopProcessesBattery
            _ = prefs.showTopProcessesDisk
            _ = PreferencesManager.shared.language
        } onChange: {
            Task { @MainActor in
                let controller = StatusItemController.shared
                guard controller.isSetUp, controller.preferencesGeneration == generation else { return }
                SystemMonitorEngine.shared.reloadConfiguration()
                controller.invalidateRenderedContent()
                controller.rebuildStatusItems()
                MainWindowController.shared.updateActivationPolicy()
                controller.observePreferences()
            }
        }
    }

    private func invalidateRenderedContent() {
        for slot in slots {
            slot.lastContent = nil
        }
    }

    private func removeOcclusionObservers() {
        for observer in occlusionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        occlusionObservers.removeAll()
    }

    private func observeOcclusion() {
        removeOcclusionObservers()
        occlusionObservers = slots.compactMap { $0.item.button?.window }.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    StatusItemController.shared.updateMenuBarVisibility()
                }
            }
        }
    }

    private func updateMenuBarVisibility() {
        let visible = slots.contains { $0.item.button?.window?.occlusionState.contains(.visible) ?? true }
        let engine = SystemMonitorEngine.shared
        let becameVisible = visible && !engine.isMenuBarVisible
        engine.setMenuBarVisible(visible)
        if becameVisible {
            refresh()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent,
              let slot = slots.first(where: { $0.item.button === sender }) else { return }
        let module = slot.module

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(for: module, in: slot)
        } else if panel == nil, let lastDismissal, lastDismissal.module == module, ProcessInfo.processInfo.systemUptime - lastDismissal.time < 0.4 {
            self.lastDismissal = nil
        } else {
            togglePanel(for: module, in: slot)
        }
    }

    private func isMouseDownOnStatusItem() -> Bool {
        guard NSEvent.pressedMouseButtons != 0 else { return false }
        let location = NSEvent.mouseLocation
        return slots.contains { $0.item.button?.window?.frame.contains(location) ?? false }
    }

    private func togglePanel(for module: ModuleType, in slot: StatusBarSlot) {
        guard let button = slot.item.button else { return }
        if panel != nil {
            let wasSameModule = panelModule == module
            closePanel(animated: wasSameModule)
            if wasSameModule { return }
        }

        let newPanel = MenuBarPanel(content: PanelRootView(module: module))
        newPanel.onCancel = { [weak self] in
            self?.closePanel(animated: true)
        }
        panel = newPanel
        panelModule = module
        SystemMonitorEngine.shared.setDetailedModule(module)
        button.highlight(true)
        newPanel.present(below: button)
        installDismissMonitors(for: newPanel)
    }

    func closePanel(animated: Bool) {
        guard let current = panel else { return }
        removeDismissMonitors()
        lastDismissal = panelModule.map { ($0, ProcessInfo.processInfo.systemUptime) }
        panel = nil
        panelModule = nil
        SystemMonitorEngine.shared.setDetailedModule(nil)
        for slot in slots {
            slot.item.button?.highlight(false)
        }
        if animated {
            current.dismiss {}
        } else {
            current.tearDown()
        }
    }

    private func installDismissMonitors(for panel: MenuBarPanel) {
        removeDismissMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated {
                StatusItemController.shared.closePanel(animated: true)
            }
        }

        let defaultCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        panelObservers = [
            (
                defaultCenter,
                defaultCenter.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        let controller = StatusItemController.shared
                        guard !controller.isMouseDownOnStatusItem() else { return }
                        controller.closePanel(animated: true)
                    }
                }
            ),
            (
                workspaceCenter,
                workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        StatusItemController.shared.closePanel(animated: false)
                    }
                }
            )
        ]
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        globalClickMonitor = nil
        for observer in panelObservers {
            observer.center.removeObserver(observer.token)
        }
        panelObservers.removeAll()
    }

    func openMainWindow() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .dashboard)
    }

    func openSettings() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .menuBar)
    }

    private func showContextMenu(for module: ModuleType, in slot: StatusBarSlot) {
        closePanel(animated: false)
        let menu = ContextMenuBuilder(target: self).menu(for: module)
        slot.item.menu = menu
        slot.item.button?.performClick(nil)
        slot.item.menu = nil
    }

    @objc func selectDisplayStyle(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? StyleChoice else { return }
        MonitorPreferences.shared.setDisplayStyle(choice.style, for: choice.module)
    }

    @objc func toggleModuleVisibility(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let module = ModuleType(rawValue: raw) else { return }
        MonitorPreferences.shared.toggleModule(module)
    }

    @objc func openModuleDetails(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = ModuleType(rawValue: raw),
              let slot = slots.first(where: { $0.module == module }) else { return }
        togglePanel(for: module, in: slot)
    }

    @objc func openSystemTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let module = ModuleType(rawValue: raw) else { return }
        NativeAppLauncher.openSystemTool(for: module)
    }

    @objc func openMainWindowAction() {
        openMainWindow()
    }

    @objc func performWindowAction(_ sender: NSMenuItem) {
        guard FeatureManager.shared.isEnabled(.windowTiling),
              let raw = sender.representedObject as? String,
              let action = WindowAction(rawValue: raw) else { return }
        closePanel(animated: false)
        WindowManager.shared.perform(action: action)
    }

    @objc func openWindowTilingAction() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .windowTiling)
    }

    @objc func openSettingsAction() {
        openSettings()
    }

    @objc func openAboutAction() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .settings)
    }

    @objc func toggleLaunchAtLogin() {
        PreferencesManager.shared.launchAtLogin.toggle()
    }

    @objc func quit() {
        (NSApp.delegate as? AppDelegate)?.forceTerminate() ?? NSApp.terminate(nil)
    }
}

final class StyleChoice: NSObject {
    let module: ModuleType
    let style: DisplayStyle

    init(module: ModuleType, style: DisplayStyle) {
        self.module = module
        self.style = style
    }
}

@MainActor
struct ContextMenuBuilder {
    let target: StatusItemController

    func menu(for module: ModuleType) -> NSMenu {
        let prefs = MonitorPreferences.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: module.title))
        if module == .battery {
            addBatterySummary(to: menu)
        }
        menu.addItem(item(localized("Show Details"), symbol: "rectangle.and.text.magnifyingglass", action: #selector(StatusItemController.openModuleDetails(_:)), object: module.rawValue))
        menu.addItem(item(NativeAppLauncher.toolTitle(for: module), symbol: NativeAppLauncher.toolSymbol(for: module), action: #selector(StatusItemController.openSystemTool(_:)), object: module.rawValue))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: localized("Menu Bar")))

        let styleMenu = NSMenu()
        let currentStyle = prefs.displayStyle(for: module)
        for style in module.availableStyles {
            let styleItem = item(style.title(for: module), symbol: style.sfSymbol, action: #selector(StatusItemController.selectDisplayStyle(_:)), object: StyleChoice(module: module, style: style))
            styleItem.state = style == currentStyle ? .on : .off
            styleMenu.addItem(styleItem)
        }
        let styleRoot = item(localized("Style"), symbol: "paintbrush", action: nil, object: nil)
        styleRoot.submenu = styleMenu
        menu.addItem(styleRoot)

        let modulesMenu = NSMenu()
        modulesMenu.autoenablesItems = false
        for candidate in prefs.moduleOrder {
            let moduleItem = item(candidate.title, symbol: candidate.sfSymbol, action: #selector(StatusItemController.toggleModuleVisibility(_:)), object: candidate.rawValue)
            let isEnabled = prefs.isModuleEnabled(candidate)
            moduleItem.state = isEnabled ? .on : .off
            moduleItem.isEnabled = !(isEnabled && prefs.enabledModules.count == 1)
            modulesMenu.addItem(moduleItem)
        }
        let modulesRoot = item(localized("Visible Modules"), symbol: "square.grid.2x2", action: nil, object: nil)
        modulesRoot.submenu = modulesMenu
        menu.addItem(modulesRoot)

        if FeatureManager.shared.isEnabled(.windowTiling) {
            menu.addItem(tilingMenuItem())
        }

        menu.addItem(.separator())

        menu.addItem(item(localized("Open MonoHub"), symbol: "macwindow", action: #selector(StatusItemController.openMainWindowAction), object: nil))

        let settings = item(localized("Settings…"), symbol: "gearshape", action: #selector(StatusItemController.openSettingsAction), object: nil)
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let login = item(localized("Open at Login"), symbol: "arrow.up.circle", action: #selector(StatusItemController.toggleLaunchAtLogin), object: nil)
        login.state = PreferencesManager.shared.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(item(localized("About MonoHub"), symbol: "info.circle", action: #selector(StatusItemController.openAboutAction), object: nil))

        menu.addItem(.separator())

        let quit = item(localized("Quit MonoHub"), symbol: "rectangle.portrait.and.arrow.right", action: #selector(StatusItemController.quit), object: nil)
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        return menu
    }

    private func tilingMenuItem() -> NSMenuItem {
        let tilingMenu = NSMenu()
        let quickActions: [WindowAction] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .restore]
        for action in quickActions {
            let actionItem = item(action.displayName, symbol: action.sfSymbol, action: #selector(StatusItemController.performWindowAction(_:)), object: action.rawValue)
            if let shortcut = TilePreferencesManager.shared.shortcut(for: action) {
                actionItem.keyEquivalent = shortcut.menuKeyEquivalent
                actionItem.keyEquivalentModifierMask = shortcut.modifiers.nsEventModifiers
            }
            tilingMenu.addItem(actionItem)
        }
        tilingMenu.addItem(.separator())
        tilingMenu.addItem(item(localized("Configure Window Tiling (MonoTile)…"), symbol: "rectangle.split.2x2", action: #selector(StatusItemController.openWindowTilingAction), object: nil))

        let tilingRoot = item(localized("Window Tiling"), symbol: "rectangle.split.2x2", action: nil, object: nil)
        tilingRoot.submenu = tilingMenu
        return tilingRoot
    }

    private func addBatterySummary(to menu: NSMenu) {
        var battery = SystemMonitorEngine.shared.batteryData
        battery.policies = battery.policies ?? SystemMonitorEngine.shared.powerPolicies
        let openBatterySettings = #selector(StatusItemController.openSystemTool(_:))
        let object = ModuleType.battery.rawValue

        if battery.hasBattery {
            let status = item("\(battery.levelPercent)% · \(battery.stateTitle)", symbol: battery.powerState.symbol, action: nil, object: nil)
            status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(item(localized("Power Source: %@", battery.powerSourceDescription), symbol: "powerplug.portrait", action: openBatterySettings, object: object))
        if let mode = battery.activeEnergyMode {
            menu.addItem(item(localized("Energy Mode: %@", mode.title), symbol: mode.symbol, action: openBatterySettings, object: object))
        }
        if battery.hasBattery, battery.policies != nil {
            menu.addItem(item(localized("Charge Limit: %@", battery.chargeLimitDescription), symbol: "battery.75percent", action: openBatterySettings, object: object))
        }
        menu.addItem(.separator())
    }

    private func item(_ title: String, symbol: String, action: Selector?, object: Any?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = action == nil ? nil : target
        menuItem.representedObject = object
        menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return menuItem
    }
}
