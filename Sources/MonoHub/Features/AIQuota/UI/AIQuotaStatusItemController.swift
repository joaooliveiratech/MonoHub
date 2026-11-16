import AppKit
import Observation
import SwiftUI

@MainActor
final class AIQuotaStatusItemController: NSObject {
    static let shared = AIQuotaStatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var globalClickMonitor: Any?
    private var panelObservers: [any NSObjectProtocol] = []
    private var lastDismissal: TimeInterval?
    private var screenObserver: (any NSObjectProtocol)?
    private var preferencesGeneration = 0
    private(set) var isSetUp = false

    private override init() {
        super.init()
    }

    func setup() {
        guard !isSetUp else { return }
        isSetUp = true
        setVisible(QuotaPreferencesManager.shared.showInMenuBar)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AIQuotaStatusItemController.shared.updateImage()
            }
        }
        observePreferences()
    }

    func teardown() {
        guard isSetUp else { return }
        isSetUp = false
        preferencesGeneration += 1
        setVisible(false)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        AIQuotaMenuBarRenderer.purgeCaches()
    }

    func setVisible(_ visible: Bool) {
        guard isSetUp else { return }
        guard visible else {
            closePanel(animated: false)
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MonoHubAIQuotaStatusItem"
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(localized("AI Quotas"))
            button.setAccessibilityHelp(localized("Shows usage and limits of AI providers"))
        }
        statusItem = item
        updateImage()
    }

    func updateImage() {
        guard let button = statusItem?.button else { return }
        let prefs = QuotaPreferencesManager.shared
        let columns = AIQuotaMenuBarRenderer.currentColumns()

        let image = AIQuotaMenuBarRenderer.image(mode: prefs.displayMode, columns: columns)
        if button.image !== image {
            button.image = image
        }
        let length = image.size.width + MenuBarRenderer.itemPadding * 2
        if statusItem?.length != length {
            statusItem?.length = length
        }
        button.setAccessibilityValue(image.accessibilityDescription)
    }

    private func observePreferences() {
        let generation = preferencesGeneration
        withObservationTracking {
            let prefs = QuotaPreferencesManager.shared
            _ = prefs.displayMode
            _ = prefs.enabledProviders
            _ = prefs.alertColors
            _ = prefs.warningThreshold
            _ = prefs.showInMenuBar
        } onChange: {
            Task { @MainActor in
                let controller = AIQuotaStatusItemController.shared
                guard controller.isSetUp, controller.preferencesGeneration == generation else { return }
                controller.updateImage()
                controller.observePreferences()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else if panel == nil, let lastDismissal, ProcessInfo.processInfo.systemUptime - lastDismissal < 0.4 {
            self.lastDismissal = nil
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if panel != nil {
            closePanel(animated: true)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = statusItem?.button, panel == nil else { return }

        let newPanel = MenuBarPanel(content: AIQuotaPanelView())
        newPanel.onCancel = { [weak self] in
            self?.closePanel(animated: true)
        }
        panel = newPanel
        button.highlight(true)
        newPanel.present(below: button)
        installDismissMonitors(for: newPanel)
        Task { await QuotaManager.shared.refreshAllIfStale() }
    }

    func closePanel(animated: Bool) {
        guard let current = panel else { return }
        removeDismissMonitors()
        lastDismissal = ProcessInfo.processInfo.systemUptime
        panel = nil
        statusItem?.button?.highlight(false)
        if animated {
            current.dismiss {}
        } else {
            current.tearDown()
        }
    }

    private func isMouseDownOnStatusItem() -> Bool {
        guard NSEvent.pressedMouseButtons != 0, let frame = statusItem?.button?.window?.frame else { return false }
        return frame.contains(NSEvent.mouseLocation)
    }

    private func installDismissMonitors(for panel: MenuBarPanel) {
        removeDismissMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated {
                AIQuotaStatusItemController.shared.closePanel(animated: true)
            }
        }

        panelObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let controller = AIQuotaStatusItemController.shared
                    guard !controller.isMouseDownOnStatusItem() else { return }
                    controller.closePanel(animated: true)
                }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AIQuotaStatusItemController.shared.closePanel(animated: false)
                }
            }
        ]
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        globalClickMonitor = nil
        for observer in panelObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        panelObservers.removeAll()
    }

    func openSettings() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .aiQuota)
    }

    private func showContextMenu() {
        closePanel(animated: false)
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: localized("AI Quotas")))
        menu.addItem(item(localized("Show Quotas"), symbol: "gauge.with.dots.needle.67percent", action: #selector(openPanel)))
        menu.addItem(item(localized("Refresh Now"), symbol: "arrow.clockwise", action: #selector(refreshNow)))

        let styles = NSMenu()
        let current = QuotaPreferencesManager.shared.displayMode
        for mode in MenuBarDisplayMode.allCases {
            let styleItem = item(mode.title, symbol: mode.systemImage, action: #selector(selectDisplayMode(_:)))
            styleItem.representedObject = mode.rawValue
            styleItem.state = mode == current ? .on : .off
            styles.addItem(styleItem)
        }
        let styleRoot = item(localized("Menu Bar Style"), symbol: "paintbrush", action: nil)
        styleRoot.submenu = styles
        menu.addItem(styleRoot)

        menu.addItem(.separator())
        menu.addItem(item(localized("Configure AI Quotas…"), symbol: "gearshape", action: #selector(openSettingsAction)))
        menu.addItem(item(localized("Open MonoHub"), symbol: "macwindow", action: #selector(openMainWindow)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, symbol: String, action: Selector?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = action == nil ? nil : self
        menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return menuItem
    }

    @objc private func openPanel() {
        showPanel()
    }

    @objc private func refreshNow() {
        Task { await QuotaManager.shared.refreshAll(force: true) }
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = MenuBarDisplayMode(rawValue: raw) else { return }
        QuotaPreferencesManager.shared.displayMode = mode
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func openMainWindow() {
        closePanel(animated: false)
        MainWindowController.shared.show(item: .dashboard)
    }
}
