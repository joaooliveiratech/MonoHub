import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Observation

private typealias TileAXWindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private nonisolated let tileAXWindowIDSymbol: TileAXWindowIDFunction? = {
    guard let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2),
          let symbol = dlsym(defaultHandle, "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(symbol, to: TileAXWindowIDFunction.self)
}()

private nonisolated func tileAXWindowID(of element: AXUIElement) -> CGWindowID? {
    guard let tileAXWindowIDSymbol else { return nil }
    var id: CGWindowID = 0
    guard tileAXWindowIDSymbol(element, &id) == .success, id > 0 else { return nil }
    return id
}

private nonisolated func activeAppFocusObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    MainActor.assumeIsolated {
        WindowManager.shared.handleActiveAppWindowFocusChanged()
    }
}

@MainActor
@Observable
final class WindowManager {
    static let shared = WindowManager()

    private struct RestorePoint {
        let original: CGRect
        var applied: CGRect
    }

    private enum RestoreKey: Hashable {
        case windowID(CGWindowID)
        case element(AXUIElement)
    }

    struct WindowInspection {
        let windowID: CGWindowID?
        let pid: pid_t
        let frame: CGRect
        let subrole: String?
        let isFullScreen: Bool
    }

    private static let ignoredSubroles: Set<String> = [kAXSystemDialogSubrole, kAXSystemFloatingWindowSubrole]
    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
    private static let inspectionAttributes = [
        kAXPositionAttribute,
        kAXSizeAttribute,
        kAXSubroleAttribute,
        "AXFullScreen"
    ] as CFArray

    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier
    @ObservationIgnored private let systemWideElement = AXUIElementCreateSystemWide()
    @ObservationIgnored private let maxRestoreHistory = 50
    @ObservationIgnored private let cycleInterval: TimeInterval = 1.3
    @ObservationIgnored private let axMessagingTimeout: Float = 0.25

    @ObservationIgnored private var appElementCache: [pid_t: AXUIElement] = [:]
    @ObservationIgnored private var restorePoints: [RestoreKey: RestorePoint] = [:]
    @ObservationIgnored private var restoreOrder: [RestoreKey] = []
    @ObservationIgnored private var lastAction: WindowAction?
    @ObservationIgnored private var lastActionWindowKey: RestoreKey?
    @ObservationIgnored private var lastActionScreen: ScreenLayout?
    @ObservationIgnored private var lastActionTime: Date = .distantPast
    @ObservationIgnored private var cycleCount = 0
    @ObservationIgnored private var lastActiveApp: NSRunningApplication?

    @ObservationIgnored private var cachedScreenLayouts: [ScreenLayout] = []
    @ObservationIgnored private(set) var primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var activeAXObserver: AXObserver?
    @ObservationIgnored private var activeAXObserverPID: pid_t = 0
    @ObservationIgnored private var focusQueue = FocusQueue()
    @ObservationIgnored private var queueCommitTask: Task<Void, Never>?

    /// Published snapshot for the Settings UI live focus queue preview (updated lazily when window is visible).
    private(set) var focusQueuePreview: [FocusWindowRef] = []

    private init() {
        AXUIElementSetMessagingTimeout(systemWideElement, axMessagingTimeout)
    }

