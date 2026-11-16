import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class HubNavigation {
    static let shared = HubNavigation()

    var selectedItem: SidebarItem = .dashboard

    private init() {}

    func select(_ item: SidebarItem) {
        selectedItem = item
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var occlusionObserver: (any NSObjectProtocol)?

    private override init() {
        super.init()
    }

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    func show(item: SidebarItem? = nil) {
        if let item {
            HubNavigation.shared.select(item)
        }

        let switchedPolicy = NSApp.activationPolicy() != .regular
        if switchedPolicy {
            NSApp.setActivationPolicy(.regular)
        }

        if let window {
            bringToFront(window, delayForPolicyChange: switchedPolicy)
            return
        }

        let hosting = NSHostingController(rootView: MainWindowView())
        hosting.sceneBridgingOptions = [.toolbars, .title]
        hosting.sizingOptions = []

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = AppInfo.name
        newWindow.contentViewController = hosting
        newWindow.setContentSize(NSSize(width: 1060, height: 700))
        newWindow.minSize = NSSize(width: 720, height: 480)
        newWindow.toolbarStyle = .unified
        newWindow.collectionBehavior = [.fullScreenPrimary, .managed, .moveToActiveSpace]
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        newWindow.setFrameAutosaveName("MonoHubMainWindow")

        window = newWindow
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: newWindow,
            queue: .main
        ) { [weak newWindow] _ in
            MainActor.assumeIsolated {
                let visible = newWindow?.occlusionState.contains(.visible) ?? true
                SystemMonitorEngine.shared.setWindowVisible(visible)
            }
        }
        bringToFront(newWindow, delayForPolicyChange: true)
    }

    private func bringToFront(_ targetWindow: NSWindow, delayForPolicyChange: Bool) {
        if targetWindow.isMiniaturized {
            targetWindow.deminiaturize(nil)
        }
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        targetWindow.orderFrontRegardless()
        targetWindow.makeKeyAndOrderFront(nil)
        targetWindow.makeMain()

        if delayForPolicyChange {
            DispatchQueue.main.async { [weak targetWindow] in
                MainActor.assumeIsolated {
                    guard let targetWindow else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                    targetWindow.orderFrontRegardless()
                    targetWindow.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    func closeWindow() {
        if let window {
            window.performClose(nil)
        } else {
            updateActivationPolicy()
        }
    }

    func updateActivationPolicy() {
        if isWindowVisible || ScreenshotController.shared.hasOpenEditors {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else if shouldStayInBackground {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    private var shouldStayInBackground: Bool {
        PreferencesManager.shared.keepRunningInBackgroundOnQuit
            || HubFeature.allCases.contains { $0.runsInBackground && FeatureManager.shared.isEnabled($0) }
    }

    func windowWillClose(_ notification: Notification) {
        SystemMonitorEngine.shared.stopAllWindowMonitoring()
        SystemMonitorEngine.shared.setWindowVisible(true)
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        window = nil
        if shouldStayInBackground {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if !MainWindowController.shared.isWindowVisible, !ScreenshotController.shared.hasOpenEditors {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
    }
}
