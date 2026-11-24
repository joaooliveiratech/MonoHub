import AppKit
import Foundation
import os
import ServiceManagement

@MainActor
@Observable
final class TilePreferencesManager {
    static let shared = TilePreferencesManager(defaults: .standard)

    static let marginRange: ClosedRange<CGFloat> = 0...32
    static let gapRange: ClosedRange<CGFloat> = 0...32
    static let snapThresholdRange: ClosedRange<CGFloat> = 10...60
    static let stepRange: ClosedRange<CGFloat> = 10...200
    static let almostMaximizeRange: ClosedRange<CGFloat> = 70...95

    private enum Keys {
        static let outerMargin = "MonoHub_Tile_outerMargin"
        static let windowGap = "MonoHub_Tile_windowGap"
        static let isSnapEnabled = "MonoHub_Tile_isSnapEnabled"
        static let isSnapPreviewEnabled = "MonoHub_Tile_isSnapPreviewEnabled"
        static let snapThreshold = "MonoHub_Tile_snapThreshold"
        static let cycleRepeatedShortcuts = "MonoHub_Tile_cycleRepeatedShortcuts"
        static let repeatBehavior = "MonoHub_Tile_repeatBehavior"
        static let customShortcuts = "MonoHub_Tile_customShortcuts"
        static let disabledShortcuts = "MonoHub_Tile_disabledShortcuts"
        static let marginOnMaximize = "MonoHub_Tile_marginOnMaximize"
        static let actionStep = "MonoHub_Tile_actionStep"
        static let almostMaximizePercent = "MonoHub_Tile_almostMaximizePercent"
        static let bottomEdgeBehavior = "MonoHub_Tile_bottomEdgeBehavior"
        static let isSnapHapticEnabled = "MonoHub_Tile_isSnapHapticEnabled"
        static let restoresSizeOnDrag = "MonoHub_Tile_restoresSizeOnDrag"
        static let isModifierDragEnabled = "MonoHub_Tile_isModifierDragEnabled"
        static let dragModifier = "MonoHub_Tile_dragModifier"
        static let excludedBundleIdentifiers = "MonoHub_Tile_excludedBundleIdentifiers"
        static let showMenuBarIcon = "MonoHub_Tile_showMenuBarIcon"
        static let moveToAdjacentDisplayOnEdge = "MonoHub_Tile_moveToAdjacentDisplayOnEdge"
        static let focusScope = "MonoHub_Tile_focusScope"
        static let directionalFocusFallback = "MonoHub_Tile_directionalFocusFallback"
        static let showFocusHUD = "MonoHub_Tile_showFocusHUD"
        static let warpCursorOnFocus = "MonoHub_Tile_warpCursorOnFocus"

        static let legacyOuterMargin = "outerMargin"
        static let legacyWindowGap = "windowGap"
        static let legacyIsSnapEnabled = "isSnapEnabled"
        static let legacyIsSnapPreviewEnabled = "isSnapPreviewEnabled"
        static let legacySnapThreshold = "snapThreshold"
        static let legacyCycleRepeatedShortcuts = "cycleRepeatedShortcuts"
        static let legacyRepeatBehavior = "repeatBehavior"
        static let legacyCustomShortcuts = "customShortcuts"
        static let legacyDisabledShortcuts = "disabledShortcuts"
        static let legacyMarginOnMaximize = "marginOnMaximize"
        static let legacyActionStep = "actionStep"
        static let legacyAlmostMaximizePercent = "almostMaximizePercent"
        static let legacyBottomEdgeBehavior = "bottomEdgeBehavior"
        static let legacyIsSnapHapticEnabled = "isSnapHapticEnabled"
        static let legacyRestoresSizeOnDrag = "restoresSizeOnDrag"
        static let legacyIsModifierDragEnabled = "isModifierDragEnabled"
        static let legacyDragModifier = "dragModifier"
        static let legacyExcludedBundleIdentifiers = "excludedBundleIdentifiers"
        static let legacyShowMenuBarIcon = "showMenuBarIcon"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var outerMargin: CGFloat {
        didSet { defaults.set(Double(outerMargin), forKey: Keys.outerMargin) }
    }

