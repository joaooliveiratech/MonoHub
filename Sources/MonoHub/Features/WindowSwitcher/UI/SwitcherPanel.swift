import AppKit
import SwiftUI

final class SwitcherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SwitcherPanelController: NSObject, NSWindowDelegate, SwitcherHotkeyManagerDelegate {
    static let shared = SwitcherPanelController()

    private static let idlePurgeDelay = Duration.seconds(90)

    let viewModel = SwitcherViewModel()

    private var panel: SwitcherPanel?
    private var hostingView: NSHostingView<SwitcherView>?
    private var screenObserver: (any NSObjectProtocol)?
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var purgeTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var isConfirmingSelection = false

    private override init() {
        super.init()
        viewModel.onPresentationChange = { [weak self] in
            self?.presentationDidChange()
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func loadPanel() -> SwitcherPanel {
        if let panel { return panel }

        let panel = SwitcherPanel()
        let hostingView = NSHostingView(
            rootView: SwitcherView(
                viewModel: viewModel,
                onConfirm: { SwitcherPanelController.shared.confirmSelection() },
                onCancel: { SwitcherPanelController.shared.hide() },
                onLayoutChange: { SwitcherPanelController.shared.layoutPanel() }
            )
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.cornerCurve = .continuous
        panel.contentView = hostingView
        panel.delegate = self

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                SwitcherPanelController.shared.screenParametersDidChange()
            }
        }

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func screenParametersDidChange() {
        if isVisible {
            layoutPanel()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if isVisible && !isConfirmingSelection {
            hide(restoringFocus: true)
        }
    }

    private func presentationDidChange() {
        guard isVisible else { return }
        syncOverlayState()
        layoutPanel()
    }

    func warmUp() {
        let panel = loadPanel()
        guard !panel.isVisible else { return }
        layoutPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func tearDown() {
        hide(restoringFocus: false)
        purgeTask?.cancel()
        purgeTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil
        stopOutsideClickMonitor()
        viewModel.releaseContent()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hostingView = nil
        previousApp = nil
        SwitcherHotkeyManager.shared.updateOverlayState(isVisible: false, isTextEntryActive: false)
    }

    func show(appOnly: Bool = false) {
        guard SwitcherFeature.isActive else {
            MainWindowController.shared.show(item: .windowSwitcher)
            return
        }

        purgeTask?.cancel()
        purgeTask = nil
        SwitcherPermissionsManager.shared.refresh()
        let panel = loadPanel()

        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != NSRunningApplication.current {
            previousApp = frontmost
        }
        if let screen = activeScreen() { updateAvailableSpace(for: screen) }
        viewModel.refreshWindows(appOnly: appOnly, targetPID: previousApp?.processIdentifier, screens: ScreenSnapshot.capture())
        layoutPanel()

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startOutsideClickMonitor()
        syncOverlayState()
        scheduleShadowUpdate()
    }

    func hide(restoringFocus: Bool = true) {
        guard let panel, panel.isVisible else { return }

        stopOutsideClickMonitor()
        viewModel.cancelPendingWork()
        panel.orderOut(nil)
        viewModel.resetTransientState()
        syncOverlayState()

        if restoringFocus, NSApp.isActive {
            previousApp?.activate()
        }
        prewarmCapture()
        scheduleIdlePurge()
    }

    func syncOverlayState() {
        let isVisible = self.isVisible
        let needsTextInput = isVisible && viewModel.isTextEntryActive
        SwitcherHotkeyManager.shared.updateOverlayState(isVisible: isVisible, isTextEntryActive: needsTextInput)

        if needsTextInput, !NSApp.isActive {
            NSApp.activate()
            panel?.makeKey()
        }
    }

    private func prewarmCapture() {
        guard SwitcherPermissionsManager.shared.hasScreenRecording, prewarmTask == nil else { return }
        prewarmTask = Task { [weak self] in
            await Task.detached(priority: .utility) {
                await SwitcherWindowManager.shared.prewarm()
            }.value
            self?.prewarmTask = nil
        }
    }

    private func scheduleIdlePurge() {
        purgeTask?.cancel()
        purgeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idlePurgeDelay, tolerance: .seconds(15))
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            self.purgeTask = nil
            self.viewModel.releaseContent()
            SwitcherWindowManager.shared.clearCache()
        }
    }

    private func scheduleShadowUpdate() {
        guard panel?.hasShadow == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel, panel.isVisible else { return }
                panel.invalidateShadow()
            }
        }
    }

