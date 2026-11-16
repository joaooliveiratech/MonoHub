import AppKit
import SwiftUI

@MainActor
final class NotchStatusItemController: NSObject, NSMenuDelegate {
    static let shared = NotchStatusItemController()

    private var statusItem: NSStatusItem?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .appLanguageDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateLocalization()
            }
        }
    }

    private func updateLocalization() {
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: localized("Dynamic Notch"))
            button.image?.isTemplate = true
            button.toolTip = localized("Dynamic Notch")
        }
    }

    var isVisible: Bool { statusItem != nil }

    func setVisible(_ visible: Bool) {
        if visible {
            installStatusItem()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MonoHubNotchStatusItem"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: localized("Dynamic Notch"))
            button.image?.isTemplate = true
            button.toolTip = localized("Dynamic Notch")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = NotchPreferences.shared
        let isExpanded = NotchWindowController.shared.isExpanded

        let toggleItem = NSMenuItem(
            title: isExpanded ? localized("Collapse notch") : localized("Expand notch"),
            action: #selector(toggleNotchAction),
            keyEquivalent: "n"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let tabsSubmenu = NSMenu()
        for tab in prefs.availableTabs {
            let item = NSMenuItem(title: tab.title, action: #selector(switchTabAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            item.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: nil)
            item.state = tab == prefs.resolvedActiveTab ? .on : .off
            tabsSubmenu.addItem(item)
        }
        let tabsItem = NSMenuItem(title: localized("Open module"), action: nil, keyEquivalent: "")
        tabsItem.submenu = tabsSubmenu
        menu.addItem(tabsItem)

        if prefs.enableMirrorModule {
            let mirrorItem = NSMenuItem(title: localized("Open camera mirror"), action: #selector(openMirrorAction), keyEquivalent: "m")
            mirrorItem.target = self
            mirrorItem.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)
            menu.addItem(mirrorItem)
        }

        if prefs.enableClipboardModule {
            let clipboardItem = NSMenuItem(title: localized("Clipboard…"), action: #selector(openClipboardAction), keyEquivalent: "c")
            clipboardItem.target = self
            clipboardItem.image = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil)
            menu.addItem(clipboardItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: localized("Notch Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
    }

    @objc func toggleNotchAction() {
        NotchWindowController.shared.toggleExpanded()
    }

    @objc private func switchTabAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = NotchTab(rawValue: raw) else { return }
        NotchPreferences.shared.selectTab(tab)
        NotchWindowController.shared.isExpanded = true
    }

    @objc private func openMirrorAction() {
        guard NotchPreferences.shared.enableMirrorModule else { return }
        NotchPreferences.shared.selectTab(.mirror)
        NotchWindowController.shared.isExpanded = true
    }

    @objc private func openClipboardAction() {
        guard NotchPreferences.shared.enableClipboardModule else { return }
        NotchPreferences.shared.selectTab(.clipboard)
        NotchWindowController.shared.isExpanded = true
    }

    @objc func openSettingsAction() {
        Self.openSettings()
    }

    static func openSettings() {
        NotchWindowController.shared.isExpanded = false
        MainWindowController.shared.show(item: .notch)
    }
}