    var windowGap: CGFloat {
        didSet { defaults.set(Double(windowGap), forKey: Keys.windowGap) }
    }

    var isSnapEnabled: Bool {
        didSet { defaults.set(isSnapEnabled, forKey: Keys.isSnapEnabled) }
    }

    var isSnapPreviewEnabled: Bool {
        didSet { defaults.set(isSnapPreviewEnabled, forKey: Keys.isSnapPreviewEnabled) }
    }

    var snapThreshold: CGFloat {
        didSet { defaults.set(Double(snapThreshold), forKey: Keys.snapThreshold) }
    }

    var repeatBehavior: RepeatBehavior {
        didSet {
            defaults.set(repeatBehavior.rawValue, forKey: Keys.repeatBehavior)
            if repeatBehavior == .moveAcrossDisplays && !moveToAdjacentDisplayOnEdge {
                moveToAdjacentDisplayOnEdge = true
            }
        }
    }

    var moveToAdjacentDisplayOnEdge: Bool {
        didSet { defaults.set(moveToAdjacentDisplayOnEdge, forKey: Keys.moveToAdjacentDisplayOnEdge) }
    }

    var marginOnMaximize: Bool {
        didSet { defaults.set(marginOnMaximize, forKey: Keys.marginOnMaximize) }
    }

    var actionStep: CGFloat {
        didSet { defaults.set(Double(actionStep), forKey: Keys.actionStep) }
    }

    var almostMaximizePercent: CGFloat {
        didSet { defaults.set(Double(almostMaximizePercent), forKey: Keys.almostMaximizePercent) }
    }

    var bottomEdgeBehavior: BottomEdgeBehavior {
        didSet { defaults.set(bottomEdgeBehavior.rawValue, forKey: Keys.bottomEdgeBehavior) }
    }

    var isSnapHapticEnabled: Bool {
        didSet { defaults.set(isSnapHapticEnabled, forKey: Keys.isSnapHapticEnabled) }
    }

    var restoresSizeOnDrag: Bool {
        didSet { defaults.set(restoresSizeOnDrag, forKey: Keys.restoresSizeOnDrag) }
    }

    var isModifierDragEnabled: Bool {
        didSet { defaults.set(isModifierDragEnabled, forKey: Keys.isModifierDragEnabled) }
    }

