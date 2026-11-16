import AppKit
import Foundation

@MainActor
final class TileStatusItemController: NSObject, NSMenuDelegate {
    static let shared = TileStatusItemController()

    private var statusItem: NSStatusItem?
    private var accessibilityItems: [NSMenuItem] = []
    private var exclusionItems: [NSMenuItem] = []

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildMenu()
            }
        }
    }

    func setVisible(_ visible: Bool) {
        guard visible else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            accessibilityItems.removeAll()
            exclusionItems.removeAll()
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "MonoTile")
        item.menu = makeMenu()
        statusItem = item
    }

    func rebuildMenu() {
        guard let statusItem else { return }
        statusItem.menu = makeMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = TileAccessibilityManager.shared.isTrusted
        accessibilityItems.forEach { $0.isHidden = trusted }

        let app = WindowManager.shared.targetApplication()
        guard let bundleIdentifier = app?.bundleIdentifier, let name = app?.localizedName else {
            exclusionItems.forEach { $0.isHidden = true }
            return
        }
        exclusionItems.forEach { $0.isHidden = false }
        if let item = exclusionItems.first {
            item.title = localized("Ignore “%@”", name)
            item.representedObject = bundleIdentifier
            item.state = TilePreferencesManager.shared.isExcluded(bundleIdentifier: bundleIdentifier) ? .on : .off
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let accessibilityItem = item(localized("Allow Accessibility Access…"), symbol: "exclamationmark.triangle", action: #selector(openAccessibility))
        accessibilityItems = [accessibilityItem, .separator()]
        accessibilityItems.forEach(menu.addItem)

        for category in ActionCategory.allCases where !category.showsAsSubmenu {
            category.actions.forEach { menu.addItem(item(for: $0)) }
            menu.addItem(.separator())
        }

        for category in ActionCategory.allCases where category.showsAsSubmenu {
            let submenu = NSMenu()
            category.actions.forEach { submenu.addItem(item(for: $0)) }
            let categoryItem = item(category.title, symbol: category.sfSymbol, action: nil)
            categoryItem.submenu = submenu
            menu.addItem(categoryItem)
        }
        menu.addItem(.separator())

        exclusionItems = [item(localized("Ignore App"), symbol: nil, action: #selector(toggleExclusion(_:))), .separator()]
        exclusionItems.forEach(menu.addItem)

        menu.addItem(item(localized("MonoHub Settings…"), symbol: "gearshape", action: #selector(openSettings), key: ","))
        return menu
    }

    private func item(_ title: String, symbol: String?, action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func item(for action: WindowAction) -> NSMenuItem {
        let item = item(action.displayName, symbol: action.sfSymbol, action: #selector(handleAction(_:)))
        item.representedObject = action
        if let shortcut = TilePreferencesManager.shared.shortcut(for: action) {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifiers.nsEventModifiers
        }
        return item
    }

    @objc private func handleAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? WindowAction else { return }
        WindowManager.shared.perform(action: action)
    }

    @objc private func toggleExclusion(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else { return }
        TilePreferencesManager.shared.setExcluded(sender.state != .on, bundleIdentifier: bundleIdentifier)
    }

    @objc private func openSettings() {
        MainWindowController.shared.show(item: .windowTiling)
    }

    @objc private func openAccessibility() {
        TileAccessibilityManager.shared.openSystemSettings()
    }
}