    func perform(_ action: HotkeyAction) {
        defer { syncOverlayState() }
        if viewModel.pendingConfirmation != nil {
            switch action {
            case .confirm: viewModel.confirmPending()
            case .cancel: viewModel.cancelPending()
            default: break
            }
            return
        }

        switch action {
        case let .open(appOnly):
            show(appOnly: appOnly)
        case let .cycle(forward):
            if isVisible {
                viewModel.cycle(forward: forward)
            } else {
                show()
            }
        case .confirm:
            if viewModel.isHelpOpen {
                viewModel.closeHelp()
            } else {
                confirmSelection()
            }
        case .cancel:
            handleEscape()
        case let .navigate(direction):
            viewModel.navigate(direction: direction)
        case .enterSearch:
            viewModel.enterSearchMode()
        case .toggleHelp:
            viewModel.toggleHelp()
        case .togglePreview:
            guard viewModel.isPreviewOpen || viewModel.selectedWindow != nil else { return }
            viewModel.togglePreview()
        case .closeWindow:
            closeSelectedWindow()
        case .quitApp:
            quitSelectedApp()
        case .hideApp:
            withSelectedWindow { SwitcherWindowManager.shared.hideApplication(pid: $0.pid) }
        case .toggleMinimize:
            withSelectedWindow { SwitcherWindowManager.shared.toggleMinimize(window: $0) }
        case .toggleZoom:
            withSelectedWindow { SwitcherWindowManager.shared.toggleZoom(window: $0) }
        case let .tile(side):
            withSelectedWindow { SwitcherWindowManager.shared.tile(window: $0, side: side, screens: ScreenSnapshot.capture()) }
        case .moveToNextDisplay:
            withSelectedWindow { SwitcherWindowManager.shared.moveToNextDisplay(window: $0, screens: ScreenSnapshot.capture()) }
        case let .quickSelect(number):
            if viewModel.quickSelect(number: number) != nil {
                confirmSelection()
            }
        }
    }

    private func withSelectedWindow(_ body: (WindowInfo) -> Void) {
        guard let window = viewModel.selectedWindow else { return }
        body(window)
    }

    func handleEscape() {
        if !viewModel.handleDismiss() {
            hide()
        }
    }

    func confirmSelection() {
        guard !isConfirmingSelection else { return }
        isConfirmingSelection = true
        defer { isConfirmingSelection = false }

        let target = viewModel.selectedWindow
        hide(restoringFocus: target == nil)
        if let target {
            if NSApp.isActive, let app = NSRunningApplication(processIdentifier: target.pid) {
                NSApp.yieldActivation(to: app)
            }
            WindowActivationHistory.shared.record(window: target)
            SwitcherWindowManager.shared.focus(window: target)
        }
    }

    func confirm(_ confirmation: PendingConfirmation) {
        guard SwitcherPreferencesManager.shared.confirmDestructiveActions else {
            confirmation.perform()
            return
        }
        viewModel.pendingConfirmation = confirmation
    }

    func close(window: WindowInfo) {
        confirm(
            PendingConfirmation(
                title: localized("Close “%@”?", window.displayTitle),
                message: localized("The window of %@ will be closed. Unsaved changes may be lost.", window.appName),
                confirmTitle: localized("Close Window"),
                pid: window.pid
            ) {
                SwitcherWindowManager.shared.close(window: window)
                WindowActivationHistory.shared.forget(windowID: window.id)
                SwitcherPanelController.shared.viewModel.removeWindow(id: window.id)
            }
        )
    }

    func closeSelectedWindow() {
        withSelectedWindow { close(window: $0) }
    }

    func quitSelectedApp() {
        withSelectedWindow { window in
            confirm(
                PendingConfirmation(
                    title: localized("Quit %@?", window.appName),
                    message: localized("All windows of %@ will be closed.", window.appName),
                    confirmTitle: localized("Quit"),
                    pid: window.pid
                ) {
                    SwitcherWindowManager.shared.quitApplication(pid: window.pid)
                    WindowActivationHistory.shared.forget(pid: window.pid)
                    SwitcherPanelController.shared.viewModel.removeWindows(pid: window.pid)
                }
            )
        }
    }

    func layoutPanel() {
        guard let panel, let hostingView, let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let available = updateAvailableSpace(for: screen)

        let isFullscreen = SwitcherPreferencesManager.shared.isFullscreen
        panel.hasShadow = !isFullscreen
        hostingView.layer?.cornerRadius = isFullscreen ? 0 : SwitcherMetrics.panelCornerRadius

        let target: NSRect
        if isFullscreen {
            target = visible
        } else {
            let size = viewModel.floatingWindowSize
            target = centered(
                size: NSSize(width: min(size.width, available.width), height: min(size.height, available.height)),
                in: visible
            )
        }

        guard panel.frame != target else { return }
        panel.setFrame(target, display: panel.isVisible)
        if panel.isVisible { scheduleShadowUpdate() }
    }

    @discardableResult
    private func updateAvailableSpace(for screen: NSScreen) -> CGSize {
        let visible = screen.visibleFrame
        let margin = SwitcherMetrics.screenMargin
        let available = CGSize(width: visible.width - margin * 2, height: visible.height - margin * 2)
        if viewModel.availableSpace != available {
            viewModel.availableSpace = available
        }
        return available
    }

    private func centered(size: NSSize, in visible: NSRect) -> NSRect {
        NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    private func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if SwitcherPreferencesManager.shared.screenTarget == .activeWindow,
           let pid = previousApp?.processIdentifier,
           let window = viewModel.windows.first(where: { $0.pid == pid }),
           let index = ScreenSnapshot.capture().screenIndex(containingCoreGraphics: window.bounds),
           screens.indices.contains(index) {
            return screens[index]
        }

        let mouseLocation = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? screens.first
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}