    var dragModifier: DragModifier {
        didSet { defaults.set(dragModifier.rawValue, forKey: Keys.dragModifier) }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    var focusScope: FocusScope {
        didSet { defaults.set(focusScope.rawValue, forKey: Keys.focusScope) }
    }

    var directionalFocusFallback: DirectionalFocusFallback {
        didSet { defaults.set(directionalFocusFallback.rawValue, forKey: Keys.directionalFocusFallback) }
    }

    var showFocusHUD: Bool {
        didSet { defaults.set(showFocusHUD, forKey: Keys.showFocusHUD) }
    }

    var warpCursorOnFocus: Bool {
        didSet { defaults.set(warpCursorOnFocus, forKey: Keys.warpCursorOnFocus) }
    }

    private(set) var excludedBundleIdentifiers: [String] = []
    @ObservationIgnored private var excludedBundleSet: Set<String> = []
    @ObservationIgnored private var pidBundleCache: [pid_t: String] = [:]

    var activeShortcutCount: Int {
        WindowAction.allCases.reduce(into: 0) { count, action in
            if shortcut(for: action) != nil { count += 1 }
        }
    }

    var tileOptions: TileOptions {
        TileOptions(
            margin: outerMargin,
            gap: windowGap,
            step: actionStep,
            almostMaximizeRatio: almostMaximizePercent / 100,
            marginOnMaximize: marginOnMaximize
        )
    }

    var isMouseTrackingNeeded: Bool {
        isSnapEnabled || restoresSizeOnDrag
    }

    private(set) var customShortcuts: [String: ShortcutKey] = [:]
    private(set) var disabledShortcuts: Set<String> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults

        func readDouble(primary: String, fallback: String, defaultVal: Double) -> Double {
            if defaults.object(forKey: primary) != nil {
                return defaults.double(forKey: primary)
            }
            if defaults.object(forKey: fallback) != nil {
                return defaults.double(forKey: fallback)
            }
            return defaultVal
        }

        func readBool(primary: String, fallback: String, defaultVal: Bool) -> Bool {
            if defaults.object(forKey: primary) != nil {
                return defaults.bool(forKey: primary)
            }
            if defaults.object(forKey: fallback) != nil {
                return defaults.bool(forKey: fallback)
            }
            return defaultVal
        }

        func readString(primary: String, fallback: String) -> String? {
            defaults.string(forKey: primary) ?? defaults.string(forKey: fallback)
        }

        outerMargin = CGFloat(readDouble(primary: Keys.outerMargin, fallback: Keys.legacyOuterMargin, defaultVal: 0.0)).clamped(to: Self.marginRange)
        windowGap = CGFloat(readDouble(primary: Keys.windowGap, fallback: Keys.legacyWindowGap, defaultVal: 0.0)).clamped(to: Self.gapRange)
        isSnapEnabled = readBool(primary: Keys.isSnapEnabled, fallback: Keys.legacyIsSnapEnabled, defaultVal: true)
        isSnapPreviewEnabled = readBool(primary: Keys.isSnapPreviewEnabled, fallback: Keys.legacyIsSnapPreviewEnabled, defaultVal: true)
        snapThreshold = CGFloat(readDouble(primary: Keys.snapThreshold, fallback: Keys.legacySnapThreshold, defaultVal: 25.0)).clamped(to: Self.snapThresholdRange)

        let repStr = readString(primary: Keys.repeatBehavior, fallback: Keys.legacyRepeatBehavior)
        let legacyCycle = readBool(primary: Keys.cycleRepeatedShortcuts, fallback: Keys.legacyCycleRepeatedShortcuts, defaultVal: true)
        repeatBehavior = repStr.flatMap(RepeatBehavior.init(rawValue:)) ?? (legacyCycle ? .cycleSizes : .none)
        if defaults.object(forKey: Keys.moveToAdjacentDisplayOnEdge) != nil {
            moveToAdjacentDisplayOnEdge = defaults.bool(forKey: Keys.moveToAdjacentDisplayOnEdge)
        } else {
            moveToAdjacentDisplayOnEdge = true
        }

        marginOnMaximize = readBool(primary: Keys.marginOnMaximize, fallback: Keys.legacyMarginOnMaximize, defaultVal: true)
        actionStep = CGFloat(readDouble(primary: Keys.actionStep, fallback: Keys.legacyActionStep, defaultVal: 50.0)).clamped(to: Self.stepRange)
        almostMaximizePercent = CGFloat(readDouble(primary: Keys.almostMaximizePercent, fallback: Keys.legacyAlmostMaximizePercent, defaultVal: 90.0)).clamped(to: Self.almostMaximizeRange)

        let bottomStr = readString(primary: Keys.bottomEdgeBehavior, fallback: Keys.legacyBottomEdgeBehavior)
        bottomEdgeBehavior = bottomStr.flatMap(BottomEdgeBehavior.init(rawValue:)) ?? .thirds

        isSnapHapticEnabled = readBool(primary: Keys.isSnapHapticEnabled, fallback: Keys.legacyIsSnapHapticEnabled, defaultVal: true)
        restoresSizeOnDrag = readBool(primary: Keys.restoresSizeOnDrag, fallback: Keys.legacyRestoresSizeOnDrag, defaultVal: true)
        isModifierDragEnabled = readBool(primary: Keys.isModifierDragEnabled, fallback: Keys.legacyIsModifierDragEnabled, defaultVal: false)

        let modStr = readString(primary: Keys.dragModifier, fallback: Keys.legacyDragModifier)
        dragModifier = modStr.flatMap(DragModifier.init(rawValue:)) ?? .controlOption

        showMenuBarIcon = readBool(primary: Keys.showMenuBarIcon, fallback: Keys.legacyShowMenuBarIcon, defaultVal: false)

        focusScope = defaults.string(forKey: Keys.focusScope).flatMap(FocusScope.init(rawValue:)) ?? .allDisplays
        directionalFocusFallback = defaults.string(forKey: Keys.directionalFocusFallback).flatMap(DirectionalFocusFallback.init(rawValue:)) ?? .lastWindow
        showFocusHUD = defaults.object(forKey: Keys.showFocusHUD) != nil ? defaults.bool(forKey: Keys.showFocusHUD) : true
        warpCursorOnFocus = defaults.bool(forKey: Keys.warpCursorOnFocus)

        let excluded = defaults.stringArray(forKey: Keys.excludedBundleIdentifiers) ?? defaults.stringArray(forKey: Keys.legacyExcludedBundleIdentifiers) ?? []
        excludedBundleIdentifiers = Self.sanitizedBundleIdentifiers(excluded)
        excludedBundleSet = Set(excludedBundleIdentifiers)

        loadShortcuts()
    }