    private func appElement(for pid: pid_t) -> AXUIElement {
        if let cached = appElementCache[pid] {
            return cached
        }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        if appElementCache.count > 96 {
            appElementCache.removeAll(keepingCapacity: true)
        }
        appElementCache[pid] = element
        return element
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        let ownPID = self.ownPID
        rebuildScreenLayoutCache()

        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ownPID,
           app.activationPolicy == .regular {
            lastActiveApp = app
        }

        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                let isRegular = app.activationPolicy == .regular
                MainActor.assumeIsolated {
                    let manager = WindowManager.shared
                    if pid != ownPID && isRegular {
                        manager.lastActiveApp = app
                    }
                    manager.attachFocusObserver(to: pid)
                    manager.recordCurrentFocusedWindow()
                }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated {
                    let manager = WindowManager.shared
                    manager.appElementCache.removeValue(forKey: pid)
                    manager.focusQueue.remove(pid: pid)
                    TilePreferencesManager.shared.invalidateProcessCache(pid: pid)
                    if manager.activeAXObserverPID == pid {
                        manager.detachFocusObserver()
                    }
                    manager.publishFocusQueuePreviewIfVisible()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    WindowManager.shared.rebuildScreenLayoutCache()
                }
            }
        ]

        if let front = NSWorkspace.shared.frontmostApplication {
            attachFocusObserver(to: front.processIdentifier)
        }
        seedFocusQueueFromCurrentWindows()
    }

    func stopObserving() {
        guard !observers.isEmpty else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observers[0])
        NSWorkspace.shared.notificationCenter.removeObserver(observers[1])
        NotificationCenter.default.removeObserver(observers[2])
        observers.removeAll()
        detachFocusObserver()
        queueCommitTask?.cancel()
        queueCommitTask = nil
        appElementCache.removeAll()
        cachedScreenLayouts.removeAll()
        lastActiveApp = nil
        restorePoints.removeAll()
        restoreOrder.removeAll()
        focusQueue.clear()
        focusQueuePreview = []
        resetCycle()
    }

    func refreshFocusObserverIfNeeded() {
        guard !observers.isEmpty, AXIsProcessTrusted() else { return }
        if activeAXObserver == nil, let front = NSWorkspace.shared.frontmostApplication {
            attachFocusObserver(to: front.processIdentifier)
            recordCurrentFocusedWindow()
        }
    }

    func refreshFocusQueuePreview() {
        let live = onScreenFocusRefs()
        focusQueue.sync(with: live)
        let layouts = screenLayouts()
        let activeDisplay = focusedWindow().flatMap { frame(of: $0) }.flatMap { displayIndex(for: $0, in: layouts) }
        focusQueuePreview = focusQueue.orderedQueue(
            liveWindows: live,
            scope: TilePreferencesManager.shared.focusScope,
            currentDisplayIndex: activeDisplay
        )
    }

    func focusWindowFromPreview(_ ref: FocusWindowRef) {
        guard let element = axWindow(for: ref) else { return }
        focusQueue.commitSession()
        focusQueue.recordFocus(ref)
        bringToFront(element, pid: ref.pid)
        if TilePreferencesManager.shared.warpCursorOnFocus {
            warpCursorToCenter(of: ref.bounds)
        }
        publishFocusQueuePreviewIfVisible()
    }

    private func rebuildScreenLayoutCache() {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        primaryScreenHeight = primaryHeight
        cachedScreenLayouts = screens.map { ScreenLayout.from(screen: $0, primaryScreenHeight: primaryHeight) }
    }

    func screenLayouts() -> [ScreenLayout] {
        if cachedScreenLayouts.isEmpty {
            rebuildScreenLayoutCache()
        }
        return cachedScreenLayouts
    }

    func focusedWindow() -> AXUIElement? {
        guard let app = targetApplication() else { return nil }
        let element = appElement(for: app.processIdentifier)

        if let window = elementAttribute(kAXFocusedWindowAttribute, of: element)
            ?? elementAttribute(kAXMainWindowAttribute, of: element) {
            AXUIElementSetMessagingTimeout(window, axMessagingTimeout)
            return window
        }
        if let first = (copyAttribute(kAXWindowsAttribute, of: element) as? [AXUIElement])?.first {
            AXUIElementSetMessagingTimeout(first, axMessagingTimeout)
            return first
        }
        return nil
    }

    func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        if pid == ownPID && !MainWindowController.shared.isWindowVisible {
            return nil
        }

        if (copyAttribute(kAXRoleAttribute, of: element) as? String) == kAXWindowRole {
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            return element
        }
        if let window = elementAttribute(kAXWindowAttribute, of: element) {
            AXUIElementSetMessagingTimeout(window, axMessagingTimeout)
            return window
        }
        return nil
    }

    func frame(of window: AXUIElement) -> CGRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, Self.frameAttributes, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 2,
              let origin = Self.unpack(values[0], as: .cgPoint, initial: CGPoint.zero),
              let size = Self.unpack(values[1], as: .cgSize, initial: CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Batched single-IPC inspection reading position, size, subrole, fullscreen state, PID, and CGWindowID.
    func inspectWindow(_ window: AXUIElement) -> WindowInspection? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        if pid == ownPID && !MainWindowController.shared.isWindowVisible {
            return nil
        }
        if pid != ownPID && TilePreferencesManager.shared.isExcluded(processIdentifier: pid) {
            return nil
        }

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, Self.inspectionAttributes, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 4,
              let origin = Self.unpack(values[0], as: .cgPoint, initial: CGPoint.zero),
              let size = Self.unpack(values[1], as: .cgSize, initial: CGSize.zero) else {
            return nil
        }

        let subrole = values[2] as? String
        if let subrole, Self.ignoredSubroles.contains(subrole) {
            return nil
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return nil
        }

        let isFullScreen = (values[3] as? Bool) == true
        let windowID = tileAXWindowID(of: window)
        return WindowInspection(
            windowID: windowID,
            pid: pid,
            frame: CGRect(origin: origin, size: size),
            subrole: subrole,
            isFullScreen: isFullScreen
        )
    }

    private static func unpack<Value: BitwiseCopyable>(_ object: AnyObject, as type: AXValueType, initial: Value) -> Value? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        var value = initial
        return AXValueGetValue(object as! AXValue, type, &value) ? value : nil
    }

    func isManageable(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            return false
        }
        if pid == ownPID {
            guard MainWindowController.shared.isWindowVisible else { return false }
            if let subrole = copyAttribute(kAXSubroleAttribute, of: window) as? String, Self.ignoredSubroles.contains(subrole) {
                return false
            }
            var settable: DarwinBoolean = false
            return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success && settable.boolValue
        }
        guard !TilePreferencesManager.shared.isExcluded(processIdentifier: pid) else {
            return false
        }
        if let subrole = copyAttribute(kAXSubroleAttribute, of: window) as? String, Self.ignoredSubroles.contains(subrole) {
            return false
        }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success && settable.boolValue
    }

    func targetApplication() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication {
            if front.processIdentifier == ownPID {
                if MainWindowController.shared.isWindowVisible {
                    return front
                }
            } else {
                return front
            }
        }
        if let last = lastActiveApp, !last.isTerminated {
            return last
        }
        return nil
    }

    func move(_ window: AXUIElement, to origin: CGPoint) {
        setPosition(origin, of: window)
    }

    func resize(_ window: AXUIElement, to frame: CGRect) {
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
    }

    /// Disables AXEnhancedUserInterface for an app once (used by ModifierDragManager for smooth 120fps dragging).
    /// Returns true if it was previously enabled and should be restored when the drag session finishes.
    func suspendEnhancedUserInterface(for window: AXUIElement) -> (pid: pid_t, wasEnabled: Bool) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return (0, false) }
        let element = appElement(for: pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        let wasEnabled = (copyAttribute("AXEnhancedUserInterface", of: element) as? Bool) == true
        if wasEnabled {
            AXUIElementSetAttributeValue(element, attribute, kCFBooleanFalse)
        }
        return (pid, wasEnabled)
    }

    func restoreEnhancedUserInterface(pid: pid_t, wasEnabled: Bool) {
        guard wasEnabled, pid > 0 else { return }
        let element = appElement(for: pid)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    func bringToFront(_ window: AXUIElement, pid knownPID: pid_t? = nil) {
        let pid: pid_t
        if let knownPID {
            pid = knownPID
        } else {
            var resolved: pid_t = 0
            guard AXUIElementGetPid(window, &resolved) == .success else { return }
            pid = resolved
        }
        let element = appElement(for: pid)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func restoreSizeIfTiled(_ window: AXUIElement, initialFrame: CGRect, cursor: CGPoint) {
        let key = restoreKey(for: window, windowID: tileAXWindowID(of: window))
        guard let point = restorePoints[key],
              abs(point.applied.width - initialFrame.width) <= 2,
              abs(point.applied.height - initialFrame.height) <= 2,
              let current = frame(of: window) else { return }

        let original = point.original.size
        let grabRatio = ((cursor.x - current.minX) / max(1, current.width)).clamped(to: 0...1)
        let origin = CGPoint(x: cursor.x - grabRatio * original.width, y: current.minY)
        setSize(original, of: window)
        setPosition(origin, of: window)
        forgetRestorePoint(for: key)
    }

    @discardableResult
    func perform(action: WindowAction) -> Bool {
        let accessibility = TileAccessibilityManager.shared
        guard accessibility.isTrusted || accessibility.refresh() else {
            accessibility.promptIfNeeded()
            return false
        }
        if let direction = action.focusDirection {
            return focusWindow(toward: direction)
        }
        switch action {
        case .focusLastWindow:
            return focusLastWindow()
        case .focusQueueNext:
            return stepFocusQueue(direction: 1)
        case .focusQueuePrevious:
            return stepFocusQueue(direction: -1)
        case .swapWithLastWindow:
            return swapWithLastWindow()
        default:
            break
        }
        guard let window = focusedWindow() else {
            accessibility.refresh()
            return false
        }
        return perform(action: action, on: window)
    }

    @discardableResult
    func perform(action: WindowAction, on window: AXUIElement) -> Bool {
        guard !action.isFocusOrSwitchAction,
              let inspection = inspectWindow(window),
              !inspection.isFullScreen else { return false }

        let currentFrame = inspection.frame
        let key = restoreKey(for: window, windowID: inspection.windowID)
        let layouts = screenLayouts()
        guard let currentScreen = ScreenLayout.screen(for: currentFrame, in: layouts) else { return false }
        let prefs = TilePreferencesManager.shared
        let options = prefs.tileOptions

        switch action {
        case .restore:
            resetCycle()
            guard let point = restorePoints[key] else { return false }
            forgetRestorePoint(for: key)
            setFrame(point.original, of: window, pid: inspection.pid)
            return true

        case .nextDisplay, .previousDisplay:
            resetCycle()
            guard layouts.count > 1 else { return false }
            let currentIndex = layouts.firstIndex(of: currentScreen) ?? 0
            let offset = action == .nextDisplay ? 1 : layouts.count - 1
            let targetScreen = layouts[(currentIndex + offset) % layouts.count]
            let target = TileCalculation.translate(frame: currentFrame, from: currentScreen, to: targetScreen)
            recordRestorePoint(currentFrame, for: key)
            let applied = setFrame(target, of: window, pid: inspection.pid, within: targetScreen.visibleBounds, crossDisplay: true)
            restorePoints[key]?.applied = applied
            return true

        default:
            let wasJustApplied = lastAction == action
                && lastActionWindowKey == key
                && lastActionScreen == currentScreen
                && restorePoints[key]?.applied.isApproximatelyEqual(to: currentFrame, tolerance: 36) == true

            if (prefs.moveToAdjacentDisplayOnEdge || prefs.repeatBehavior == .moveAcrossDisplays),
               let (target, targetScreen) = TileCalculation.traversalTarget(
                   for: action,
                   frame: currentFrame,
                   screen: currentScreen,
                   layouts: layouts,
                   options: options,
                   wasJustApplied: wasJustApplied
               ) {
                resetCycle()
                recordRestorePoint(currentFrame, for: key)
                let applied = setFrame(target, of: window, pid: inspection.pid, within: targetScreen.visibleBounds, crossDisplay: true)
                restorePoints[key]?.applied = applied
                return true
            }

            let now = Date()
            let isRepeat = prefs.repeatBehavior == .cycleSizes
                && lastAction == action
                && lastActionWindowKey == key
                && now.timeIntervalSince(lastActionTime) < cycleInterval
            cycleCount = isRepeat ? cycleCount + 1 : 0
            lastAction = action
            lastActionWindowKey = key
            lastActionScreen = currentScreen
            lastActionTime = now

            if !isRepeat {
                recordRestorePoint(currentFrame, for: key)
            }

            let target = TileCalculation.calculate(
                action: action,
                screen: currentScreen,
                currentFrame: currentFrame,
                options: options,
                cycleIndex: cycleCount
            )
            let applied = setFrame(target, of: window, pid: inspection.pid, within: currentScreen.visibleBounds)
            restorePoints[key]?.applied = applied
            return true
        }
    }

    // MARK: - Smart Focus & MRU Queue Actions

    private func focusLastWindow() -> Bool {
        let layouts = screenLayouts()
        let live = onScreenFocusRefs(layouts: layouts)
        guard live.count >= 2 else { return false }

        let currentWindow = focusedWindow()
        let currentID = currentWindow.flatMap(tileAXWindowID(of:))
        let currentFrame = currentWindow.flatMap { frame(of: $0) }
        let currentDisplay = currentFrame.flatMap { displayIndex(for: $0, in: layouts) }
        let prefs = TilePreferencesManager.shared

        guard let result = focusQueue.switchToLastWindow(
            currentID: currentID,
            liveWindows: live,
            scope: prefs.focusScope,
            currentDisplayIndex: currentDisplay
        ) else {
            return false
        }

        return activateFocusResult(
            result,
            headerTitle: WindowAction.focusLastWindow.displayName,
            headerSymbol: WindowAction.focusLastWindow.sfSymbol,
            layouts: layouts,
            hudDuration: 0.95
        )
    }

    private func stepFocusQueue(direction: Int) -> Bool {
        let layouts = screenLayouts()
        let live = onScreenFocusRefs(layouts: layouts)
        guard live.count >= 2 else { return false }

        let currentWindow = focusedWindow()
        let currentID = currentWindow.flatMap(tileAXWindowID(of:))
        let currentFrame = currentWindow.flatMap { frame(of: $0) }
        let currentDisplay = currentFrame.flatMap { displayIndex(for: $0, in: layouts) }
        let prefs = TilePreferencesManager.shared

        guard let result = focusQueue.step(
            direction: direction,
            currentID: currentID,
            liveWindows: live,
            scope: prefs.focusScope,
            currentDisplayIndex: currentDisplay
        ) else {
            return false
        }

        scheduleQueueSessionCommit()

        let action: WindowAction = direction > 0 ? .focusQueueNext : .focusQueuePrevious
        return activateFocusResult(
            result,
            headerTitle: action.displayName,
            headerSymbol: action.sfSymbol,
            layouts: layouts,
            hudDuration: focusQueue.sessionTimeout
        )
    }

    private func swapWithLastWindow() -> Bool {
        let layouts = screenLayouts()
        let live = onScreenFocusRefs(layouts: layouts)
        guard live.count >= 2,
              let currentElement = focusedWindow(),
              let currentInspection = inspectWindow(currentElement),
              !currentInspection.isFullScreen else {
            return false
        }

        let currentDisplay = displayIndex(for: currentInspection.frame, in: layouts)
        let prefs = TilePreferencesManager.shared
        focusQueue.commitSession()
        focusQueue.sync(with: live)

        let ordered = focusQueue.orderedQueue(
            liveWindows: live,
            scope: prefs.focusScope,
            currentDisplayIndex: currentDisplay
        )
        let currentID = currentInspection.windowID
        guard let partnerRef = ordered.first(where: { ref in
            if let currentID { return ref.windowID != currentID }
            return !ref.bounds.isApproximatelyEqual(to: currentInspection.frame)
        }),
              let partnerElement = axWindow(for: partnerRef),
              let partnerInspection = inspectWindow(partnerElement),
              !partnerInspection.isFullScreen else {
            return false
        }

        let currentFrame = currentInspection.frame
        let partnerFrame = partnerInspection.frame
        let currentScreen = ScreenLayout.screen(for: currentFrame, in: layouts)
        let partnerScreen = ScreenLayout.screen(for: partnerFrame, in: layouts)
        let crossesDisplays = currentScreen != partnerScreen

        let currentKey = restoreKey(for: currentElement, windowID: currentInspection.windowID)
        let partnerKey = restoreKey(for: partnerElement, windowID: partnerInspection.windowID)
        recordRestorePoint(currentFrame, for: currentKey)
        recordRestorePoint(partnerFrame, for: partnerKey)

        let appliedCurrent = setFrame(
            partnerFrame,
            of: currentElement,
            pid: currentInspection.pid,
            within: partnerScreen?.visibleBounds,
            crossDisplay: crossesDisplays
        )
        let appliedPartner = setFrame(
            currentFrame,
            of: partnerElement,
            pid: partnerInspection.pid,
            within: currentScreen?.visibleBounds,
            crossDisplay: crossesDisplays
        )
        restorePoints[currentKey]?.applied = appliedCurrent
        restorePoints[partnerKey]?.applied = appliedPartner

        if prefs.showFocusHUD, let hudScreen = partnerScreen ?? currentScreen ?? layouts.first {
            let refreshedQueue = ordered.map { item -> FocusWindowRef in
                var copy = item
                if copy.windowID == currentInspection.windowID {
                    copy.bounds = appliedCurrent
                } else if copy.windowID == partnerRef.windowID {
                    copy.bounds = appliedPartner
                }
                return copy
            }
            let selected = refreshedQueue.firstIndex(where: { $0.windowID == currentInspection.windowID }) ?? 0
            FocusQueuePanel.shared.show(
                queue: refreshedQueue,
                selectedIndex: selected,
                headerTitle: WindowAction.swapWithLastWindow.displayName,
                headerSymbol: WindowAction.swapWithLastWindow.sfSymbol,
                on: hudScreen,
                primaryScreenHeight: primaryScreenHeight,
                autoHideAfter: 0.95
            )
        }
        return true
    }

    private func focusWindow(toward direction: FocusDirection) -> Bool {
        guard let current = focusedWindow(), let source = frame(of: current) else { return false }
        let layouts = screenLayouts()
        let live = onScreenFocusRefs(layouts: layouts)
        guard !live.isEmpty else { return false }

        focusQueue.commitSession()
        focusQueue.sync(with: live)

        let currentID = tileAXWindowID(of: current)
        let currentDisplay = displayIndex(for: source, in: layouts)
        let prefs = TilePreferencesManager.shared

        let scopedLive: [FocusWindowRef]
        if prefs.focusScope == .currentDisplay {
            let matching = live.filter { $0.displayIndex == currentDisplay }
            scopedLive = matching.isEmpty ? live : matching
        } else {
            scopedLive = live
        }

        let ranks = focusQueue.mruRanks()
        let navCandidates = scopedLive.map {
            WindowNavigationCandidate(windowID: $0.windowID, bounds: $0.bounds, mruRank: ranks[$0.windowID])
        }

        var chosenIndex = WindowNavigator.smartNearest(
            from: source,
            toward: direction,
            among: navCandidates,
            sourceWindowID: currentID
        )

        var headerTitle: String
        var headerSymbol: String
        switch direction {
        case .left:
            headerTitle = WindowAction.focusLeft.displayName
            headerSymbol = WindowAction.focusLeft.sfSymbol
        case .right:
            headerTitle = WindowAction.focusRight.displayName
            headerSymbol = WindowAction.focusRight.sfSymbol
        case .up:
            headerTitle = WindowAction.focusUp.displayName
            headerSymbol = WindowAction.focusUp.sfSymbol
        case .down:
            headerTitle = WindowAction.focusDown.displayName
            headerSymbol = WindowAction.focusDown.sfSymbol
        }

        if chosenIndex == nil {
            switch prefs.directionalFocusFallback {
            case .none:
                return false
            case .wrapAround:
                chosenIndex = WindowNavigator.wrapAround(
                    from: source,
                    toward: direction,
                    among: navCandidates,
                    sourceWindowID: currentID
                )
            case .lastWindow:
                return focusLastWindow()
            }
        }

        guard let index = chosenIndex else { return false }
        let targetRef = scopedLive[index]
        guard let targetWindow = axWindow(for: targetRef) else { return false }

        if let currentID, let currentRef = live.first(where: { $0.windowID == currentID }) {
            focusQueue.recordFocus(currentRef)
        }
        focusQueue.recordFocus(targetRef)
        bringToFront(targetWindow, pid: targetRef.pid)

        if prefs.warpCursorOnFocus {
            warpCursorToCenter(of: targetRef.bounds)
        }

        if prefs.showFocusHUD {
            let ordered = focusQueue.orderedQueue(
                liveWindows: live,
                scope: prefs.focusScope,
                currentDisplayIndex: targetRef.displayIndex
            )
            let selected = ordered.firstIndex(where: { $0.windowID == targetRef.windowID }) ?? 0
            let hudScreen = ScreenLayout.screen(for: targetRef.bounds, in: layouts) ?? layouts.first
            if let hudScreen {
                FocusQueuePanel.shared.show(
                    queue: ordered,
                    selectedIndex: selected,
                    headerTitle: headerTitle,
                    headerSymbol: headerSymbol,
                    on: hudScreen,
                    primaryScreenHeight: primaryScreenHeight,
                    autoHideAfter: 0.9
                )
            }
        }

        publishFocusQueuePreviewIfVisible()
        return true
    }

    private func activateFocusResult(
        _ result: FocusStepResult,
        headerTitle: String,
        headerSymbol: String,
        layouts: [ScreenLayout],
        hudDuration: TimeInterval
    ) -> Bool {
        guard let targetWindow = axWindow(for: result.target) else {
            focusQueue.remove(windowID: result.target.windowID)
            return false
        }

        bringToFront(targetWindow, pid: result.target.pid)

        let prefs = TilePreferencesManager.shared
        if prefs.warpCursorOnFocus {
            warpCursorToCenter(of: result.target.bounds)
        }

        if prefs.showFocusHUD,
           let hudScreen = ScreenLayout.screen(for: result.target.bounds, in: layouts) ?? layouts.first {
            FocusQueuePanel.shared.show(
                queue: result.queue,
                selectedIndex: result.selectedIndex,
                headerTitle: headerTitle,
                headerSymbol: headerSymbol,
                on: hudScreen,
                primaryScreenHeight: primaryScreenHeight,
                autoHideAfter: hudDuration
            )
        }

        publishFocusQueuePreviewIfVisible()
        return true
    }

    private func scheduleQueueSessionCommit() {
        queueCommitTask?.cancel()
        let delay = focusQueue.sessionTimeout
        queueCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled, let self else { return }
            self.focusQueue.commitSession()
            self.publishFocusQueuePreviewIfVisible()
        }
    }

    private func warpCursorToCenter(of quartzRect: CGRect) {
        guard quartzRect.width > 10, quartzRect.height > 10 else { return }
        CGWarpMouseCursorPosition(CGPoint(x: quartzRect.midX, y: quartzRect.midY))
    }

    // MARK: - Fast Frame Application

    @discardableResult
    private func setFrame(
        _ target: CGRect,
        of window: AXUIElement,
        pid: pid_t? = nil,
        within bounds: CGRect? = nil,
        crossDisplay: Bool = false
    ) -> CGRect {
        let resolvedPID: pid_t
        if let pid {
            resolvedPID = pid
        } else {
            var fetched: pid_t = 0
            AXUIElementGetPid(window, &fetched)
            resolvedPID = fetched
        }

        var actual: CGRect?
        withEnhancedUserInterfaceDisabled(pid: resolvedPID) {
            if crossDisplay {
                // Cross-display moves may clamp size to the old screen first: position -> size -> verify -> retry if needed.
                setPosition(target.origin, of: window)
                setSize(target.size, of: window)
            } else {
                setSize(target.size, of: window)
                setPosition(target.origin, of: window)
            }

            actual = frame(of: window)
            if let current = actual, !current.isApproximatelyEqual(to: target, tolerance: 2) {
                setSize(target.size, of: window)
                setPosition(target.origin, of: window)
                actual = frame(of: window)
            }
        }

        guard let bounds,
              let current = actual,
              bounds.intersects(current),
              !current.size.equalTo(target.size) else { return actual ?? target }

        let maxX = max(bounds.minX, bounds.maxX - current.width)
        let maxY = max(bounds.minY, bounds.maxY - current.height)
        let corrected = CGRect(
            x: current.minX.clamped(to: bounds.minX...maxX),
            y: current.minY.clamped(to: bounds.minY...maxY),
            width: current.width,
            height: current.height
        )
        if !corrected.origin.equalTo(current.origin) {
            setPosition(corrected.origin, of: window)
        }
        return corrected
    }

    private func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
    }

    private func withEnhancedUserInterfaceDisabled(pid: pid_t, _ body: () -> Void) {
        guard pid > 0 else {
            body()
            return
        }
        let element = appElement(for: pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        let wasEnabled = (copyAttribute("AXEnhancedUserInterface", of: element) as? Bool) == true
        if wasEnabled {
            AXUIElementSetAttributeValue(element, attribute, kCFBooleanFalse)
        }
        body()
        if wasEnabled {
            AXUIElementSetAttributeValue(element, attribute, kCFBooleanTrue)
        }
    }

    // MARK: - Window Resolution & Focus Observation

    private func axWindow(for ref: FocusWindowRef) -> AXUIElement? {
        let element = appElement(for: ref.pid)
        guard let windows = copyAttribute(kAXWindowsAttribute, of: element) as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        // Fast path: match exact CGWindowID with zero additional IPCs
        if ref.windowID > 0, let matched = windows.first(where: { tileAXWindowID(of: $0) == ref.windowID }) {
            AXUIElementSetMessagingTimeout(matched, axMessagingTimeout)
            return matched
        }

        // Fallback: match by bounds
        if let matched = windows.first(where: { frame(of: $0)?.isApproximatelyEqual(to: ref.bounds, tolerance: 6) == true }) {
            AXUIElementSetMessagingTimeout(matched, axMessagingTimeout)
            return matched
        }

        return nil
    }

    private func onScreenFocusRefs(layouts: [ScreenLayout]? = nil) -> [FocusWindowRef] {
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let resolvedLayouts = layouts ?? screenLayouts()
        let ownVisible = MainWindowController.shared.isWindowVisible
        let prefs = TilePreferencesManager.shared
        let now = Date()

        var results: [FocusWindowRef] = []
        results.reserveCapacity(entries.count)
        var seenIDs = Set<CGWindowID>()

        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  (pid != ownPID || ownVisible),
                  !prefs.isExcluded(processIdentifier: pid),
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 60, bounds.height > 60 else { continue }

            let windowID = CGWindowID(windowNumber.uint32Value)
            guard windowID > 0, seenIDs.insert(windowID).inserted else { continue }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? "App"
            let title = (entry[kCGWindowName as String] as? String) ?? ""
            let display = displayIndex(for: bounds, in: resolvedLayouts)

            results.append(
                FocusWindowRef(
                    windowID: windowID,
                    pid: pid,
                    appName: appName,
                    title: title,
                    bounds: bounds,
                    displayIndex: display,
                    lastFocusedAt: now
                )
            )
        }
        return results
    }

    private func displayIndex(for bounds: CGRect, in layouts: [ScreenLayout]) -> Int {
        guard let screen = ScreenLayout.screen(for: bounds, in: layouts),
              let index = layouts.firstIndex(of: screen) else { return 0 }
        return index
    }

    private func attachFocusObserver(to pid: pid_t) {
        guard pid > 0, AXIsProcessTrusted() else { return }
        if activeAXObserverPID == pid, activeAXObserver != nil { return }
        detachFocusObserver()

        var observer: AXObserver?
        guard AXObserverCreate(pid, activeAppFocusObserverCallback, &observer) == .success,
              let observer else { return }

        let element = appElement(for: pid)
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, nil)
        AXObserverAddNotification(observer, element, kAXMainWindowChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        activeAXObserver = observer
        activeAXObserverPID = pid
    }

    private func detachFocusObserver() {
        if let observer = activeAXObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            activeAXObserver = nil
        }
        activeAXObserverPID = 0
    }

    fileprivate func handleActiveAppWindowFocusChanged() {
        recordCurrentFocusedWindow()
    }

    private func seedFocusQueueFromCurrentWindows() {
        let live = onScreenFocusRefs()
        focusQueue.sync(with: live)
        if let first = live.first {
            focusQueue.recordFocus(first)
        }
        publishFocusQueuePreviewIfVisible()
    }

    private func recordCurrentFocusedWindow() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if pid == ownPID && !MainWindowController.shared.isWindowVisible { return }
        if pid != ownPID && TilePreferencesManager.shared.isExcluded(processIdentifier: pid) { return }

        let element = appElement(for: pid)
        guard let window = elementAttribute(kAXFocusedWindowAttribute, of: element)
            ?? elementAttribute(kAXMainWindowAttribute, of: element),
              let windowID = tileAXWindowID(of: window),
              let rect = frame(of: window),
              rect.width > 60, rect.height > 60 else { return }

        let title = (copyAttribute(kAXTitleAttribute, of: window) as? String) ?? ""
        let appName = app.localizedName ?? "App"
        let display = displayIndex(for: rect, in: screenLayouts())
        let ref = FocusWindowRef(
            windowID: windowID,
            pid: pid,
            appName: appName,
            title: title,
            bounds: rect,
            displayIndex: display
        )
        focusQueue.recordFocus(ref)
        publishFocusQueuePreviewIfVisible()
    }

    private func publishFocusQueuePreviewIfVisible() {
        guard MainWindowController.shared.isWindowVisible else { return }
        focusQueuePreview = focusQueue.entries
    }

    // MARK: - AX Helpers & Restore History

    private func copyAttribute(_ attribute: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func restoreKey(for window: AXUIElement, windowID: CGWindowID?) -> RestoreKey {
        if let windowID, windowID > 0 {
            return .windowID(windowID)
        }
        return .element(window)
    }

    private func resetCycle() {
        lastAction = nil
        lastActionWindowKey = nil
        lastActionScreen = nil
        cycleCount = 0
    }

    private func recordRestorePoint(_ frame: CGRect, for key: RestoreKey) {
        if let existing = restorePoints[key], existing.applied.isApproximatelyEqual(to: frame) {
            return
        }
        if restorePoints[key] == nil {
            restoreOrder.append(key)
            if restoreOrder.count > maxRestoreHistory {
                restorePoints.removeValue(forKey: restoreOrder.removeFirst())
            }
        }
        restorePoints[key] = RestorePoint(original: frame, applied: frame)
    }

    private func forgetRestorePoint(for key: RestoreKey) {
        restorePoints.removeValue(forKey: key)
        restoreOrder.removeAll { $0 == key }
    }
}
