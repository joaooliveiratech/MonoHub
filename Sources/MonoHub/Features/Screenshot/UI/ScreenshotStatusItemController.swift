import AppKit

@MainActor
final class ScreenshotStatusItemController: NSObject, NSMenuDelegate {
    static let shared = ScreenshotStatusItemController()

    private var statusItem: NSStatusItem?

    private override init() {
        super.init()
    }

    func setVisible(_ visible: Bool) {
        guard visible else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MonoHubScreenshotStatusItem"
        item.button?.image = NSImage(systemSymbolName: ScreenshotStyle.symbol, accessibilityDescription: ShotText.statusItemLabel)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel(ShotText.statusItemLabel)

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let preferences = ScreenshotPreferences.shared
        for request in CaptureRequest.allCases {
            let shortcut = preferences.shortcut(for: request)
            let item = NSMenuItem(title: request.menuTitle, action: #selector(captureClicked(_:)), keyEquivalent: shortcut.menuKeyEquivalent)
            item.keyEquivalentModifierMask = shortcut.cocoaModifiers
            item.tag = Int(request.rawValue)
            item.image = MonoStyle.symbol(request.iconName)
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(ShotText.menuOpenImage, symbol: "photo.badge.plus", action: #selector(openImageClicked)))

        if !SwitcherPermissionsManager.shared.hasScreenRecording {
            menu.addItem(.separator())
            menu.addItem(makeItem(ShotText.menuScreenPermissions, symbol: "exclamationmark.triangle", action: #selector(permissionsClicked)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(ShotText.menuSettings, symbol: "gearshape", action: #selector(settingsClicked)))
        menu.addItem(makeItem(ShotText.menuOpenHub, symbol: "macwindow", action: #selector(openHubClicked)))
    }

    func menuWillOpen(_ menu: NSMenu) {
        SwitcherPermissionsManager.shared.refresh(force: true)
    }

    private func makeItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = MonoStyle.symbol(symbol)
        item.target = self
        return item
    }

    @objc private func captureClicked(_ sender: NSMenuItem) {
        guard let request = CaptureRequest(rawValue: UInt32(sender.tag)) else { return }
        ScreenshotController.shared.handleCaptureRequest(request)
    }

    @objc private func openImageClicked() {
        ScreenshotController.shared.presentOpenImagePanel()
    }

    @objc private func permissionsClicked() {
        SwitcherPermissionsManager.shared.openSettings(for: .screenRecording)
    }

    @objc private func settingsClicked() {
        MainWindowController.shared.show(item: .screenshot)
    }

    @objc private func openHubClicked() {
        MainWindowController.shared.show(item: .dashboard)
    }
}