    func shortcut(for action: WindowAction) -> ShortcutKey? {
        if disabledShortcuts.contains(action.rawValue) {
            return nil
        }
        return customShortcuts[action.rawValue] ?? action.defaultShortcut
    }

    func action(using shortcut: ShortcutKey) -> WindowAction? {
        WindowAction.allCases.first { self.shortcut(for: $0) == shortcut }
    }

    @discardableResult
    func setShortcut(_ shortcut: ShortcutKey?, for action: WindowAction) -> WindowAction? {
        var displaced: WindowAction?
        if let shortcut, let owner = self.action(using: shortcut), owner != action {
            assign(nil, to: owner)
            displaced = owner
        }
        assign(shortcut, to: action)
        persistShortcuts()
        return displaced
    }

    func resetShortcutsToDefaults() {
        customShortcuts.removeAll()
        disabledShortcuts.removeAll()
        persistShortcuts()
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedBundleSet.contains(bundleIdentifier)
    }

    func isExcluded(processIdentifier: pid_t) -> Bool {
        guard !excludedBundleSet.isEmpty else { return false }
        if let cached = pidBundleCache[processIdentifier] {
            return excludedBundleSet.contains(cached)
        }
        guard let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier else {
            return false
        }
        if pidBundleCache.count > 128 {
            pidBundleCache.removeAll(keepingCapacity: true)
        }
        pidBundleCache[processIdentifier] = bundleIdentifier
        return excludedBundleSet.contains(bundleIdentifier)
    }

    func invalidateProcessCache(pid: pid_t) {
        pidBundleCache.removeValue(forKey: pid)
    }

    func setExcluded(_ excluded: Bool, bundleIdentifier: String) {
        var identifiers = excludedBundleSet
        if excluded {
            identifiers.insert(bundleIdentifier)
        } else {
            identifiers.remove(bundleIdentifier)
        }
        excludedBundleIdentifiers = Self.sanitizedBundleIdentifiers(Array(identifiers))
        excludedBundleSet = Set(excludedBundleIdentifiers)
        defaults.set(excludedBundleIdentifiers, forKey: Keys.excludedBundleIdentifiers)
    }

    static func sanitizedBundleIdentifiers(_ identifiers: [String]) -> [String] {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return Set(identifiers)
            .filter { !$0.isEmpty && $0.count <= 255 && $0.unicodeScalars.allSatisfy(allowed.contains) }
            .sorted()
    }

