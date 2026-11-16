import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit
import Synchronization

private typealias AXWindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private nonisolated let axWindowIDSymbol: AXWindowIDFunction? = {
    guard let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2),
          let symbol = dlsym(defaultHandle, "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(symbol, to: AXWindowIDFunction.self)
}()

private nonisolated func axWindowID(of element: AXUIElement) -> CGWindowID? {
    guard let axWindowIDSymbol else { return nil }
    var id: CGWindowID = 0
    guard axWindowIDSymbol(element, &id) == .success, id > 0 else { return nil }
    return id
}

nonisolated protocol WindowManaging: Sendable {
    func cachedThumbnail(for windowID: CGWindowID) -> CGImage?
    func clearCache()
    func prewarm() async
    func fetchOnScreenWindows(screens: ScreenSnapshot) -> [WindowInfo]
    func fetchExtendedWindows(
        base: [WindowInfo],
        screens: ScreenSnapshot,
        includeMinimized: Bool,
        showTabs: Bool,
        currentSpaceOnly: Bool
    ) async -> [WindowInfo]
    func focus(window: WindowInfo)
    func quitApplication(pid: pid_t)
    func hideApplication(pid: pid_t)
    func close(window: WindowInfo)
    func toggleMinimize(window: WindowInfo)
    func toggleZoom(window: WindowInfo)
    func tile(window: WindowInfo, side: TileSide, screens: ScreenSnapshot)
    func moveToNextDisplay(window: WindowInfo, screens: ScreenSnapshot)
    func captureThumbnails(
        for windows: [WindowInfo],
        priorityID: CGWindowID?,
        maxPixelSize: CGSize,
        onCapture: @escaping @Sendable @MainActor (CGWindowID, CGImage) -> Void
    ) async
}

