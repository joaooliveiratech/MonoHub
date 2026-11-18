import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import MonoHub

@Suite("Window Tiling Calculations")
@MainActor
struct TileCalculationTests {
    let sampleScreen = ScreenLayout(
        bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleBounds: CGRect(x: 0, y: 25, width: 1920, height: 1055)
    )

    let currentWindow = CGRect(x: 200, y: 200, width: 800, height: 600)

    @Test("Left Half calculation")
    func testLeftHalf() {
        let result = TileCalculation.calculate(
            action: .leftHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(),
            cycleIndex: 0
        )
        #expect(result.origin.x == 0)
        #expect(result.origin.y == 25)
        #expect(result.width == 960)
        #expect(result.height == 1055)
    }

    @Test("Right Half calculation")
    func testRightHalf() {
        let result = TileCalculation.calculate(
            action: .rightHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(),
            cycleIndex: 0
        )
        #expect(result.origin.x == 960)
        #expect(result.origin.y == 25)
        #expect(result.width == 960)
        #expect(result.height == 1055)
    }

    @Test("Top Half calculation")
    func testTopHalf() {
        let result = TileCalculation.calculate(
            action: .topHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(),
            cycleIndex: 0
        )
        #expect(result.origin.x == 0)
        #expect(result.origin.y == 25)
        #expect(result.width == 1920)
        #expect(result.height == 527.5)
    }

    @Test("Bottom Half calculation")
    func testBottomHalf() {
        let result = TileCalculation.calculate(
            action: .bottomHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(),
            cycleIndex: 0
        )
        #expect(result.origin.x == 0)
        #expect(result.origin.y == 25 + 527.5)
        #expect(result.width == 1920)
        #expect(result.height == 527.5)
    }

    @Test("Maximize calculation")
    func testMaximize() {
        let result = TileCalculation.calculate(
            action: .maximize,
            screen: sampleScreen,
            currentFrame: currentWindow
        )
        #expect(result == sampleScreen.visibleBounds)
    }

    @Test("Quarters calculation")
    func testQuarters() {
        let tl = TileCalculation.calculate(action: .topLeftQuarter, screen: sampleScreen, currentFrame: currentWindow)
        let tr = TileCalculation.calculate(action: .topRightQuarter, screen: sampleScreen, currentFrame: currentWindow)
        let bl = TileCalculation.calculate(action: .bottomLeftQuarter, screen: sampleScreen, currentFrame: currentWindow)
        let br = TileCalculation.calculate(action: .bottomRightQuarter, screen: sampleScreen, currentFrame: currentWindow)

        #expect(tl.origin.x == 0)
        #expect(tl.origin.y == 25)
        #expect(tl.width == 960)
        #expect(tl.height == 527.5)

        #expect(tr.origin.x == 960)
        #expect(tr.origin.y == 25)

        #expect(bl.origin.x == 0)
        #expect(bl.origin.y == 25 + 527.5)

        #expect(br.origin.x == 960)
        #expect(br.origin.y == 25 + 527.5)
    }

    @Test("Margins and Gaps calculation")
    func testMarginsAndGaps() {
        let margin: CGFloat = 10
        let gap: CGFloat = 8

        let left = TileCalculation.calculate(
            action: .leftHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(margin: margin, gap: gap),
            cycleIndex: 0
        )

        let right = TileCalculation.calculate(
            action: .rightHalf,
            screen: sampleScreen,
            currentFrame: currentWindow,
            options: TileOptions(margin: margin, gap: gap),
            cycleIndex: 0
        )

        #expect(left.origin.x == margin)
        #expect(left.origin.y == 25 + margin)
        #expect(left.width == 946)

        #expect(right.origin.x == margin + 950 + 4)
        #expect(right.width == 946)
        #expect(right.origin.x - left.maxX == gap)
    }

    @Test("Cycling repeated Left Half (1/2 -> 2/3 -> 1/3)")
    func testCycling() {
        let step0 = TileCalculation.calculate(action: .leftHalf, screen: sampleScreen, currentFrame: currentWindow, cycleIndex: 0)
        let step1 = TileCalculation.calculate(action: .leftHalf, screen: sampleScreen, currentFrame: currentWindow, cycleIndex: 1)
        let step2 = TileCalculation.calculate(action: .leftHalf, screen: sampleScreen, currentFrame: currentWindow, cycleIndex: 2)

        #expect(step0.width == 960)
        #expect(abs(step1.width - (1920.0 * 2.0 / 3.0)) < 0.01)
        #expect(abs(step2.width - (1920.0 / 3.0)) < 0.01)
    }

