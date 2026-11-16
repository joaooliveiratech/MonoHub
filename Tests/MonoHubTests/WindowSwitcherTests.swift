import CoreGraphics
import Foundation
import Testing
@testable import MonoHub

@Suite("WindowSwitcher - WindowInfo")
struct WindowSwitcherInfoTests {
    private func window(
        id: CGWindowID = 1,
        pid: pid_t = 100,
        appName: String = "App",
        title: String = "Window",
        isMinimized: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: pid,
            appName: appName,
            title: title,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMinimized: isMinimized
        )
    }

    @Test("Matches on app name and title, case insensitively")
    func matching() {
        let xcode = window(appName: "Xcode", title: "MonoHub — Package.swift")

        #expect(xcode.matches(query: "xcode"))
        #expect(xcode.matches(query: "XCODE"))
        #expect(xcode.matches(query: "xc"))
        #expect(xcode.matches(query: "Package"))
        #expect(xcode.matches(query: "monohub"))
        #expect(xcode.matches(query: ""))
        #expect(xcode.matches(query: "   "))
        #expect(!xcode.matches(query: "Safari"))
    }

    @Test("The normalized fast path agrees with the convenience overload")
    func normalizedMatching() {
        let slack = window(appName: "Slack", title: "general")
        #expect(slack.matchScore(normalizedQuery: WindowInfo.normalize("  SLACK ")) != nil)
        #expect(slack.matchScore(normalizedQuery: WindowInfo.normalize("finder")) == nil)
    }

    @Test("Fuzzy initials match correctly")
    func fuzzyMatching() {
        let code = window(appName: "Visual Studio Code", title: "WindowInfo.swift")
        #expect(code.matches(query: "vsc"))
        #expect(code.matches(query: "vscode"))
        #expect(code.matches(query: "winfo"))
        #expect(!code.matches(query: "zzz"))
    }

    @Test("A contiguous match outranks a scattered one")
    func fuzzyRanking() {
        let query = WindowInfo.normalize("slk")
        let exact = window(appName: "Slk", title: "")
        let scattered = window(appName: "Superlong Kitchen Sink", title: "")

        let exactScore = try! #require(exact.matchScore(normalizedQuery: query))
        let scatteredScore = try! #require(scattered.matchScore(normalizedQuery: query))
        #expect(exactScore > scatteredScore)
    }

    @Test("The app name outranks the window title")
    func appNameWins() {
        let query = WindowInfo.normalize("mail")
        let byApp = window(appName: "Mail", title: "unrelated")
        let byTitle = window(appName: "unrelated", title: "Mail")

        let appScore = try! #require(byApp.matchScore(normalizedQuery: query))
        let titleScore = try! #require(byTitle.matchScore(normalizedQuery: query))
        #expect(appScore > titleScore)
    }

    @Test("Blank titles fall back to the app name")
    func displayTitleFallback() {
        #expect(window(appName: "Finder", title: "   ").displayTitle == "Finder")
        #expect(window(appName: "Finder", title: "").displayTitle == "Finder")
        #expect(window(appName: "Finder", title: "Downloads").displayTitle == "Downloads")
    }

    @Test("Identity is the window id alone")
    func identity() {
        let first = window(id: 42, pid: 100, appName: "App1", title: "Title 1")
        let sameID = window(id: 42, pid: 200, appName: "App2", title: "Title 2")
        let otherID = window(id: 43, pid: 100, appName: "App1", title: "Title 1")

        #expect(first == sameID)
        #expect(first != otherID)
        #expect(first.hashValue == sameID.hashValue)
    }

    @Test("Minimized state round-trips")
    func minimizedFlag() {
        #expect(!window().isMinimized)
        #expect(window(isMinimized: true).isMinimized)
    }
}