nonisolated final class SwitcherWindowManager: WindowManaging, Sendable {
    static let shared = SwitcherWindowManager()

    private static let axMessagingTimeout: Float = 0.05
    private static let axActionTimeout: Float = 0.5
    private static let thumbnailCacheLimit = 40
    private static let maxConcurrentCaptures = 4
    private static let thumbnailFreshness = Duration.seconds(3)
    private static let shareableContentLifetime = Duration.seconds(2)
    private static let browserNames = ["safari", "chrome", "arc", "firefox", "brave", "edge"]

    private struct Unchecked<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) { self.value = value }
    }

    private struct CachedThumbnail {
        let image: CGImage
        let bounds: CGRect
        let capturedAt: ContinuousClock.Instant
    }

    private struct ThumbnailStore {
        var entries: [CGWindowID: CachedThumbnail] = [:]
        var insertionOrder: [CGWindowID] = []
    }

    private struct ShareableCache {
        var windows: Unchecked<[CGWindowID: SCWindow]>?
        var fetchedAt: ContinuousClock.Instant?
    }

    private struct LastTiledState: Sendable {
        let windowID: CGWindowID
        let side: TileSide
        let screenIndex: Int
    }

    private let thumbnails = Mutex(ThumbnailStore())
    private let appsCache = Mutex(AppLookup())
    private let shareable = Mutex(ShareableCache())
    private let lastTiled = Mutex<LastTiledState?>(nil)

    private init() {}

    func cachedThumbnail(for windowID: CGWindowID) -> CGImage? {
        thumbnails.withLock { $0.entries[windowID]?.image }
    }

    func clearCache() {
        thumbnails.withLock {
            $0.entries.removeAll()
            $0.insertionOrder.removeAll()
        }
        appsCache.withLock { $0.purge() }
        shareable.withLock {
            $0.windows = nil
            $0.fetchedAt = nil
        }
    }

    func prewarm() async {
        _ = await refreshShareableWindows()
    }

    private func store(_ image: CGImage, for windowID: CGWindowID, bounds: CGRect) {
        thumbnails.withLock { store in
            let entry = CachedThumbnail(image: image, bounds: bounds, capturedAt: ContinuousClock.now)
            if store.entries.updateValue(entry, forKey: windowID) == nil {
                store.insertionOrder.append(windowID)
            }
            guard store.entries.count > Self.thumbnailCacheLimit else { return }
            let excess = store.entries.count - Self.thumbnailCacheLimit
            for evicted in store.insertionOrder.prefix(excess) {
                store.entries.removeValue(forKey: evicted)
            }
            store.insertionOrder.removeFirst(excess)
        }
    }

    private func isFresh(_ window: WindowInfo, minimumWidth: Int, now: ContinuousClock.Instant) -> Bool {
        thumbnails.withLock { store in
            guard let entry = store.entries[window.id] else { return false }
            return entry.bounds == window.bounds
                && entry.image.width >= minimumWidth
                && now - entry.capturedAt < Self.thumbnailFreshness
        }
    }

    private func purgeThumbnails(keeping liveIDs: Set<CGWindowID>) {
        thumbnails.withLock { store in
            guard store.entries.count > liveIDs.count else { return }
            store.entries = store.entries.filter { liveIDs.contains($0.key) }
            store.insertionOrder.removeAll { !liveIDs.contains($0) }
        }
    }

    func fetchOnScreenWindows(screens: ScreenSnapshot) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

        var results: [WindowInfo] = []
        results.reserveCapacity(raw.count)

        appsCache.withLock { apps in
            for info in raw {
                guard let candidate = Candidate(info, minimumSide: 60, apps: &apps) else { continue }
                if info[kCGWindowIsOnscreen as String] as? Bool == false { continue }
                if candidate.title.isEmpty, Self.requiresTitle(appName: candidate.appName) { continue }

                results.append(candidate.windowInfo(isMinimized: false, screens: screens))
            }
        }

        purgeThumbnails(keeping: Set(results.map(\.id)))
        return results
    }

    func fetchExtendedWindows(
        base: [WindowInfo],
        screens: ScreenSnapshot,
        includeMinimized: Bool,
        showTabs: Bool,
        currentSpaceOnly: Bool
    ) async -> [WindowInfo] {
        var results = base
        var seenIDs = Set(base.map(\.id))
        let allWindows = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []

        if includeMinimized {
            var byWindowID: [CGWindowID: [String: Any]] = [:]
            var byPID: [pid_t: [[String: Any]]] = [:]
            byWindowID.reserveCapacity(allWindows.count)
            for info in allWindows {
                guard let number = info[kCGWindowNumber as String] as? NSNumber,
                      let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
                byWindowID[CGWindowID(number.uint32Value)] = info
                byPID[pid_t(ownerPID.int32Value), default: []].append(info)
            }

            let currentPID = appsCache.withLock { $0.currentPID }
            let candidatePIDs = NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
                guard app.activationPolicy == .regular, app.processIdentifier != currentPID else { return nil }
                return app.processIdentifier
            }

            let collectedMinimized = await Self.collectMinimizedWindows(pids: candidatePIDs)
            appsCache.withLock { apps in
                for minimized in collectedMinimized {
                    var windowID = minimized.windowID
                    var matched = windowID > 0 ? byWindowID[windowID] : nil

                    if matched == nil, let candidates = byPID[minimized.pid] {
                        matched = candidates.first { info in
                            guard let id = Self.windowID(info), !seenIDs.contains(id) else { return false }
                            return !minimized.title.isEmpty && info[kCGWindowName as String] as? String == minimized.title
                        } ?? candidates.first { info in
                            guard let id = Self.windowID(info) else { return false }
                            return !seenIDs.contains(id)
                        }
                        if let matched, let id = Self.windowID(matched) { windowID = id }
                    }

                    guard windowID > 0, seenIDs.insert(windowID).inserted else { continue }

                    let bounds = matched.flatMap(Self.bounds) ?? minimized.bounds
                    let appName = matched?[kCGWindowOwnerName as String] as? String
                        ?? apps.name(for: minimized.pid)
                        ?? "App"
                    let title = minimized.title.isEmpty
                        ? (matched?[kCGWindowName as String] as? String ?? "")
                        : minimized.title

                    Self.insertGrouped(
                        WindowInfo(
                            id: windowID,
                            pid: minimized.pid,
                            appName: appName,
                            title: title,
                            bounds: bounds,
                            isMinimized: true,
                            displayIndex: screens.displayIndex(forCoreGraphics: bounds)
                        ),
                        into: &results
                    )
                }
            }
        }

        if showTabs || !currentSpaceOnly {
            var onScreenPIDs = Set(base.map(\.pid))

            appsCache.withLock { apps in
                for info in allWindows {
                    guard let candidate = Candidate(info, minimumSide: 120, apps: &apps) else { continue }
                    if seenIDs.contains(candidate.id) { continue }
                    if candidate.title.isEmpty { continue }
                    if showTabs, currentSpaceOnly, !onScreenPIDs.contains(candidate.pid) { continue }

                    seenIDs.insert(candidate.id)
                    onScreenPIDs.insert(candidate.pid)
                    Self.insertGrouped(candidate.windowInfo(isMinimized: false, screens: screens), into: &results)
                }
            }
        }

        purgeThumbnails(keeping: seenIDs)
        return results
    }

    private static func insertGrouped(_ window: WindowInfo, into results: inout [WindowInfo]) {
        if let lastOfSameApp = results.lastIndex(where: { $0.pid == window.pid }) {
            results.insert(window, at: lastOfSameApp + 1)
        } else {
            results.append(window)
        }
    }

    private static func requiresTitle(appName: String) -> Bool {
        let lower = appName.lowercased()
        return browserNames.contains { lower.contains($0) }
    }

    private static func windowID(_ info: [String: Any]) -> CGWindowID? {
        (info[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
    }

    private static func bounds(_ info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private struct AppLookup: Sendable {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        private var names: [pid_t: String?] = [:]

        mutating func name(for pid: pid_t) -> String? {
            if let cached = names[pid] { return cached }
            let app = NSRunningApplication(processIdentifier: pid)
            let resolved = app?.activationPolicy == .regular ? (app?.localizedName ?? "App") : nil
            names[pid] = resolved
            return resolved
        }

        mutating func purge() {
            names.removeAll()
        }
    }

    private struct Candidate {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let title: String
        let bounds: CGRect

        init?(_ info: [String: Any], minimumSide: CGFloat, apps: inout AppLookup) {
            guard let id = SwitcherWindowManager.windowID(info),
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(ownerPID.int32Value)
            guard pid != apps.currentPID else { return nil }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            guard (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0 >= 0.05 else { return nil }
            guard let bounds = SwitcherWindowManager.bounds(info),
                  bounds.width >= minimumSide,
                  bounds.height >= minimumSide,
                  bounds.origin.x >= -2000 else { return nil }
            guard let ownerName = apps.name(for: pid) else { return nil }
            let appName = info[kCGWindowOwnerName as String] as? String ?? ownerName

            self.id = id
            self.pid = pid
            self.appName = appName
            self.bounds = bounds
            self.title = (info[kCGWindowName as String] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func windowInfo(isMinimized: Bool, screens: ScreenSnapshot) -> WindowInfo {
            WindowInfo(
                id: id,
                pid: pid,
                appName: appName,
                title: title,
                bounds: bounds,
                isMinimized: isMinimized,
                displayIndex: screens.displayIndex(forCoreGraphics: bounds)
            )
        }
    }

    private struct MinimizedWindow: Sendable {
        let pid: pid_t
        let windowID: CGWindowID
        let title: String
        let bounds: CGRect
    }

    private static func collectMinimizedWindows(pids: [pid_t]) async -> [MinimizedWindow] {
        guard !pids.isEmpty else { return [] }

        return await withTaskGroup(of: [MinimizedWindow].self) { group in
            for pid in pids {
                group.addTask(priority: .userInitiated) { minimizedWindows(pid: pid) }
            }

            var collected: [MinimizedWindow] = []
            for await found in group where !found.isEmpty {
                collected.append(contentsOf: found)
            }
            return collected
        }
    }

    private static func axAttribute(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        axAttribute(kAXTitleAttribute, of: element) as? String
    }

    private static func axValue<T: BitwiseCopyable>(_ attribute: String, of element: AXUIElement, type: AXValueType, default value: T) -> T {
        var result = value
        guard let ref = axAttribute(attribute, of: element), CFGetTypeID(ref) == AXValueGetTypeID() else { return result }
        AXValueGetValue(unsafeDowncast(ref as AnyObject, to: AXValue.self), type, &result)
        return result
    }

    private static func axWindows(pid: pid_t, timeout: Float) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return axAttribute(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? []
    }

    private static func minimizedWindows(pid: pid_t) -> [MinimizedWindow] {
        axWindows(pid: pid, timeout: axMessagingTimeout).compactMap { axWindow in
            guard isMinimized(axWindow) else { return nil }
            let windowID = axWindowID(of: axWindow) ?? 0
            return MinimizedWindow(
                pid: pid,
                windowID: windowID,
                title: axTitle(of: axWindow) ?? "",
                bounds: windowID > 0 ? .zero : axFrame(of: axWindow)
            )
        }
    }

    private static func axFrame(of element: AXUIElement) -> CGRect {
        CGRect(
            origin: axValue(kAXPositionAttribute, of: element, type: .cgPoint, default: CGPoint.zero),
            size: axValue(kAXSizeAttribute, of: element, type: .cgSize, default: CGSize(width: 800, height: 600))
        )
    }

    private static func resolve(
        _ window: WindowInfo,
        among axWindows: [AXUIElement],
        allowGeometryFallback: Bool
    ) -> AXUIElement? {
        for axWindow in axWindows where axWindowID(of: axWindow) == window.id {
            return axWindow
        }

        if !window.title.isEmpty, let match = axWindows.first(where: { axTitle(of: $0) == window.title }) {
            return match
        }

        if !window.title.isEmpty, let match = axWindows.first(where: {
            guard let axTitle = axTitle(of: $0), !axTitle.isEmpty else { return false }
            return axTitle.localizedCaseInsensitiveContains(window.title) || window.title.localizedCaseInsensitiveContains(axTitle)
        }) {
            return match
        }

        guard allowGeometryFallback else { return nil }

        var bestMatch: AXUIElement?
        var minDistance: CGFloat = .infinity

        for axWindow in axWindows {
            let frame = axFrame(of: axWindow)
            let dx = frame.origin.x - window.bounds.origin.x
            let dy = frame.origin.y - window.bounds.origin.y
            let dw = frame.size.width - window.bounds.size.width
            let dh = frame.size.height - window.bounds.size.height
            let distance = dx * dx + dy * dy + dw * dw + dh * dh
            if distance < minDistance {
                minDistance = distance
                bestMatch = axWindow
            }
        }

        if minDistance < 250_000, let bestMatch {
            return bestMatch
        }
        return axWindows.first
    }

    private func performOnTargetAXWindow(
        for window: WindowInfo,
        allowGeometryFallback: Bool,
        action: @escaping @Sendable (AXUIElement) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            let axWindows = Self.axWindows(pid: window.pid, timeout: Self.axActionTimeout)
            guard let target = Self.resolve(
                window,
                among: axWindows,
                allowGeometryFallback: allowGeometryFallback
            ) else { return }
            action(target)
        }
    }

    private static func raiseAndFocus(_ target: AXUIElement, in application: AXUIElement) {
        unminimize(target)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, kAXMainWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, target)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func press(_ buttonAttribute: String, on target: AXUIElement) {
        guard let button = axAttribute(buttonAttribute, of: target),
              CFGetTypeID(button) == AXUIElementGetTypeID() else {
            return
        }
        AXUIElementPerformAction(unsafeDowncast(button as AnyObject, to: AXUIElement.self), kAXPressAction as CFString)
    }

    private static func isMinimized(_ target: AXUIElement) -> Bool {
        (axAttribute(kAXMinimizedAttribute, of: target) as? NSNumber)?.boolValue == true
    }

    private static func setMinimized(_ minimized: Bool, on target: AXUIElement) {
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private static func unminimize(_ target: AXUIElement) {
        if isMinimized(target) { setMinimized(false, on: target) }
    }

    private static func setFrame(_ frame: CGRect, on target: AXUIElement) {
        var pid: pid_t = 0
        let hasPID = AXUIElementGetPid(target, &pid) == .success && pid > 0
        let appElement: AXUIElement? = hasPID ? AXUIElementCreateApplication(pid) : nil
        let enhancedAttr = "AXEnhancedUserInterface" as CFString
        let wasEnhanced = appElement.flatMap { (axAttribute(enhancedAttr as String, of: $0) as? NSNumber)?.boolValue } == true
        if wasEnhanced, let appElement {
            AXUIElementSetAttributeValue(appElement, enhancedAttr, kCFBooleanFalse)
        }

        var origin = frame.origin
        var size = frame.size
        let positionValue = AXValueCreate(.cgPoint, &origin)
        let sizeValue = AXValueCreate(.cgSize, &size)
        if let sizeValue {
            AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, sizeValue)
        }
        if let positionValue {
            AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue {
            AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, sizeValue)
        }
        if let positionValue {
            AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, positionValue)
        }

        if wasEnhanced, let appElement {
            AXUIElementSetAttributeValue(appElement, enhancedAttr, kCFBooleanTrue)
        }
    }

    func focus(window: WindowInfo) {
        let pid = window.pid
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateAllWindows])
        }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.axActionTimeout)
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        if let axWindows = Self.axAttribute(kAXWindowsAttribute, of: application) as? [AXUIElement],
           let target = Self.resolve(window, among: axWindows, allowGeometryFallback: true) {
            Self.raiseAndFocus(target, in: application)
        }

        Task.detached(priority: .high) {
            try? await Task.sleep(for: .milliseconds(35))
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axActionTimeout)
            if let axWindows = Self.axAttribute(kAXWindowsAttribute, of: appElement) as? [AXUIElement],
               let target = Self.resolve(window, among: axWindows, allowGeometryFallback: true) {
                Self.raiseAndFocus(target, in: appElement)
            }
            await MainActor.run {
                if let app = NSRunningApplication(processIdentifier: pid), !app.isActive {
                    app.activate(options: [.activateAllWindows])
                }
            }
        }
    }

    func quitApplication(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    func hideApplication(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    func close(window: WindowInfo) {
        performOnTargetAXWindow(for: window, allowGeometryFallback: false) { target in
            Self.press(kAXCloseButtonAttribute, on: target)
        }
    }

    func toggleMinimize(window: WindowInfo) {
        performOnTargetAXWindow(for: window, allowGeometryFallback: false) { target in
            Self.setMinimized(!Self.isMinimized(target), on: target)
        }
    }

    func toggleZoom(window: WindowInfo) {
        performOnTargetAXWindow(for: window, allowGeometryFallback: false) { target in
            Self.press(kAXZoomButtonAttribute, on: target)
        }
    }

    func tile(window: WindowInfo, side: TileSide, screens: ScreenSnapshot) {
        performOnTargetAXWindow(for: window, allowGeometryFallback: true) { [self] element in
            Self.unminimize(element)
            let liveBounds = Self.axFrame(of: element)
            let index = screens.screenIndex(containingCoreGraphics: liveBounds) ?? 0
            guard let visible = screens.visibleFrame(at: index) else { return }

            let halfWidth = (visible.width / 2).rounded(.down)
            let half = CGRect(
                x: side == .left ? visible.minX : visible.midX,
                y: visible.minY,
                width: halfWidth,
                height: visible.height
            )
            let currentTarget = screens.coreGraphicsRect(fromAppKit: half).integral

            let wasJustTiledSameSide = lastTiled.withLock {
                $0?.windowID == window.id && $0?.side == side && $0?.screenIndex == index
            }

            let isAlreadyOnSide: Bool = {
                if wasJustTiledSameSide { return true }
                let tolerance: CGFloat = 36
                if side == .left {
                    return abs(liveBounds.minX - currentTarget.minX) <= tolerance
                        && liveBounds.midX <= currentTarget.maxX + 24
                } else {
                    return abs(liveBounds.maxX - currentTarget.maxX) <= tolerance
                        && liveBounds.midX >= currentTarget.minX - 24
                }
            }()

            if isAlreadyOnSide,
               let neighborIndex = screens.neighborScreenIndex(from: index, towardLeft: side == .left),
               let neighborVisible = screens.visibleFrame(at: neighborIndex) {
                let neighborHalfWidth = (neighborVisible.width / 2).rounded(.down)
                let landingLeft = (side == .right)
                let neighborHalf = CGRect(
                    x: landingLeft ? neighborVisible.minX : neighborVisible.midX,
                    y: neighborVisible.minY,
                    width: neighborHalfWidth,
                    height: neighborVisible.height
                )
                let neighborTarget = screens.coreGraphicsRect(fromAppKit: neighborHalf).integral
                Self.setFrame(neighborTarget, on: element)
                lastTiled.withLock {
                    $0 = LastTiledState(
                        windowID: window.id,
                        side: landingLeft ? .left : .right,
                        screenIndex: neighborIndex
                    )
                }
            } else {
                Self.setFrame(currentTarget, on: element)
                lastTiled.withLock {
                    $0 = LastTiledState(windowID: window.id, side: side, screenIndex: index)
                }
            }
        }
    }

    func moveToNextDisplay(window: WindowInfo, screens: ScreenSnapshot) {
        guard screens.count > 1 else { return }
        performOnTargetAXWindow(for: window, allowGeometryFallback: true) { element in
            let liveBounds = Self.axFrame(of: element)
            let currentIndex = screens.screenIndex(containingCoreGraphics: liveBounds) ?? 0
            let nextIndex = (currentIndex + 1) % screens.count
            guard let current = screens.visibleFrame(at: currentIndex),
                  let next = screens.visibleFrame(at: nextIndex) else { return }

            let appKitBounds = screens.appKitRect(fromCoreGraphics: liveBounds)
            let relativeX = current.width > 0 ? (appKitBounds.minX - current.minX) / current.width : 0
            let relativeY = current.height > 0 ? (appKitBounds.minY - current.minY) / current.height : 0

            let width = min(appKitBounds.width, next.width)
            let height = min(appKitBounds.height, next.height)
            let x = min(max(next.minX, next.minX + relativeX * next.width), next.maxX - width)
            let y = min(max(next.minY, next.minY + relativeY * next.height), next.maxY - height)

            let target = screens
                .coreGraphicsRect(fromAppKit: CGRect(x: x, y: y, width: width, height: height))
                .integral

            Self.setFrame(target, on: element)
        }
    }

    private struct CaptureTarget: Sendable {
        let window: WindowInfo
        let scWindow: Unchecked<SCWindow>
    }

    private func cachedShareableWindows() -> (windows: [CGWindowID: SCWindow], isStale: Bool)? {
        shareable.withLock { cache in
            guard let windows = cache.windows, let fetchedAt = cache.fetchedAt else { return nil }
            return (windows.value, ContinuousClock.now - fetchedAt >= Self.shareableContentLifetime)
        }
    }

    private func refreshShareableWindows() async -> [CGWindowID: SCWindow]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }

        var map: [CGWindowID: SCWindow] = [:]
        map.reserveCapacity(content.windows.count)
        for window in content.windows { map[window.windowID] = window }

        shareable.withLock { cache in
            cache.windows = Unchecked(map)
            cache.fetchedAt = ContinuousClock.now
        }
        return map
    }

    private func refreshedShareableWindows(if needed: Bool) async -> Unchecked<[CGWindowID: SCWindow]>? {
        guard needed, let map = await refreshShareableWindows() else { return nil }
        return Unchecked(map)
    }

    func captureThumbnails(
        for windows: [WindowInfo],
        priorityID: CGWindowID?,
        maxPixelSize: CGSize,
        onCapture: @escaping @Sendable @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        guard !windows.isEmpty, !Task.isCancelled else { return }

        let now = ContinuousClock.now
        var pending = windows.filter { window in
            guard !window.isMinimized else { return false }
            let required = Self.pixelSize(for: window.bounds, fitting: maxPixelSize)
            return !isFresh(window, minimumWidth: required.width - 2, now: now)
        }
        if let priorityID, let index = pending.firstIndex(where: { $0.id == priorityID }) {
            pending.insert(pending.remove(at: index), at: 0)
        }
        guard !pending.isEmpty else { return }

        let cached = cachedShareableWindows()
        let needsRefresh = cached?.isStale ?? true
        async let refreshed = refreshedShareableWindows(if: needsRefresh)

        var captured: Set<CGWindowID> = []
        if let cached {
            captured = await capture(pending, using: cached.windows, maxPixelSize: maxPixelSize, onCapture: onCapture)
        }

        guard let fresh = await refreshed, !Task.isCancelled else { return }
        let remaining = pending.filter { !captured.contains($0.id) }
        _ = await capture(remaining, using: fresh.value, maxPixelSize: maxPixelSize, onCapture: onCapture)
    }

    private func capture(
        _ windows: [WindowInfo],
        using scWindows: [CGWindowID: SCWindow],
        maxPixelSize: CGSize,
        onCapture: @escaping @Sendable @MainActor (CGWindowID, CGImage) -> Void
    ) async -> Set<CGWindowID> {
        let targets = windows.compactMap { window in
            scWindows[window.id].map { CaptureTarget(window: window, scWindow: Unchecked($0)) }
        }
        guard !targets.isEmpty, !Task.isCancelled else { return [] }

        return await withTaskGroup(of: CGWindowID?.self) { group in
            var captured: Set<CGWindowID> = []
            var iterator = targets.makeIterator()

            func schedule() {
                guard !Task.isCancelled, let target = iterator.next() else { return }
                group.addTask { [self] in
                    guard !Task.isCancelled,
                          let image = await capture(target.scWindow.value, window: target.window, maxPixelSize: maxPixelSize),
                          !Task.isCancelled else { return nil }
                    await onCapture(target.window.id, image)
                    return target.window.id
                }
            }

            for _ in 0..<Self.maxConcurrentCaptures { schedule() }

            while let result = await group.next() {
                if let result { captured.insert(result) }
                schedule()
            }
            return captured
        }
    }

    private func capture(_ scWindow: SCWindow, window: WindowInfo, maxPixelSize: CGSize) async -> CGImage? {
        let target = Self.pixelSize(for: window.bounds, fitting: maxPixelSize)

        let configuration = SCStreamConfiguration()
        configuration.width = target.width
        configuration.height = target.height
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard let captured = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ), !Task.isCancelled else {
            return nil
        }

        let image = captured.width > target.width ? Self.downsample(captured, to: target) ?? captured : captured
        store(image, for: scWindow.windowID, bounds: window.bounds)
        return image
    }

    private static func downsample(_ image: CGImage, to size: (width: Int, height: Int)) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    static func pixelSize(for bounds: CGRect, fitting maximum: CGSize) -> (width: Int, height: Int) {
        guard bounds.width > 0, bounds.height > 0 else {
            return (max(2, Int(maximum.width)), max(2, Int(maximum.height)))
        }
        let scale = min(maximum.width / bounds.width, maximum.height / bounds.height, 2)
        return (max(2, Int((bounds.width * scale).rounded())), max(2, Int((bounds.height * scale).rounded())))
    }
}
