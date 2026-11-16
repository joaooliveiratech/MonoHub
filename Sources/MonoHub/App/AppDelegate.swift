import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var isExplicitTermination = false
    private var isSystemShuttingDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferencesManager.shared.applyTheme()
        setupMainMenu()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSystemShuttingDown = true
            }
        }

        FeatureManager.shared.startEnabledFeatures()

        MainWindowController.shared.show(item: .dashboard)
    }

    func applicationWillTerminate(_ notification: Notification) {
        FeatureManager.shared.stopAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isExplicitTermination || isSystemShuttingDown || !PreferencesManager.shared.keepRunningInBackgroundOnQuit {
            return .terminateNow
        }

        closeToBackground()
        return .terminateCancel
    }

    @objc func handleQuitMenu() {
        if PreferencesManager.shared.keepRunningInBackgroundOnQuit {
            closeToBackground()
        } else {
            forceTerminate()
        }
    }

    @objc func closeToBackground() {
        if MainWindowController.shared.isWindowVisible {
            MainWindowController.shared.closeWindow()
        } else {
            MainWindowController.shared.updateActivationPolicy()
        }
    }

    @objc func forceTerminate() {
        isExplicitTermination = true
        NSApp.terminate(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let features = FeatureManager.shared
        let imageFiles = urls.filter(\.isFileURL)
        if !imageFiles.isEmpty {
            if features.isEnabled(.screenshot) {
                ScreenshotController.shared.openImageFiles(imageFiles)
            } else {
                MainWindowController.shared.show(item: .screenshot)
            }
        }
        for url in urls where !url.isFileURL {
            let isSettings = url.host == "settings" || url.path.contains("settings")

            if url.scheme == "monotab" || url.host == "switcher" || url.host == "monotab" {
                if isSettings || !features.isEnabled(.windowSwitcher) {
                    MainWindowController.shared.show(item: .windowSwitcher)
                } else {
                    SwitcherPanelController.shared.show()
                }
                continue
            }

            if url.scheme == "mononotch" || url.host == "notch" || url.host == "mononotch" {
                if isSettings || !features.isEnabled(.dynamicNotch) {
                    MainWindowController.shared.show(item: .notch)
                } else {
                    NotchWindowController.shared.toggleExpanded()
                }
                continue
            }

            if url.scheme == "monoshot" || url.host == "screenshot" || url.host == "monoshot" {
                let candidates = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
                    .compactMap { $0?.lowercased() }
                let request = CaptureRequest.allCases.first { candidates.contains($0.urlCommand) }
                if let request, features.isEnabled(.screenshot) {
                    ScreenshotController.shared.handleCaptureRequest(request)
                } else {
                    MainWindowController.shared.show(item: .screenshot)
                }
                continue
            }

            if url.scheme == "monoaibar" || url.host == "aiquota" || url.host == "monoaibar" {
                if isSettings || !features.isEnabled(.aiQuota) {
                    MainWindowController.shared.show(item: .aiQuota)
                } else {
                    AIQuotaStatusItemController.shared.togglePanel()
                }
                continue
            }

            if let command = TileURLCommand(url: url) {
                switch command {
                case .settings:
                    MainWindowController.shared.show(item: .windowTiling)
                case .perform(let action):
                    if features.isEnabled(.windowTiling) {
                        WindowManager.shared.perform(action: action)
                    } else {
                        MainWindowController.shared.show(item: .windowTiling)
                    }
                }
                continue
            }

            if url.scheme == "http" || url.scheme == "https" {
                if features.isEnabled(.productivity) {
                    URLRouterService.shared.openURL(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
                continue
            }

            if url.scheme == "monoroute" || url.host == "urlrouter" || url.host == "router" {
                MainWindowController.shared.show(item: .urlRouter)
                continue
            }

            if url.scheme == "monosnippet" || url.host == "snippets" {
                MainWindowController.shared.show(item: .snippets)
                continue
            }

            if url.scheme == "monobluetooth" || url.host == "bluetooth" {
                if isSettings || !features.isEnabled(.productivity) {
                    MainWindowController.shared.show(item: .bluetoothQuickConnect)
                } else {
                    BluetoothQuickConnectManager.shared.toggleQuickConnection()
                }
                continue
            }

            if url.scheme == "monohub" {
                MainWindowController.shared.show(item: isSettings ? .settings : nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: String(format: localized("About %@"), AppInfo.name), action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefsItem = NSMenuItem(title: localized("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        let modulesItem = NSMenuItem(title: localized("Modules…"), action: #selector(openModules), keyEquivalent: "")
        modulesItem.target = self
        appMenu.addItem(modulesItem)
        let menuBarItem = NSMenuItem(title: localized("Configure Menu Bar…"), action: #selector(openMenuBarSettings), keyEquivalent: "")
        menuBarItem.target = self
        appMenu.addItem(menuBarItem)
        let notchItem = NSMenuItem(title: localized("Dynamic Notch…"), action: #selector(openNotch), keyEquivalent: "")
        notchItem.target = self
        appMenu.addItem(notchItem)
        let switcherItem = NSMenuItem(title: localized("Window Switcher…"), action: #selector(openWindowSwitcher), keyEquivalent: "")
        switcherItem.target = self
        appMenu.addItem(switcherItem)
        let tilingItem = NSMenuItem(title: localized("Window Tiling…"), action: #selector(openWindowTiling), keyEquivalent: "")
        tilingItem.target = self
        appMenu.addItem(tilingItem)
        let screenshotItem = NSMenuItem(title: localized("Screenshots…"), action: #selector(openScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        appMenu.addItem(screenshotItem)
        let aiQuotaItem = NSMenuItem(title: localized("AI Quotas…"), action: #selector(openAIQuota), keyEquivalent: "")
        aiQuotaItem.target = self
        appMenu.addItem(aiQuotaItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(format: localized("Hide %@"), AppInfo.name), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: localized("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: localized("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: localized("Close Window (Keep in Background)"), action: #selector(handleQuitMenu), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let forceQuitItem = NSMenuItem(title: String(format: localized("Quit %@ Definitively"), AppInfo.name), action: #selector(forceTerminate), keyEquivalent: "q")
        forceQuitItem.keyEquivalentModifierMask = [.command, .option]
        forceQuitItem.target = self
        appMenu.addItem(forceQuitItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: localized("Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: localized("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: localized("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: localized("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: localized("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: localized("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: localized("Delete"), action: #selector(CanvasView.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: localized("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        mainMenu.addItem(ScreenshotMenu.makeMenuItem(captureTarget: self, captureActions: [
            .area: #selector(captureArea),
            .fullscreen: #selector(captureFullscreen),
            .window: #selector(captureWindow),
            .textRecognition: #selector(captureText),
            .scrolling: #selector(captureScrolling),
            .screenRecord: #selector(recordScreen)
        ]))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: localized("Window"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: localized("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: localized("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: localized("Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: localized("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func openAbout() {
        MainWindowController.shared.show(item: .settings)
    }

    @objc private func openSettings() {
        MainWindowController.shared.show(item: .settings)
    }

    @objc private func openModules() {
        MainWindowController.shared.show(item: .modules)
    }

    @objc private func openMenuBarSettings() {
        MainWindowController.shared.show(item: .menuBar)
    }

    @objc private func openNotch() {
        MainWindowController.shared.show(item: .notch)
    }

    @objc private func openWindowSwitcher() {
        MainWindowController.shared.show(item: .windowSwitcher)
    }

    @objc private func openWindowTiling() {
        MainWindowController.shared.show(item: .windowTiling)
    }

    @objc private func openScreenshot() {
        MainWindowController.shared.show(item: .screenshot)
    }

    @objc private func captureArea() {
        ScreenshotController.shared.handleCaptureRequest(.area)
    }

    @objc private func captureFullscreen() {
        ScreenshotController.shared.handleCaptureRequest(.fullscreen)
    }

    @objc private func captureWindow() {
        ScreenshotController.shared.handleCaptureRequest(.window)
    }

    @objc private func captureText() {
        ScreenshotController.shared.handleCaptureRequest(.textRecognition)
    }

    @objc private func captureScrolling() {
        ScreenshotController.shared.handleCaptureRequest(.scrolling)
    }

    @objc private func recordScreen() {
        ScreenshotController.shared.handleCaptureRequest(.screenRecord)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(captureArea),
             #selector(captureFullscreen),
             #selector(captureWindow),
             #selector(captureText),
             #selector(captureScrolling),
             #selector(recordScreen):
            return FeatureManager.shared.isEnabled(.screenshot)
        default:
            return true
        }
    }

    @objc private func openAIQuota() {
        MainWindowController.shared.show(item: .aiQuota)
    }
}
