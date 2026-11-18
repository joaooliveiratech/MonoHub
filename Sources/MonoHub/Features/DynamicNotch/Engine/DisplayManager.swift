import AppKit
import CoreGraphics
import Foundation
import Observation

nonisolated struct ScreenInfo: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let isBuiltin: Bool
    let hasHardwareNotch: Bool
    let safeAreaTop: CGFloat
    let frame: CGRect

    var resolutionString: String {
        "\(Int(frame.width)) × \(Int(frame.height))"
    }

    var notchTypeDescription: String {
        hasHardwareNotch ? localized("Physical notch") : localized("Virtual notch")
    }
}

nonisolated struct ScreenNotchGeometry: Sendable, Equatable {
    let hasHardwareNotch: Bool
    let screenFrame: CGRect
    let safeAreaTop: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let topBezelOffset: CGFloat

    init(
        hasHardwareNotch: Bool,
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        topBezelOffset: CGFloat = 0
    ) {
        self.hasHardwareNotch = hasHardwareNotch
        self.screenFrame = screenFrame
        self.safeAreaTop = safeAreaTop
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.topBezelOffset = topBezelOffset
    }

    static let standardHeaderHeight: CGFloat = 46

    var expandedHeaderHeight: CGFloat {
        hasHardwareNotch ? max(notchHeight, 32) + 34 : Self.standardHeaderHeight
    }

    var expandedNotchGap: CGFloat {
        hasHardwareNotch ? notchWidth + 16 : 0
    }
}

@Observable
@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    private(set) var screenInfos: [ScreenInfo] = []

    var hasPhysicalNotch: Bool {
        screenInfos.contains { $0.hasHardwareNotch }
    }

    private struct PhysicalScreenMetrics: Equatable {
        let frame: CGRect
        let visibleMaxY: CGFloat
        let safeAreaTop: CGFloat
        let auxiliaryLeftWidth: CGFloat?
        let auxiliaryRightWidth: CGFloat?
    }

    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var physicalMetricsCache: [String: PhysicalScreenMetrics] = [:]
    @ObservationIgnored private(set) var topBandFrames: [CGRect] = []

    private init() {}

    func start() {
        refreshDisplays()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DisplayManager.shared.refreshDisplays()
            }
        }
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        physicalMetricsCache.removeAll()
        topBandFrames.removeAll()
    }

    func refreshDisplays() {
        var nextCache: [String: PhysicalScreenMetrics] = [:]
        var nextTopBands: [CGRect] = []
        let infos = NSScreen.screens.map { screen in
            let id = screenIdentifier(for: screen)
            let safeTop = screen.safeAreaInsets.top
            let frame = screen.frame
            nextCache[id] = PhysicalScreenMetrics(
                frame: frame,
                visibleMaxY: screen.visibleFrame.maxY,
                safeAreaTop: safeTop,
                auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width
            )
            nextTopBands.append(CGRect(x: frame.minX, y: frame.maxY - 90, width: frame.width, height: 90))
            return ScreenInfo(
                id: id,
                name: screen.localizedName,
                isBuiltin: isScreenBuiltin(screen),
                hasHardwareNotch: safeTop > 0,
                safeAreaTop: safeTop,
                frame: frame
            )
        }
        physicalMetricsCache = nextCache
        topBandFrames = nextTopBands
        if infos != screenInfos {
            screenInfos = infos
        }
    }

    private func cachedMetrics(for screen: NSScreen) -> PhysicalScreenMetrics {
        let id = screenIdentifier(for: screen)
        if let cached = physicalMetricsCache[id] {
            return cached
        }
        let metrics = PhysicalScreenMetrics(
            frame: screen.frame,
            visibleMaxY: screen.visibleFrame.maxY,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width
        )
        physicalMetricsCache[id] = metrics
        return metrics
    }

    func isScreenEnabled(_ screen: NSScreen) -> Bool {
        let prefs = NotchPreferences.shared
        let id = screenIdentifier(for: screen)
        let isBuiltin = isScreenBuiltin(screen)
        let isMain = screen == NSScreen.main
        let hasHardwareNotch = cachedMetrics(for: screen).safeAreaTop > 0

        if !hasHardwareNotch && !prefs.enableVirtualNotch {
            return false
        }

        return prefs.isDisplayEnabled(id: id, isBuiltin: isBuiltin, isMain: isMain)
    }

    func screenIdentifier(for screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(num)
        }
        return screen.localizedName
    }

    func isScreenBuiltin(_ screen: NSScreen) -> Bool {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return CGDisplayIsBuiltin(num) != 0
        }
        return screen.safeAreaInsets.top > 0
    }

    static func calculateGeometry(for screen: NSScreen?, preferences: NotchPreferences) -> ScreenNotchGeometry {
        guard let screen = screen else {
            return ScreenNotchGeometry(
                hasHardwareNotch: false,
                screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                safeAreaTop: 0,
                notchWidth: preferences.closedNotchWidth,
                notchHeight: preferences.closedNotchHeight
            )
        }

        let metrics = DisplayManager.shared.cachedMetrics(for: screen)
        let hasNotch = metrics.safeAreaTop > 0
        var calculatedWidth: CGFloat = preferences.closedNotchWidth
        var calculatedHeight: CGFloat = preferences.closedNotchHeight

        if hasNotch {
            calculatedHeight = metrics.safeAreaTop
            var physicalWidth: CGFloat = 185
            if let leftPadding = metrics.auxiliaryLeftWidth,
               let rightPadding = metrics.auxiliaryRightWidth {
                physicalWidth = metrics.frame.width - leftPadding - rightPadding
            }
            calculatedWidth = physicalWidth
        } else {
            if preferences.enableVirtualNotch {
                let menuBarHeight = max(24, metrics.frame.maxY - metrics.visibleMaxY)
                calculatedHeight = max(preferences.closedNotchHeight, menuBarHeight)
                calculatedWidth = preferences.closedNotchWidth
            } else {
                calculatedWidth = preferences.closedNotchWidth
                calculatedHeight = preferences.closedNotchHeight
            }
        }

        return ScreenNotchGeometry(
            hasHardwareNotch: hasNotch,
            screenFrame: metrics.frame,
            safeAreaTop: metrics.safeAreaTop,
            notchWidth: calculatedWidth,
            notchHeight: calculatedHeight
        )
    }
}