@Suite("WindowSwitcher - Navigation")
@MainActor
struct SwitcherNavigationTests {
    private func viewModel(windowCount: Int) -> SwitcherViewModel {
        let vm = SwitcherViewModel()
        vm.windows = (1...windowCount).map {
            WindowInfo(
                id: CGWindowID($0),
                pid: pid_t($0),
                appName: "App \($0)",
                title: "Win \($0)",
                bounds: .zero
            )
        }
        return vm
    }

    @Test("Next and previous wrap around the list")
    func cycling() {
        let vm = viewModel(windowCount: 3)
        vm.selectedIndex = 0

        vm.selectNext()
        #expect(vm.selectedIndex == 1)
        vm.selectNext()
        #expect(vm.selectedIndex == 2)
        vm.selectNext()
        #expect(vm.selectedIndex == 0)
        vm.selectPrevious()
        #expect(vm.selectedIndex == 2)
        vm.selectPrevious()
        #expect(vm.selectedIndex == 1)
    }

    @Test("Grid navigation clamps at the edges")
    func gridNavigation() {
        let vm = viewModel(windowCount: 6)
        vm.selectedIndex = 0

        vm.navigate(direction: .down, columns: 4)
        #expect(vm.selectedIndex == 4)

        vm.navigate(direction: .right, columns: 4)
        #expect(vm.selectedIndex == 5)

        vm.navigate(direction: .down, columns: 4)
        #expect(vm.selectedIndex == 5)

        vm.navigate(direction: .up, columns: 4)
        #expect(vm.selectedIndex == 1)

        vm.navigate(direction: .left, columns: 4)
        #expect(vm.selectedIndex == 0)
    }

    @Test("Search filters the list and resets the selection")
    func searchFiltering() {
        let vm = SwitcherViewModel()
        vm.windows = [
            WindowInfo(id: 1, pid: 10, appName: "Terminal", title: "zsh", bounds: .zero),
            WindowInfo(id: 2, pid: 20, appName: "Slack", title: "general", bounds: .zero),
            WindowInfo(id: 3, pid: 30, appName: "Safari", title: "Apple Developer", bounds: .zero)
        ]
        #expect(vm.filteredWindows.count == 3)

        vm.searchQuery = "slack"
        #expect(vm.filteredWindows.map(\.appName) == ["Slack"])
        #expect(vm.selectedIndex == 0)

        vm.searchQuery = "apple"
        #expect(vm.filteredWindows.map(\.appName) == ["Safari"])

        vm.searchQuery = "nonexistent"
        #expect(vm.filteredWindows.isEmpty)
        #expect(vm.selectedWindow == nil)
    }

    @Test("Selecting by window id survives reordering")
    func selectByID() {
        let vm = viewModel(windowCount: 4)
        vm.select(id: 3)
        #expect(vm.selectedWindow?.id == 3)

        vm.select(id: 999)
        #expect(vm.selectedWindow?.id == 3)
    }

    @Test("Removing a window keeps the selection in range")
    func removalAdjustsSelection() {
        let vm = viewModel(windowCount: 3)
        vm.selectedIndex = 2

        vm.removeWindow(id: 3)
        #expect(vm.windows.count == 2)
        #expect(vm.selectedIndex == 1)

        vm.removeWindow(id: 2)
        #expect(vm.windows.count == 1)
        #expect(vm.selectedIndex == 0)

        vm.removeWindow(id: 1)
        #expect(vm.windows.isEmpty)
        #expect(vm.selectedIndex == 0)
    }

    @Test("Quick select selects the exact window by number")
    func quickSelect() {
        let vm = viewModel(windowCount: 5)
        let selected1 = vm.quickSelect(number: 1)
        #expect(selected1?.id == 1)
        #expect(vm.selectedIndex == 0)

        let selected3 = vm.quickSelect(number: 3)
        #expect(selected3?.id == 3)
        #expect(vm.selectedIndex == 2)

        let invalid = vm.quickSelect(number: 99)
        #expect(invalid == nil)
        #expect(vm.selectedIndex == 2)
    }