    private func assign(_ shortcut: ShortcutKey?, to action: WindowAction) {
        let key = action.rawValue
        guard let shortcut else {
            customShortcuts.removeValue(forKey: key)
            disabledShortcuts.insert(key)
            return
        }
        disabledShortcuts.remove(key)
        if shortcut == action.defaultShortcut {
            customShortcuts.removeValue(forKey: key)
        } else {
            customShortcuts[key] = shortcut
        }
    }

    private static let actionKeys = Set(WindowAction.allCases.map(\.rawValue))

    private func loadShortcuts() {
        let data = defaults.data(forKey: Keys.customShortcuts) ?? defaults.data(forKey: Keys.legacyCustomShortcuts)
        if let data {
            do {
                let decoded = try JSONDecoder().decode([String: ShortcutKey].self, from: data)
                customShortcuts = decoded.filter { Self.actionKeys.contains($0.key) && $0.value.isValidGlobalShortcut }
            } catch {
                NSLog("MonoHub: Falha ao decodificar atalhos personalizados: \(error.localizedDescription)")
            }
        }
        let disabledList = defaults.stringArray(forKey: Keys.disabledShortcuts) ?? defaults.stringArray(forKey: Keys.legacyDisabledShortcuts)
        if let disabledList {
            disabledShortcuts = Set(disabledList).intersection(Self.actionKeys)
        }
        removeDuplicateShortcuts()
    }

    private func removeDuplicateShortcuts() {
        var seen: Set<ShortcutKey> = []
        for action in WindowAction.allCases {
            guard let shortcut = shortcut(for: action) else { continue }
            if seen.contains(shortcut) {
                assign(nil, to: action)
            } else {
                seen.insert(shortcut)
            }
        }
    }

    private func persistShortcuts() {
        do {
            defaults.set(try JSONEncoder().encode(customShortcuts), forKey: Keys.customShortcuts)
        } catch {
            NSLog("MonoHub: Falha ao codificar atalhos personalizados: \(error.localizedDescription)")
        }
        defaults.set(disabledShortcuts.sorted(), forKey: Keys.disabledShortcuts)
    }
}

struct PreferencesSnapshot: Codable, Sendable {
    static let currentVersion = 1

    var version = PreferencesSnapshot.currentVersion
    var outerMargin: Double?
    var windowGap: Double?
    var isSnapEnabled: Bool?
    var isSnapPreviewEnabled: Bool?
    var snapThreshold: Double?
    var repeatBehavior: String?
    var marginOnMaximize: Bool?
    var actionStep: Double?
    var almostMaximizePercent: Double?
    var bottomEdgeBehavior: String?
    var isSnapHapticEnabled: Bool?
    var restoresSizeOnDrag: Bool?
    var isModifierDragEnabled: Bool?
    var dragModifier: String?
    var customShortcuts: [String: ShortcutKey]?
    var disabledShortcuts: [String]?
    var excludedBundleIdentifiers: [String]?
    var showMenuBarIcon: Bool?
    var moveToAdjacentDisplayOnEdge: Bool?
    var focusScope: String?
    var directionalFocusFallback: String?
    var showFocusHUD: Bool?
    var warpCursorOnFocus: Bool?
}

extension TilePreferencesManager {
    func snapshot() -> PreferencesSnapshot {
        PreferencesSnapshot(
            outerMargin: Double(outerMargin),
            windowGap: Double(windowGap),
            isSnapEnabled: isSnapEnabled,
            isSnapPreviewEnabled: isSnapPreviewEnabled,
            snapThreshold: Double(snapThreshold),
            repeatBehavior: repeatBehavior.rawValue,
            marginOnMaximize: marginOnMaximize,
            actionStep: Double(actionStep),
            almostMaximizePercent: Double(almostMaximizePercent),
            bottomEdgeBehavior: bottomEdgeBehavior.rawValue,
            isSnapHapticEnabled: isSnapHapticEnabled,
            restoresSizeOnDrag: restoresSizeOnDrag,
            isModifierDragEnabled: isModifierDragEnabled,
            dragModifier: dragModifier.rawValue,
            customShortcuts: customShortcuts,
            disabledShortcuts: disabledShortcuts.sorted(),
            excludedBundleIdentifiers: excludedBundleIdentifiers,
            showMenuBarIcon: showMenuBarIcon,
            moveToAdjacentDisplayOnEdge: moveToAdjacentDisplayOnEdge,
            focusScope: focusScope.rawValue,
            directionalFocusFallback: directionalFocusFallback.rawValue,
            showFocusHUD: showFocusHUD,
            warpCursorOnFocus: warpCursorOnFocus
        )
    }