    @Test("Multi-display translation")
    func testMultiDisplayTranslation() {
        let screenA = ScreenLayout(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleBounds: CGRect(x: 0, y: 25, width: 1920, height: 1055)
        )
        let screenB = ScreenLayout(
            bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            visibleBounds: CGRect(x: 1920, y: 25, width: 2560, height: 1415)
        )

        let windowOnA = CGRect(x: 0, y: 25, width: 960, height: 1055)
        let windowOnB = TileCalculation.translate(frame: windowOnA, from: screenA, to: screenB)

        #expect(windowOnB.origin.x == 1920)
        #expect(windowOnB.origin.y == 25)
        #expect(windowOnB.width == 1280)
    }
}

@Suite("Window Tiling Snap Areas")
@MainActor
struct SnapAreaTests {
    let screen = ScreenLayout(
        bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleBounds: CGRect(x: 0, y: 25, width: 1920, height: 1055)
    )

    @Test("Pointer inside the menu bar maximizes")
    func menuBarMaximizes() {
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 960, y: 2), screen: screen) == .maximize)
    }

    @Test("Edges map to halves")
    func edgesMapToHalves() {
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 0, y: 540), screen: screen) == .leftHalf)
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 1919, y: 540), screen: screen) == .rightHalf)
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 960, y: 1079), screen: screen) == .bottomHalf)
    }

    @Test("Corners map to quarters")
    func cornersMapToQuarters() {
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 5, y: 30), screen: screen) == .topLeftQuarter)
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 1915, y: 0), screen: screen) == .topRightQuarter)
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 5, y: 1075), screen: screen) == .bottomLeftQuarter)
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 1915, y: 1075), screen: screen) == .bottomRightQuarter)
    }

    @Test("Center of the screen does not snap")
    func centerDoesNotSnap() {
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 960, y: 540), screen: screen) == nil)
    }

    @Test("Pointer outside the screen does not snap")
    func outsideDoesNotSnap() {
        #expect(SnapArea.evaluate(mousePoint: CGPoint(x: 2500, y: 540), screen: screen) == nil)
    }

    @Test("Threshold widens the edge zone")
    func thresholdWidensZone() {
        let point = CGPoint(x: 40, y: 540)
        #expect(SnapArea.evaluate(mousePoint: point, screen: screen, threshold: 25) == nil)
        #expect(SnapArea.evaluate(mousePoint: point, screen: screen, threshold: 50) == .leftHalf)
    }

    @Test("Screen lookup prefers the display containing the window center")
    func screenLookup() {
        let secondary = ScreenLayout(
            bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            visibleBounds: CGRect(x: 1920, y: 25, width: 2560, height: 1415)
        )
        let layouts = [screen, secondary]
        let window = CGRect(x: 1800, y: 100, width: 800, height: 600)
        #expect(ScreenLayout.screen(for: window, in: layouts) == secondary)
        #expect(ScreenLayout.screen(containing: CGPoint(x: 100, y: 100), in: layouts) == screen)
    }
}

@Suite("Window Tiling Shortcuts")
@MainActor
struct ShortcutTests {
    private func makePreferences() -> TilePreferencesManager {
        let suiteName = "com.antigravity.monohub.tests.tile.shortcuts"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TilePreferencesManager(defaults: defaults)
    }

    @Test("Shift alone is not a valid global shortcut")
    func shiftOnlyIsRejected() {
        #expect(!ShortcutKey(kVK_ANSI_A, [.shift]).isValidGlobalShortcut)
        #expect(!ShortcutKey(kVK_ANSI_A, []).isValidGlobalShortcut)
        #expect(ShortcutKey(kVK_ANSI_A, [.option]).isValidGlobalShortcut)
        #expect(ShortcutKey(kVK_F5, []).isValidGlobalShortcut)
    }

    @Test("Display strings follow macOS modifier order")
    func displayOrder() {
        let shortcut = ShortcutKey(kVK_LeftArrow, [.command, .shift, .option, .control])
        #expect(shortcut.displayString == "⌃⌥⇧⌘←")
    }

