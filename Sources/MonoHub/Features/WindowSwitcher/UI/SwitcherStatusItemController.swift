import AppKit

final class SwitcherStatusItemController: NSObject {
    static let shared = SwitcherStatusItemController()

    private var statusItem: NSStatusItem?
    private var visibilityObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateLabels()
            }
        }
    }

    private func updateLabels() {
        statusItem?.button?.toolTip = localized("Window Switcher (MonoTab) — click to switch")
        statusItem?.button?.setAccessibilityLabel(localized("Window Switcher"))
    }

    func setVisible(_ visible: Bool) {
        guard visible else {
            visibilityObservation = nil
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MonoHubSwitcherStatusItem"
        item.behavior = .removalAllowed
        item.button?.image = Self.menuBarImage()
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = localized("Window Switcher (MonoTab) — click to switch")
        item.button?.setAccessibilityLabel(localized("Window Switcher"))
        item.isVisible = true

        visibilityObservation = item.observe(\.isVisible, options: [.new]) { _, change in
            guard let isVisible = change.newValue else { return }
            MainActor.assumeIsolated {
                if SwitcherPreferencesManager.shared.showMenuBarIcon != isVisible {
                    SwitcherPreferencesManager.shared.showMenuBarIcon = isVisible
                }
            }
        }

        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            SwitcherPanelController.shared.show()
            return
        }

        let isSecondary = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        guard isSecondary else {
            toggleSwitcher()
            return
        }

        guard let statusItem else { return }
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func toggleSwitcher() {
        let controller = SwitcherPanelController.shared
        if controller.isVisible {
            controller.hide()
        } else {
            controller.show()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let entries: [(title: String, selector: Selector, key: String)] = [
            (localized("Switch Windows…"), #selector(openSwitcher), "⇥"),
            (localized("Keyboard Shortcuts…"), #selector(openShortcuts), "?"),
            (localized("Switcher Settings…"), #selector(openPreferences), ",")
        ]

        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: entry.selector, keyEquivalent: entry.key)
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let permissions = NSMenuItem(
            title: localized("Accessibility Permissions…"),
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)

        let screenPerms = NSMenuItem(
            title: localized("Screen Recording Permission…"),
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenPerms.target = self
        menu.addItem(screenPerms)

        menu.addItem(.separator())

        let openHub = NSMenuItem(title: localized("Open %@", AppInfo.name), action: #selector(openHubApp), keyEquivalent: "")
        openHub.target = self
        menu.addItem(openHub)

        let quit = NSMenuItem(title: localized("Close Window"), action: #selector(closeWindow), keyEquivalent: "w")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let back = NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: 10.5, height: 8.5), xRadius: 2, yRadius: 2)
        back.lineWidth = 1.3
        back.stroke()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(
            roundedRect: NSRect(x: 5.2, y: 1.2, width: 12.1, height: 10.1),
            xRadius: 3,
            yRadius: 3
        ).fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let front = NSBezierPath(roundedRect: NSRect(x: 6, y: 2, width: 11, height: 9), xRadius: 2.5, yRadius: 2.5)
        front.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    @objc private func openSwitcher() {
        SwitcherPanelController.shared.show()
    }

    @objc private func openPreferences() {
        MainWindowController.shared.show(item: .windowSwitcher)
    }

    @objc private func openShortcuts() {
        let controller = SwitcherPanelController.shared
        if !controller.isVisible { controller.show() }
        controller.viewModel.isHelpOpen = true
    }

    @objc private func openAccessibilitySettings() {
        SwitcherPermissionsManager.shared.openSettings(for: .accessibility)
    }

    @objc private func openScreenRecordingSettings() {
        SwitcherPermissionsManager.shared.openSettings(for: .screenRecording)
    }

    @objc private func openHubApp() {
        MainWindowController.shared.show(item: .windowSwitcher)
    }

    @objc private func closeWindow() {
        if MainWindowController.shared.isWindowVisible {
            MainWindowController.shared.closeWindow()
        }
    }
}