    @Test("Preview state toggles and closes properly")
    func previewState() {
        let vm = viewModel(windowCount: 3)
        #expect(!vm.isPreviewOpen)

        vm.togglePreview()
        #expect(vm.isPreviewOpen)

        vm.closePreview()
        #expect(!vm.isPreviewOpen)
    }
}

@Suite("WindowSwitcher - Activation History")
@MainActor
struct SwitcherHistoryTests {
    private func window(id: CGWindowID, pid: pid_t) -> WindowInfo {
        WindowInfo(id: id, pid: pid, appName: "App \(pid)", title: "Win \(id)", bounds: .zero)
    }

    @Test("Most recently focused windows float to the top")
    func recencyOrdering() {
        let history = WindowActivationHistory.shared
        let windows = [window(id: 101, pid: 10), window(id: 102, pid: 20), window(id: 103, pid: 30)]

        for w in windows { history.forget(windowID: w.id) }
        history.record(window: windows[2])
        history.record(window: windows[0])

        let ordered = history.ordered(windows)
        #expect(ordered.map(\.id) == [101, 103, 102])
    }
}

@Suite("WindowSwitcher - Metrics & Layout")
struct SwitcherMetricsLayoutTests {
    private static let medium = CGSize(width: 288, height: 180)

    @Test("Row count never drops below one")
    func rowCounts() {
        #expect(SwitcherMetrics.rowCount(items: 0, columns: 4) == 1)
        #expect(SwitcherMetrics.rowCount(items: 4, columns: 4) == 1)
        #expect(SwitcherMetrics.rowCount(items: 5, columns: 4) == 2)
    }

    @Test("Panel never outgrows available space")
    func layoutFitsAvailableSpace() {
        let available = CGSize(width: 1200, height: 700)
        let layout = SwitcherMetrics.layout(items: 8, maxThumbnail: Self.medium, showsBanner: true, available: available)
        #expect(layout.panelSize.width <= available.width)
        #expect(layout.panelSize.height <= available.height)
    }

    @Test("Thumbnail captures keep window aspect ratio and never upscale past 2x")
    func thumbnailPixelSize() {
        let wide = SwitcherWindowManager.pixelSize(for: CGRect(x: 0, y: 0, width: 2000, height: 1000), fitting: CGSize(width: 576, height: 360))
        #expect(wide.width == 576)
        #expect(wide.height == 288)

        let tiny = SwitcherWindowManager.pixelSize(for: CGRect(x: 0, y: 0, width: 100, height: 50), fitting: CGSize(width: 576, height: 360))
        #expect(tiny.width == 200)
        #expect(tiny.height == 100)
    }
}

@Suite("WindowSwitcher - Preferences")
@MainActor
struct SwitcherPreferencesTests {
    @Test("Preferences manager initializes with valid default values")
    func defaults() {
        let prefs = SwitcherPreferencesManager.shared
        #expect(prefs.shortcut == .both || prefs.shortcut == .optionTab || prefs.shortcut == .commandTab)
        #expect(prefs.displayMode == .compact || prefs.displayMode == .fullscreen)
        #expect(prefs.thumbnailSize == .medium || prefs.thumbnailSize == .small || prefs.thumbnailSize == .large)
    }
}

@Suite("WindowSwitcher - Lifecycle")
@MainActor
struct SwitcherLifecycleTests {
    private func window(id: CGWindowID, pid: pid_t) -> WindowInfo {
        WindowInfo(id: id, pid: pid, appName: "App \(pid)", title: "Win \(id)", bounds: .zero)
    }

    @Test("Releasing content clears windows, search and transient state")
    func releaseContent() {
        let vm = SwitcherViewModel()
        vm.windows = [window(id: 1, pid: 1), window(id: 2, pid: 2)]
        vm.enterSearchMode()
        vm.searchQuery = "App"
        vm.toggleHelp()

        vm.releaseContent()

        #expect(vm.windows.isEmpty)
        #expect(vm.filteredWindows.isEmpty)
        #expect(vm.searchQuery.isEmpty)
        #expect(!vm.isSearchMode)
        #expect(!vm.isHelpOpen)
        #expect(vm.activeSheet == nil)
        #expect(vm.selectedWindow == nil)
    }

