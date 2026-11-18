import AppKit
import SwiftUI
import Observation
import Combine

final class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        NotchWindowController.shared.navigationGraceUntil = nil
        withAnimation(NotchTheme.collapse) {
            NotchWindowController.shared.isExpanded = false
        }
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var hitTester: ((NSPoint) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hitTester = hitTester, !hitTester(point) {
            return nil
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@Observable
@MainActor
final class NotchWindowController {
    static let shared = NotchWindowController()

    var expandedScreens: Set<String> = [] {
        didSet {
            if expandedScreens.isEmpty != oldValue.isEmpty {
                IdleInteractionMonitor.shared.syncRenderTimer()
            }
        }
    }
    var navigationGraceUntil: Date?
    var previousExpandedHeight: CGFloat = 0
    var isMenuTracking: Bool = false
    private(set) var isDisplayAsleep: Bool = false

    func recordNavigationFromExpanded(previousHeight: CGFloat) {
        navigationGraceUntil = Date().addingTimeInterval(3.5)
        previousExpandedHeight = previousHeight
    }

    var isExpanded: Bool {
        get { !expandedScreens.isEmpty }
        set {
            if newValue {
                expandedScreens.formUnion(windows.keys)
            } else {
                expandedScreens.removeAll()
            }
        }
    }

    @ObservationIgnored private var windows: [String: NotchPanel] = [:]
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var menuBeginObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var menuEndObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var sleepObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var localScrollMonitor: Any?
    @ObservationIgnored private var globalScrollMonitor: Any?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchWindowController.shared.refreshWindows()
            }
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchWindowController.shared.handleScreenSleep(true)
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchWindowController.shared.handleScreenSleep(false)
            }
        }

        menuBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchWindowController.shared.isMenuTracking = true
                NotchWindowController.shared.navigationGraceUntil = Date().addingTimeInterval(5.0)
            }
        }

        menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchWindowController.shared.isMenuTracking = false
                NotchWindowController.shared.navigationGraceUntil = Date().addingTimeInterval(2.0)
            }
        }

        AppExclusionManager.shared.onSuppressionChange = { suppressed in
            NotchWindowController.shared.handleSuppressionChange(suppressed)
        }

        layoutTask = Task { [weak self] in
            let stream = Observations { @MainActor in
                let prefs = NotchPreferences.shared
                return NotchWindowLayout(
                    displayTargetMode: prefs.displayTargetMode,
                    customEnabledDisplayIDs: prefs.customEnabledDisplayIDs,
                    enableVirtualNotch: prefs.enableVirtualNotch,
                    openNotchWidth: prefs.openNotchWidth,
                    openNotchHeight: prefs.openNotchHeight
                )
            }
            for await _ in stream {
                guard let self, self.isRunning, !Task.isCancelled else { break }
                self.refreshWindows()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        layoutTask?.cancel()
        layoutTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let menuBeginObserver {
            NotificationCenter.default.removeObserver(menuBeginObserver)
            self.menuBeginObserver = nil
        }
        if let menuEndObserver {
            NotificationCenter.default.removeObserver(menuEndObserver)
            self.menuEndObserver = nil
        }
        AppExclusionManager.shared.onSuppressionChange = nil
        setScrollMonitoring(false)
        expandedScreens.removeAll()
        for panel in windows.values {
            panel.contentView = nil
            panel.close()
        }
        windows.removeAll()
    }

    private func handleScreenSleep(_ asleep: Bool) {
        isDisplayAsleep = asleep
        if asleep {
            expandedScreens.removeAll()
            IdleInteractionMonitor.shared.stop()
            for panel in windows.values {
                panel.orderOut(nil)
            }
        } else if !AppExclusionManager.shared.isSuppressed {
            if NotchFeature.isRunning, NotchPreferences.shared.idleAnimation != .none {
                IdleInteractionMonitor.shared.ensureStarted()
            }
            refreshWindows()
        }
        SystemMonitorEngine.shared.reloadConfiguration()
    }

    func setScrollMonitoring(_ enabled: Bool) {
        if enabled {
            guard isRunning, globalScrollMonitor == nil, localScrollMonitor == nil else { return }
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
                guard !NotchWindowController.shared.isDisplayAsleep, !AppExclusionManager.shared.isSuppressed else { return }
                let location = NSEvent.mouseLocation
                let topBands = DisplayManager.shared.topBandFrames
                if !topBands.isEmpty {
                    guard topBands.contains(where: { $0.contains(location) }) else { return }
                } else {
                    guard NSScreen.screens.contains(where: { location.y >= $0.frame.maxY - 90 && $0.frame.minX <= location.x && location.x <= $0.frame.maxX }) else { return }
                }
                let deltaY = event.scrollingDeltaY
                MainActor.assumeIsolated {
                    _ = NotchWindowController.shared.processScroll(deltaY: deltaY, at: location)
                }
            }
            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard !NotchWindowController.shared.isDisplayAsleep, !AppExclusionManager.shared.isSuppressed else { return event }
                let location = NSEvent.mouseLocation
                let topBands = DisplayManager.shared.topBandFrames
                if !topBands.isEmpty {
                    guard topBands.contains(where: { $0.contains(location) }) else { return event }
                } else {
                    guard NSScreen.screens.contains(where: { location.y >= $0.frame.maxY - 90 && $0.frame.minX <= location.x && location.x <= $0.frame.maxX }) else { return event }
                }
                return NotchWindowController.shared.processScroll(deltaY: event.scrollingDeltaY, at: location) ? nil : event
            }
        } else {
            if let globalScrollMonitor {
                NSEvent.removeMonitor(globalScrollMonitor)
                self.globalScrollMonitor = nil
            }
            if let localScrollMonitor {
                NSEvent.removeMonitor(localScrollMonitor)
                self.localScrollMonitor = nil
            }
        }
    }

    @discardableResult
    private func processScroll(deltaY: CGFloat, at mouseLoc: NSPoint) -> Bool {
        let action = NotchPreferences.shared.scrollAction
        guard action != .disabled, abs(deltaY) > 0.05, !windows.isEmpty else { return false }

        for screen in NSScreen.screens where mouseLoc.y >= screen.frame.maxY - 80 && screen.frame.minX <= mouseLoc.x && mouseLoc.x <= screen.frame.maxX {
            let screenID = DisplayManager.shared.screenIdentifier(for: screen)
            guard windows[screenID] != nil, !expandedScreens.contains(screenID) else { continue }

            let geom = DisplayManager.calculateGeometry(for: screen, preferences: NotchPreferences.shared)
            let metrics = LiveActivityCenter.shared.metrics(for: geom)
            var activeRect = CGRect(
                x: screen.frame.midX - metrics.width / 2,
                y: screen.frame.maxY - metrics.height,
                width: metrics.width,
                height: metrics.height
            ).insetBy(dx: -14, dy: -8)
            if metrics.hasBubble {
                let bubbleW = metrics.hasAnimationBubble ? metrics.animationBubbleWidth : metrics.bubbleDiameter
                activeRect.size.width += bubbleW + metrics.bubbleSpacing + 10
            }
            guard activeRect.contains(mouseLoc) else { continue }

            let step: Float = 0.02
            switch action {
            case .adjustVolume:
                if deltaY > 0 {
                    AudioVolumeManager.shared.increaseVolume(step: step)
                } else {
                    AudioVolumeManager.shared.decreaseVolume(step: step)
                }
                return true
            case .adjustBrightness:
                if deltaY > 0 {
                    DisplayBrightnessManager.shared.increaseBrightness(step: step)
                } else {
                    DisplayBrightnessManager.shared.decreaseBrightness(step: step)
                }
                return true
            case .disabled:
                return false
            }
        }
        return false
    }

    private func handleSuppressionChange(_ suppressed: Bool) {
        if suppressed {
            expandedScreens.removeAll()
            IdleInteractionMonitor.shared.stop()
            for panel in windows.values {
                panel.orderOut(nil)
            }
        } else {
            if !isDisplayAsleep, NotchFeature.isRunning, NotchPreferences.shared.idleAnimation != .none {
                IdleInteractionMonitor.shared.ensureStarted()
            }
            for panel in windows.values {
                panel.orderFrontRegardless()
            }
        }
        SystemMonitorEngine.shared.reloadConfiguration()
    }

    func refreshWindows() {
        guard isRunning else { return }
        let screens = NSScreen.screens
        let display = DisplayManager.shared
        let enabledScreens = screens.filter { display.isScreenEnabled($0) }
        let enabledIDs = Set(enabledScreens.map { display.screenIdentifier(for: $0) })

        for (screenID, panel) in windows where !enabledIDs.contains(screenID) {
            panel.contentView = nil
            panel.close()
            windows.removeValue(forKey: screenID)
            expandedScreens.remove(screenID)
        }

        let prefs = NotchPreferences.shared
        let canvasWidth = max(prefs.openNotchWidth + 100, 740)
        let canvasHeight: CGFloat = max(prefs.openNotchHeight + 80, 520)
        let suppressed = AppExclusionManager.shared.isSuppressed

        for screen in enabledScreens {
            let screenID = display.screenIdentifier(for: screen)
            let windowFrame = CGRect(
                x: screen.frame.midX - (canvasWidth / 2),
                y: screen.frame.maxY - canvasHeight,
                width: canvasWidth,
                height: canvasHeight
            )

            let panel = windows[screenID] ?? makePanel(for: screen, screenID: screenID, frame: windowFrame)
            windows[screenID] = panel
            if panel.frame != windowFrame {
                panel.setFrame(windowFrame, display: true)
            }
            if suppressed {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    private func makePanel(for screen: NSScreen, screenID: String, frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let isExpandedBinding = Binding<Bool>(
            get: { NotchWindowController.shared.expandedScreens.contains(screenID) },
            set: { newValue in
                if newValue {
                    NotchWindowController.shared.expandedScreens.insert(screenID)
                } else {
                    NotchWindowController.shared.expandedScreens.remove(screenID)
                }
            }
        )

        let hostingView = NotchHostingView(rootView: NotchContainerView(screen: screen, isExpanded: isExpandedBinding))
        hostingView.hitTester = { [weak hostingView, weak screen] point in
            guard let hostingView, let screen, !AppExclusionManager.shared.isSuppressed else { return false }
            return NotchWindowController.hitTest(point: point, in: hostingView.bounds.size, screen: screen, screenID: screenID)
        }
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)
        return panel
    }

    private static func hitTest(point: NSPoint, in canvas: CGSize, screen: NSScreen, screenID: String) -> Bool {
        let prefs = NotchPreferences.shared
        let isExpanded = NotchWindowController.shared.expandedScreens.contains(screenID)
        let geometry = DisplayManager.calculateGeometry(for: screen, preferences: prefs)
        let metrics = LiveActivityCenter.shared.metrics(for: geometry)
        let earRadius = isExpanded ? NotchTheme.expandedEarRadius : (geometry.hasHardwareNotch ? prefs.closedTopCornerRadius : 0)
        let width = (isExpanded ? prefs.openNotchWidth : metrics.width) + earRadius * 2
        let tabHeight = prefs.effectiveExpandedHeight(for: prefs.resolvedActiveTab, headerHeight: geometry.expandedHeaderHeight)
        let effectiveHeight: CGFloat = {
            if isExpanded {
                if let graceUntil = NotchWindowController.shared.navigationGraceUntil, Date() < graceUntil {
                    return max(tabHeight, NotchWindowController.shared.previousExpandedHeight)
                }
                return tabHeight
            }
            return metrics.height
        }()
        let height = effectiveHeight
        let notchX = (canvas.width - width) / 2
        let notchY = canvas.height - height
        let notchRect = NSRect(x: notchX, y: notchY, width: width, height: height)

        if isExpanded {
            return notchRect.insetBy(dx: -6, dy: -6).contains(point)
        }
        if notchRect.insetBy(dx: -8, dy: -4).contains(point) {
            return true
        }
        guard metrics.hasBubble else { return false }
        let bubbleW = metrics.hasAnimationBubble ? metrics.animationBubbleWidth : metrics.bubbleDiameter
        let bubbleRect = NSRect(
            x: notchX + width + metrics.bubbleSpacing,
            y: canvas.height - metrics.baseHeight,
            width: bubbleW,
            height: metrics.bubbleDiameter
        ).insetBy(dx: -4, dy: -4)
        return bubbleRect.contains(point)
    }

    func toggleExpanded(on screenID: String? = nil) {
        let willExpand: Bool = {
            if let screenID { return !expandedScreens.contains(screenID) }
            return expandedScreens.isEmpty
        }()
        if !willExpand {
            navigationGraceUntil = nil
        }
        withAnimation(willExpand ? NotchTheme.expand : NotchTheme.collapse) {
            if let screenID {
                if expandedScreens.contains(screenID) {
                    expandedScreens.remove(screenID)
                } else {
                    expandedScreens.insert(screenID)
                }
            } else if expandedScreens.isEmpty {
                expandedScreens.formUnion(windows.keys)
            } else {
                expandedScreens.removeAll()
            }
        }
    }
}

private nonisolated struct NotchWindowLayout: Equatable, Sendable {
    let displayTargetMode: DisplayTargetMode
    let customEnabledDisplayIDs: [String]
    let enableVirtualNotch: Bool
    let openNotchWidth: CGFloat
    let openNotchHeight: CGFloat
}