    func apply(_ snapshot: PreferencesSnapshot) {
        if let value = snapshot.outerMargin { outerMargin = CGFloat(value).clamped(to: Self.marginRange) }
        if let value = snapshot.windowGap { windowGap = CGFloat(value).clamped(to: Self.gapRange) }
        if let value = snapshot.isSnapEnabled { isSnapEnabled = value }
        if let value = snapshot.isSnapPreviewEnabled { isSnapPreviewEnabled = value }
        if let value = snapshot.snapThreshold { snapThreshold = CGFloat(value).clamped(to: Self.snapThresholdRange) }
        if let value = snapshot.repeatBehavior.flatMap(RepeatBehavior.init(rawValue:)) { repeatBehavior = value }
        if let value = snapshot.moveToAdjacentDisplayOnEdge { moveToAdjacentDisplayOnEdge = value }
        if let value = snapshot.marginOnMaximize { marginOnMaximize = value }
        if let value = snapshot.actionStep { actionStep = CGFloat(value).clamped(to: Self.stepRange) }
        if let value = snapshot.almostMaximizePercent { almostMaximizePercent = CGFloat(value).clamped(to: Self.almostMaximizeRange) }
        if let value = snapshot.bottomEdgeBehavior.flatMap(BottomEdgeBehavior.init(rawValue:)) { bottomEdgeBehavior = value }
        if let value = snapshot.isSnapHapticEnabled { isSnapHapticEnabled = value }
        if let value = snapshot.restoresSizeOnDrag { restoresSizeOnDrag = value }
        if let value = snapshot.dragModifier.flatMap(DragModifier.init(rawValue:)) { dragModifier = value }
        if let value = snapshot.isModifierDragEnabled { isModifierDragEnabled = value }
        if let value = snapshot.showMenuBarIcon { showMenuBarIcon = value }
        if let value = snapshot.focusScope.flatMap(FocusScope.init(rawValue:)) { focusScope = value }
        if let value = snapshot.directionalFocusFallback.flatMap(DirectionalFocusFallback.init(rawValue:)) { directionalFocusFallback = value }
        if let value = snapshot.showFocusHUD { showFocusHUD = value }
        if let value = snapshot.warpCursorOnFocus { warpCursorOnFocus = value }

        if let identifiers = snapshot.excludedBundleIdentifiers {
            excludedBundleIdentifiers = Self.sanitizedBundleIdentifiers(identifiers)
            excludedBundleSet = Set(excludedBundleIdentifiers)
            defaults.set(excludedBundleIdentifiers, forKey: Keys.excludedBundleIdentifiers)
        }

        if snapshot.customShortcuts != nil || snapshot.disabledShortcuts != nil {
            customShortcuts = (snapshot.customShortcuts ?? [:])
                .filter { Self.actionKeys.contains($0.key) && $0.value.isValidGlobalShortcut }
            disabledShortcuts = Set(snapshot.disabledShortcuts ?? []).intersection(Self.actionKeys)
            removeDuplicateShortcuts()
            persistShortcuts()
        }
    }
}