    @Test("Default shortcuts are unique and valid")
    func defaultsAreUnique() {
        let shortcuts = WindowAction.allCases.compactMap(\.defaultShortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
        #expect(shortcuts.allSatisfy { $0.isValidGlobalShortcut })
    }

    @Test("Assigning a used shortcut moves it from the previous action")
    func conflictingShortcutMoves() {
        let prefs = makePreferences()
        let leftHalf = WindowAction.leftHalf.defaultShortcut!

        let displaced = prefs.setShortcut(leftHalf, for: .center)

        #expect(displaced == .leftHalf)
        #expect(prefs.shortcut(for: .center) == leftHalf)
        #expect(prefs.shortcut(for: .leftHalf) == nil)
    }

    @Test("Assigning the default shortcut drops the custom override")
    func defaultShortcutIsNotStoredAsCustom() {
        let prefs = makePreferences()
        prefs.setShortcut(ShortcutKey(kVK_ANSI_L, [.control, .option]), for: .leftHalf)
        #expect(prefs.customShortcuts[WindowAction.leftHalf.rawValue] != nil)

        prefs.setShortcut(WindowAction.leftHalf.defaultShortcut, for: .leftHalf)
        #expect(prefs.customShortcuts.isEmpty)
        #expect(prefs.disabledShortcuts.isEmpty)
    }

    @Test("Restore defaults clears custom and disabled shortcuts")
    func restoreDefaults() {
        let prefs = makePreferences()
        prefs.setShortcut(nil, for: .maximize)
        prefs.setShortcut(ShortcutKey(kVK_ANSI_L, [.control, .option]), for: .center)

        prefs.resetShortcutsToDefaults()

        #expect(prefs.shortcut(for: .maximize) == WindowAction.maximize.defaultShortcut)
        #expect(prefs.shortcut(for: .center) == WindowAction.center.defaultShortcut)
    }
}

@Suite("Window Tiling Actions")
@MainActor
struct WindowActionTests {
    @Test("Verify all WindowAction cases exist and have valid names and symbols")
    func testAllActions() {
        let all = WindowAction.allCases
        #expect(all.count >= 22)

        for action in all {
            #expect(!action.displayName.isEmpty)
            #expect(!action.sfSymbol.isEmpty)
            #expect(!action.id.isEmpty)
        }
    }

    @Test("Verify categories contain appropriate actions")
    func testCategories() {
        let halves = WindowAction.allCases.filter { $0.category == .halves }
        #expect(halves.contains(.leftHalf))
        #expect(halves.contains(.rightHalf))
        #expect(halves.contains(.topHalf))
        #expect(halves.contains(.bottomHalf))

        let quarters = WindowAction.allCases.filter { $0.category == .quarters }
        #expect(quarters.count == 4)

        let thirds = WindowAction.allCases.filter { $0.category == .thirds }
        #expect(thirds.count == 5)

        let displays = WindowAction.allCases.filter { $0.category == .displays }
        #expect(displays.contains(.nextDisplay))
        #expect(displays.contains(.previousDisplay))
    }

    @Test("Verify standard Option+Shift default shortcuts are configured")
    func testDefaultShortcuts() {
        #expect(WindowAction.leftHalf.defaultShortcut != nil)
        #expect(WindowAction.rightHalf.defaultShortcut != nil)
        #expect(WindowAction.maximize.defaultShortcut != nil)
        #expect(WindowAction.center.defaultShortcut != nil)
        #expect(WindowAction.restore.defaultShortcut != nil)

        let leftShortcut = WindowAction.leftHalf.defaultShortcut!
        #expect(leftShortcut.modifiers.contains(.option))
        #expect(leftShortcut.modifiers.contains(.shift))
        #expect(!leftShortcut.modifiers.contains(.control))

        let rightShortcut = WindowAction.rightHalf.defaultShortcut!
        #expect(rightShortcut.modifiers.contains(.option))
        #expect(rightShortcut.modifiers.contains(.shift))
        #expect(!rightShortcut.modifiers.contains(.control))
    }
}

@Suite("Window Tiling Features & Integration")
@MainActor
struct TileFeatureTests {
    let screen = ScreenLayout(
        bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleBounds: CGRect(x: 0, y: 25, width: 1920, height: 1055)
    )

    private func makePreferences(_ suffix: String = "main") -> (TilePreferencesManager, UserDefaults) {
        let suiteName = "com.antigravity.monohub.tests.tile.\(suffix)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (TilePreferencesManager(defaults: defaults), defaults)
    }