    @Test("Text entry is active only while searching")
    func textEntryFollowsSearch() {
        let vm = SwitcherViewModel()
        #expect(!vm.isTextEntryActive)
        vm.enterSearchMode()
        #expect(vm.isTextEntryActive)
        vm.exitSearchMode()
        #expect(!vm.isTextEntryActive)
    }

    @Test("Stopping history observation forgets recorded activations")
    func historyStopClears() {
        let history = WindowActivationHistory.shared
        let windows = [window(id: 201, pid: 21), window(id: 202, pid: 22)]
        history.record(window: windows[1])
        #expect(history.ordered(windows).map(\.id) == [202, 201])

        history.stopObserving()
        #expect(history.ordered(windows).map(\.id) == [201, 202])
    }
}

@Suite("WindowSwitcher - Hotkey Tap")
@MainActor
struct SwitcherHotkeyTapTests {
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
        event.flags = flags
        return event
    }

    @Test("Option-Tab is consumed and following keys are treated as overlay input")
    func optimisticOverlayState() throws {
        let manager = SwitcherHotkeyManager.shared
        manager.setShortcutPreference(.optionTab)
        manager.updateOverlayState(isVisible: false, isTextEntryActive: false)

        let letterW = try key(13)
        #expect(manager.handleEvent(type: .keyDown, event: letterW) != nil)

        #expect(manager.handleEvent(type: .keyDown, event: try key(48, flags: .maskAlternate)) == nil)
        #expect(manager.handleEvent(type: .keyDown, event: try key(48, flags: .maskAlternate)) == nil)
        #expect(manager.handleEvent(type: .keyDown, event: letterW) == nil)

        manager.updateOverlayState(isVisible: false, isTextEntryActive: false)
        #expect(manager.handleEvent(type: .keyDown, event: letterW) != nil)
        manager.setShortcutPreference(.both)
    }

    @Test("Command-Tab passes through when only Option-Tab is configured")
    func respectsShortcutPreference() throws {
        let manager = SwitcherHotkeyManager.shared
        manager.setShortcutPreference(.optionTab)
        manager.updateOverlayState(isVisible: false, isTextEntryActive: false)

        #expect(manager.handleEvent(type: .keyDown, event: try key(48, flags: .maskCommand)) != nil)
        manager.setShortcutPreference(.both)
    }

    @Test("Search mode lets letters reach the text field")
    func textEntryPassesLetters() throws {
        let manager = SwitcherHotkeyManager.shared
        manager.updateOverlayState(isVisible: true, isTextEntryActive: true)
        #expect(manager.handleEvent(type: .keyDown, event: try key(13)) != nil)
        #expect(manager.handleEvent(type: .keyDown, event: try key(53)) == nil)
        manager.updateOverlayState(isVisible: false, isTextEntryActive: false)
    }

    @Test("Releasing active modifier after Option-Tab dispatches confirm and closes overlay state")
    func modifierReleaseConfirmsSelection() throws {
        let manager = SwitcherHotkeyManager.shared
        manager.setShortcutPreference(.both)
        manager.updateOverlayState(isVisible: false, isTextEntryActive: false)
        defer {
            manager.updateOverlayState(isVisible: false, isTextEntryActive: false)
        }

        #expect(manager.handleEvent(type: .keyDown, event: try key(48, flags: .maskAlternate)) == nil)
        let releaseEvent = try key(58, flags: [])
        _ = manager.handleEvent(type: .flagsChanged, event: releaseEvent)

        let letterW = try key(13)
        #expect(manager.handleEvent(type: .keyDown, event: letterW) != nil)
    }
}
