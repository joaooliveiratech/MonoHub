import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private struct RestorePoint {
        let original: CGRect
        var applied: CGRect
    }

    private static let ignoredSubroles: Set<String> = [kAXSystemDialogSubrole, kAXSystemFloatingWindowSubrole]
    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute] as CFArray

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let systemWideElement = AXUIElementCreateSystemWide()
    private let maxRestoreHistory = 50
    private let cycleInterval: TimeInterval = 1.3

    private var restorePoints: [AXUIElement: RestorePoint] = [:]
    private var restoreOrder: [AXUIElement] = []
    private var lastAction: WindowAction?
    private var lastActionWindow: AXUIElement?
    private var lastActionScreen: ScreenLayout?
    private var lastActionTime: Date = .distantPast
    private var cycleCount = 0
    private var lastActiveApp: NSRunningApplication?
    private(set) var primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

    private var observers: [any NSObjectProtocol] = []

    private init() {
        AXUIElementSetMessagingTimeout(systemWideElement, 0.35)
    }

    private func makeAppElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.35)
        return element
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        let ownPID = self.ownPID
        primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID, app.activationPolicy == .regular {
            lastActiveApp = app
        }

        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ownPID,
                      app.activationPolicy == .regular else { return }
                MainActor.assumeIsolated {
                    WindowManager.shared.lastActiveApp = app
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    WindowManager.shared.primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
                }
            }
        ]
    }

    func stopObserving() {
        guard !observers.isEmpty else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observers[0])
        NotificationCenter.default.removeObserver(observers[1])
        observers.removeAll()
        lastActiveApp = nil
        restorePoints.removeAll()
        restoreOrder.removeAll()
        resetCycle()
    }

    func screenLayouts() -> [ScreenLayout] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? primaryScreenHeight
        primaryScreenHeight = primaryHeight
        return NSScreen.screens.map { ScreenLayout.from(screen: $0, primaryScreenHeight: primaryHeight) }
    }

    func focusedWindow() -> AXUIElement? {
        guard let app = targetApplication() else { return nil }
        let appElement = makeAppElement(pid: app.processIdentifier)

        if let window = elementAttribute(kAXFocusedWindowAttribute, of: appElement)
            ?? elementAttribute(kAXMainWindowAttribute, of: appElement) {
            AXUIElementSetMessagingTimeout(window, 0.35)
            return window
        }
        if let first = (copyAttribute(kAXWindowsAttribute, of: appElement) as? [AXUIElement])?.first {
            AXUIElementSetMessagingTimeout(first, 0.35)
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
            return element
        }
        return elementAttribute(kAXWindowAttribute, of: element)
    }

    func frame(of window: AXUIElement) -> CGRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, Self.frameAttributes, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 2,
              let origin = Self.unpack(values[0], as: .cgPoint, initial: CGPoint.zero),
              let size = Self.unpack(values[1], as: .cgSize, initial: CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
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

    func bringToFront(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func restoreSizeIfTiled(_ window: AXUIElement, initialFrame: CGRect, cursor: CGPoint) {
        guard let point = restorePoints[window],
              abs(point.applied.width - initialFrame.width) <= 2,
              abs(point.applied.height - initialFrame.height) <= 2,
              let current = frame(of: window) else { return }

        let original = point.original.size
        let grabRatio = ((cursor.x - current.minX) / max(1, current.width)).clamped(to: 0...1)
        let origin = CGPoint(x: cursor.x - grabRatio * original.width, y: current.minY)
        setSize(original, of: window)
        setPosition(origin, of: window)
        forgetRestorePoint(for: window)
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
        guard let window = focusedWindow() else {
            accessibility.refresh()
            return false
        }
        return perform(action: action, on: window)
    }

    @discardableResult
    func perform(action: WindowAction, on window: AXUIElement) -> Bool {
        guard action.focusDirection == nil,
              isManageable(window),
              !isFullScreen(window),
              let currentFrame = frame(of: window) else { return false }

        let layouts = screenLayouts()
        guard let currentScreen = ScreenLayout.screen(for: currentFrame, in: layouts) else { return false }
        let prefs = TilePreferencesManager.shared
        let options = prefs.tileOptions

        switch action {
        case .restore:
            resetCycle()
            guard let point = restorePoints[window] else { return false }
            forgetRestorePoint(for: window)
            setFrame(point.original, of: window)
            return true

        case .nextDisplay, .previousDisplay:
            resetCycle()
            guard layouts.count > 1 else { return false }
            let currentIndex = layouts.firstIndex(of: currentScreen) ?? 0
            let offset = action == .nextDisplay ? 1 : layouts.count - 1
            let targetScreen = layouts[(currentIndex + offset) % layouts.count]
            let target = TileCalculation.translate(frame: currentFrame, from: currentScreen, to: targetScreen)
            recordRestorePoint(currentFrame, for: window)
            let applied = setFrame(target, of: window, within: targetScreen.visibleBounds)
            restorePoints[window]?.applied = applied
            return true

        default:
            let wasJustApplied = lastAction == action
                && lastActionWindow == window
                && (lastActionScreen == currentScreen
                    || restorePoints[window]?.applied.isApproximatelyEqual(to: currentFrame, tolerance: 36) == true)

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
                recordRestorePoint(currentFrame, for: window)
                let applied = setFrame(target, of: window, within: targetScreen.visibleBounds)
                restorePoints[window]?.applied = applied
                return true
            }

            let now = Date()
            let isRepeat = prefs.repeatBehavior == .cycleSizes
                && lastAction == action
                && lastActionWindow == window
                && now.timeIntervalSince(lastActionTime) < cycleInterval
            cycleCount = isRepeat ? cycleCount + 1 : 0
            lastAction = action
            lastActionWindow = window
            lastActionScreen = currentScreen
            lastActionTime = now

            if !isRepeat {
                recordRestorePoint(currentFrame, for: window)
            }

            let target = TileCalculation.calculate(
                action: action,
                screen: currentScreen,
                currentFrame: currentFrame,
                options: options,
                cycleIndex: cycleCount
            )
            let applied = setFrame(target, of: window, within: currentScreen.visibleBounds)
            restorePoints[window]?.applied = applied
            return true
        }
    }

    @discardableResult
    private func setFrame(_ target: CGRect, of window: AXUIElement, within bounds: CGRect? = nil) -> CGRect {
        withEnhancedUserInterfaceDisabled(for: window) {
            setSize(target.size, of: window)
            setPosition(target.origin, of: window)
            setSize(target.size, of: window)
            setPosition(target.origin, of: window)
        }

        guard let bounds,
              let actual = frame(of: window),
              bounds.intersects(actual),
              !actual.size.equalTo(target.size) else { return target }

        let maxX = max(bounds.minX, bounds.maxX - actual.width)
        let maxY = max(bounds.minY, bounds.maxY - actual.height)
        let corrected = CGRect(
            x: actual.minX.clamped(to: bounds.minX...maxX),
            y: actual.minY.clamped(to: bounds.minY...maxY),
            width: actual.width,
            height: actual.height
        )
        if !corrected.origin.equalTo(actual.origin) {
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

    private func withEnhancedUserInterfaceDisabled(for window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            body()
            return
        }

        let appElement = makeAppElement(pid: pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        let wasEnabled = (copyAttribute(attribute as String, of: appElement) as? Bool) == true
        if wasEnabled {
            AXUIElementSetAttributeValue(appElement, attribute, kCFBooleanFalse)
        }
        body()
        if wasEnabled {
            AXUIElementSetAttributeValue(appElement, attribute, kCFBooleanTrue)
        }
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        (copyAttribute("AXFullScreen", of: window) as? Bool) == true
    }

    private func focusWindow(toward direction: FocusDirection) -> Bool {
        guard let current = focusedWindow(), let source = frame(of: current) else { return false }
        let candidates = onScreenWindows()
        guard let index = WindowNavigator.nearest(from: source, toward: direction, among: candidates.map(\.bounds)) else {
            return false
        }

        let candidate = candidates[index]
        let appElement = makeAppElement(pid: candidate.pid)
        guard let windows = copyAttribute(kAXWindowsAttribute, of: appElement) as? [AXUIElement],
              let window = windows.first(where: { frame(of: $0)?.isApproximatelyEqual(to: candidate.bounds) == true }) else {
            return false
        }
        bringToFront(window)
        return true
    }

    private func onScreenWindows() -> [(pid: pid_t, bounds: CGRect)] {
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownVisible = MainWindowController.shared.isWindowVisible
        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  (pid != ownPID || ownVisible),
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return (pid, bounds)
        }
    }

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

    private func resetCycle() {
        lastAction = nil
        lastActionWindow = nil
        lastActionScreen = nil
        cycleCount = 0
    }

    private func recordRestorePoint(_ frame: CGRect, for window: AXUIElement) {
        if let existing = restorePoints[window], existing.applied.isApproximatelyEqual(to: frame) {
            return
        }
        if restorePoints[window] == nil {
            restoreOrder.append(window)
            if restoreOrder.count > maxRestoreHistory {
                restorePoints.removeValue(forKey: restoreOrder.removeFirst())
            }
        }
        restorePoints[window] = RestorePoint(original: frame, applied: frame)
    }

    private func forgetRestorePoint(for window: AXUIElement) {
        restorePoints.removeValue(forKey: window)
        restoreOrder.removeAll { $0 == window }
    }
}