    @Test("Command names round-trip through kebab case")
    func commandNames() {
        #expect(WindowAction.topLeftQuarter.commandName == "top-left-quarter")
        for action in WindowAction.allCases {
            #expect(WindowAction(commandName: action.commandName) == action)
        }
        #expect(WindowAction(commandName: "LeftHalf") == .leftHalf)
        #expect(WindowAction(commandName: "nope") == nil)
    }

    @Test("URL commands parse actions and settings for both monotile and monohub schemes")
    func urlCommands() {
        #expect(TileURLCommand(url: URL(string: "monotile://left-half")!) == .perform(.leftHalf))
        #expect(TileURLCommand(url: URL(string: "monotile:maximize")!) == .perform(.maximize))
        #expect(TileURLCommand(url: URL(string: "monotile://settings")!) == .settings)
        #expect(TileURLCommand(url: URL(string: "monohub://tile/left-half")!) == .perform(.leftHalf))
        #expect(TileURLCommand(url: URL(string: "monohub://tile")!) == .settings)
        #expect(TileURLCommand(url: URL(string: "https://left-half")!) == nil)
        #expect(TileURLCommand(url: URL(string: "monotile://rm-rf")!) == nil)
        #expect(TileURLCommand.perform(.nextDisplay).url.absoluteString == "monotile://next-display")
    }

    @Test("Bottom edge can snap to thirds")
    func bottomEdgeThirds() {
        func area(_ x: CGFloat) -> SnapArea? {
            SnapArea.evaluate(mousePoint: CGPoint(x: x, y: 1079), screen: screen, bottomEdge: .thirds)
        }
        #expect(area(300) == .firstThird)
        #expect(area(960) == .centerThird)
        #expect(area(1600) == .lastThird)
        #expect(area(5) == .bottomLeftQuarter)
    }

    @Test("Maximize can ignore the outer margin")
    func maximizeWithoutMargin() {
        let withMargin = TileCalculation.calculate(action: .maximize, screen: screen, currentFrame: .zero, options: TileOptions(margin: 10))
        let withoutMargin = TileCalculation.calculate(action: .maximize, screen: screen, currentFrame: .zero, options: TileOptions(margin: 10, marginOnMaximize: false))
        #expect(withMargin == screen.visibleBounds.insetBy(dx: 10, dy: 10))
        #expect(withoutMargin == screen.visibleBounds)
    }

    @Test("Almost Maximize and step follow options")
    func configurableSizes() {
        let almost = TileCalculation.calculate(action: .almostMaximize, screen: screen, currentFrame: .zero, options: TileOptions(almostMaximizeRatio: 0.8))
        #expect(abs(almost.width - 1920 * 0.8) < 0.01)

        let window = CGRect(x: 500, y: 300, width: 800, height: 600)
        let moved = TileCalculation.calculate(action: .moveRight, screen: screen, currentFrame: window, options: TileOptions(step: 120))
        #expect(moved.minX == 620)
    }

    @Test("Adjacent display lookup")
    func adjacentDisplays() {
        let left = ScreenLayout(bounds: CGRect(x: -1440, y: 0, width: 1440, height: 900), visibleBounds: CGRect(x: -1440, y: 25, width: 1440, height: 875))
        let right = ScreenLayout(bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440), visibleBounds: CGRect(x: 1920, y: 25, width: 2560, height: 1415))
        let layouts = [screen, left, right]
        #expect(ScreenLayout.neighbor(of: screen, toward: .left, in: layouts) == left)
        #expect(ScreenLayout.neighbor(of: screen, toward: .right, in: layouts) == right)
        #expect(ScreenLayout.neighbor(of: right, toward: .right, in: layouts) == nil)
    }

    @Test("Directional focus picks the nearest window in that direction")
    func directionalFocus() {
        let source = CGRect(x: 800, y: 400, width: 300, height: 300)
        let candidates = [
            source,
            CGRect(x: 100, y: 400, width: 300, height: 300),
            CGRect(x: 1400, y: 420, width: 300, height: 300),
            CGRect(x: 1300, y: 900, width: 300, height: 100),
            CGRect(x: 800, y: 0, width: 300, height: 200)
        ]
        #expect(WindowNavigator.nearest(from: source, toward: .left, among: candidates) == 1)
        #expect(WindowNavigator.nearest(from: source, toward: .right, among: candidates) == 2)
        #expect(WindowNavigator.nearest(from: source, toward: .up, among: candidates) == 4)
        #expect(WindowNavigator.nearest(from: source, toward: .down, among: candidates) == 3)
        #expect(WindowNavigator.nearest(from: source, toward: .left, among: [source]) == nil)
    }

    @Test("Excluded bundle identifiers are sanitized")
    func exclusions() {
        let (prefs, _) = makePreferences()
        prefs.setExcluded(true, bundleIdentifier: "com.apple.Safari")
        prefs.setExcluded(true, bundleIdentifier: "bad id/../")
        #expect(prefs.excludedBundleIdentifiers == ["com.apple.Safari"])
        #expect(prefs.isExcluded(bundleIdentifier: "com.apple.Safari"))
        prefs.setExcluded(false, bundleIdentifier: "com.apple.Safari")
        #expect(prefs.excludedBundleIdentifiers.isEmpty)
    }

    @Test("Imported snapshots are clamped and validated")
    func snapshotImport() {
        let (prefs, _) = makePreferences()
        let shiftOnly = ShortcutKey(kVK_ANSI_A, [.shift])
        let duplicate = WindowAction.leftHalf.defaultShortcut!
        var snapshot = PreferencesSnapshot()
        snapshot.outerMargin = 999
        snapshot.snapThreshold = -5
        snapshot.repeatBehavior = "bogus"
        snapshot.customShortcuts = ["center": shiftOnly, "maximize": duplicate, "unknownAction": duplicate]
        snapshot.excludedBundleIdentifiers = ["com.example.app", "../../etc"]

        prefs.apply(snapshot)

        #expect(prefs.outerMargin == TilePreferencesManager.marginRange.upperBound)
        #expect(prefs.snapThreshold == TilePreferencesManager.snapThresholdRange.lowerBound)
        #expect(prefs.repeatBehavior == .cycleSizes)
        #expect(prefs.shortcut(for: .center) == WindowAction.center.defaultShortcut)
        #expect(prefs.shortcut(for: .leftHalf) == duplicate)
        #expect(prefs.shortcut(for: .maximize) == nil)
        #expect(prefs.excludedBundleIdentifiers == ["com.example.app"])
    }

    @Test("Export and import round-trip through a private file")
    func backupRoundTrip() throws {
        let (source, _) = makePreferences()
        source.outerMargin = 12
        source.setShortcut(ShortcutKey(kVK_ANSI_L, [.control, .option]), for: .center)
        source.setExcluded(true, bundleIdentifier: "com.apple.Notes")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("monohub-tile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SettingsBackup.export(source, to: url)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.int16Value == 0o600)

        let (target, _) = makePreferences("target")
        try SettingsBackup.importSettings(into: target, from: url)
        #expect(target.outerMargin == 12)
        #expect(target.shortcut(for: .center) == ShortcutKey(kVK_ANSI_L, [.control, .option]))
        #expect(target.excludedBundleIdentifiers == ["com.apple.Notes"])
    }

    @Test("Menu bar visibility preference persists and roundtrips")
    func menuBarVisibilityPreference() {
        let (prefs, defaults) = makePreferences("source")
        #expect(prefs.showMenuBarIcon == false)

        prefs.showMenuBarIcon = true
        #expect(defaults.bool(forKey: "MonoHub_Tile_showMenuBarIcon") == true)

        var snapshot = prefs.snapshot()
        #expect(snapshot.showMenuBarIcon == true)

        let (target, _) = makePreferences("target")
        #expect(target.showMenuBarIcon == false)
        target.apply(snapshot)
        #expect(target.showMenuBarIcon == true)

        snapshot.showMenuBarIcon = false
        target.apply(snapshot)
        #expect(target.showMenuBarIcon == false)
    }
}

@Suite("Window Tiling Lifecycle")
@MainActor
struct TilingLifecycleTests {
    @Test("Deactivating an inactive module is a no-op")
    func deactivateWhileInactive() {
        #expect(!TilingFeature.isActive)
        TilingFeature.deactivate()
        TilingFeature.deactivate()
        #expect(!TilingFeature.isActive)
        #expect(!ModifierDragManager.shared.isRunning)
    }

    @Test("Releasing the snap preview without showing it is safe")
    func releaseSnapPreview() {
        SnapPreviewPanel.release()
        SnapPreviewPanel.release()
    }

    @Test("Mouse tracking is only needed when snapping or size restoration is on")
    func mouseTrackingNeeded() {
        let suite = "com.antigravity.monohub.tests.tile.tracking"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = TilePreferencesManager(defaults: defaults)
        prefs.isSnapEnabled = false
        prefs.restoresSizeOnDrag = false
        #expect(!prefs.isMouseTrackingNeeded)
        prefs.restoresSizeOnDrag = true
        #expect(prefs.isMouseTrackingNeeded)
    }

    @Test("Repeating Left/Right Half (⌥⇧H / ⌥⇧L) traverses across adjacent monitors")
    func crossMonitorTraversalOnRepeat() {
        let leftScreen = ScreenLayout(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleBounds: CGRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        let rightScreen = ScreenLayout(
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleBounds: CGRect(x: 1920, y: 0, width: 1920, height: 1055)
        )
        let layouts = [leftScreen, rightScreen]
        let options = TileOptions(margin: 0, gap: 0)

        // Start in center of right screen
        let initialFrame = CGRect(x: 2200, y: 100, width: 1200, height: 800)

        // 1st ⌥⇧H -> Not at left edge yet, so traversalTarget is nil and calculate places it on Left half of right screen
        #expect(TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: initialFrame,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)
        let step1Rect = TileCalculation.calculate(
            action: .leftHalf,
            screen: rightScreen,
            currentFrame: initialFrame,
            options: options,
            cycleIndex: 0
        )
        #expect(step1Rect.minX == 1920)
        #expect(step1Rect.width == 960)

        // 2nd ⌥⇧H (already at left edge of right screen) -> Crosses to Right half of left screen
        guard let step2 = TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: step1Rect,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: true
        ) else {
            Issue.record("Expected step 2 target on adjacent monitor")
            return
        }
        #expect(step2.1 == leftScreen)
        #expect(step2.0.minX == 960)
        #expect(step2.0.width == 960)

        // 3rd ⌥⇧H (now on right half of left screen) -> Moves to Left half of left screen
        #expect(TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: step2.0,
            screen: step2.1,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)
        let step3Rect = TileCalculation.calculate(
            action: .leftHalf,
            screen: step2.1,
            currentFrame: step2.0,
            options: options,
            cycleIndex: 0
        )
        #expect(step3Rect.minX == 0)
        #expect(step3Rect.width == 960)
    }

    @Test("Window at screen edge but not in target format adjusts on current monitor before traversing")
    func adjustsToFormatBeforeCrossMonitorTraversal() {
        let leftScreen = ScreenLayout(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleBounds: CGRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        let rightScreen = ScreenLayout(
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleBounds: CGRect(x: 1920, y: 0, width: 1920, height: 1055)
        )
        let layouts = [leftScreen, rightScreen]
        let options = TileOptions(margin: 0, gap: 0)

        // Window on the left edge of rightScreen, but shorter and narrower than leftHalf
        let nonStandardLeft = CGRect(x: 1920, y: 120, width: 650, height: 600)
        #expect(TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: nonStandardLeft,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)

        // Window in topLeftQuarter on rightScreen when leftHalf is triggered -> should snap to leftHalf first
        let quarterLeft = TileCalculation.calculate(action: .topLeftQuarter, screen: rightScreen, currentFrame: nonStandardLeft, options: options)
        #expect(TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: quarterLeft,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)

        // Window in firstThird on rightScreen when leftHalf is triggered -> should snap to leftHalf first
        let firstThird = TileCalculation.calculate(action: .firstThird, screen: rightScreen, currentFrame: nonStandardLeft, options: options)
        #expect(TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: firstThird,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)

        // Window on right edge of leftScreen with non-standard height -> should snap to rightHalf first
        let nonStandardRight = CGRect(x: 1920 - 700, y: 80, width: 700, height: 500)
        #expect(TileCalculation.traversalTarget(
            for: .rightHalf,
            frame: nonStandardRight,
            screen: leftScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        ) == nil)

        // Once snapped to full leftHalf, triggering leftHalf traverses to leftScreen's rightHalf
        let fullLeftHalf = TileCalculation.calculate(action: .leftHalf, screen: rightScreen, currentFrame: nonStandardLeft, options: options)
        let traversed = TileCalculation.traversalTarget(
            for: .leftHalf,
            frame: fullLeftHalf,
            screen: rightScreen,
            layouts: layouts,
            options: options,
            wasJustApplied: false
        )
        #expect(traversed?.1 == leftScreen)
        #expect(traversed?.0 == TileCalculation.calculate(action: .rightHalf, screen: leftScreen, currentFrame: fullLeftHalf, options: options))
    }
}
