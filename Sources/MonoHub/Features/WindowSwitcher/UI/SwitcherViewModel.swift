import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
final class ThumbnailSlot {
    var image: CGImage?

    init(image: CGImage? = nil) {
        self.image = image
    }
}

private struct RankedWindow {
    let window: WindowInfo
    let score: Int
    let order: Int
}

nonisolated enum SwitcherSheet: Sendable {
    case help
    case preview

    var size: CGSize {
        switch self {
        case .help: SwitcherMetrics.helpSize
        case .preview: SwitcherMetrics.previewSize
        }
    }
}

@Observable
final class SwitcherViewModel {
    var windows: [WindowInfo] = [] {
        didSet {
            searchKeys = nil
            syncSlots()
            applyFilter()
            notifyPresentationChange(windows.count != oldValue.count)
        }
    }

    private(set) var filteredWindows: [WindowInfo] = []

    var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            applyFilter()
            selectedIndex = 0
        }
    }

    var selectedIndex: Int = 0
    var availableSpace = CGSize(width: 1400, height: 900)
    var isAppOnlyMode: Bool = false
    var pendingConfirmation: PendingConfirmation?

    @ObservationIgnored var targetAppPID: pid_t?
    @ObservationIgnored var onPresentationChange: (@MainActor () -> Void)?

    var isSearchMode: Bool = false {
        didSet { notifyPresentationChange(isSearchMode != oldValue) }
    }

    var isHelpOpen: Bool = false {
        didSet { notifyPresentationChange(isHelpOpen != oldValue) }
    }

    var isPreviewOpen: Bool = false {
        didSet {
            guard isPreviewOpen != oldValue else { return }
            if isPreviewOpen { startPreviewCapture() } else { previewTask?.cancel() }
            onPresentationChange?()
        }
    }

    var isTextEntryActive: Bool { isSearchMode }

    var activeSheet: SwitcherSheet? {
        if isHelpOpen { return .help }
        if isPreviewOpen { return .preview }
        return nil
    }

    var layout: SwitcherLayout {
        SwitcherMetrics.layout(
            items: windows.count,
            maxThumbnail: SwitcherPreferencesManager.shared.maxThumbnail,
            showsBanner: SwitcherPermissionsManager.shared.showsBanner,
            available: availableSpace
        )
    }

    var floatingWindowSize: CGSize {
        activeSheet?.size ?? layout.panelSize
    }

    @ObservationIgnored private var slots: [CGWindowID: ThumbnailSlot] = [:]
    @ObservationIgnored private var searchKeys: [WindowSearchKey]?
    @ObservationIgnored private var extendedFetchTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init() {}

    var selectedWindow: WindowInfo? {
        filteredWindows.indices.contains(selectedIndex) ? filteredWindows[selectedIndex] : nil
    }

    func slot(for windowID: CGWindowID) -> ThumbnailSlot {
        slots[windowID] ?? ThumbnailSlot(image: SwitcherWindowManager.shared.cachedThumbnail(for: windowID))
    }

    func quickNumbers() -> [CGWindowID: Int] {
        guard SwitcherPreferencesManager.shared.showQuickShortcuts else { return [:] }
        var numbers: [CGWindowID: Int] = [:]
        for (index, window) in filteredWindows.prefix(9).enumerated() {
            numbers[window.id] = index + 1
        }
        return numbers
    }

    private func notifyPresentationChange(_ changed: Bool) {
        if changed { onPresentationChange?() }
    }

    private func syncSlots() {
        var updated: [CGWindowID: ThumbnailSlot] = [:]
        updated.reserveCapacity(windows.count)
        for window in windows {
            updated[window.id] = slot(for: window.id)
        }
        slots = updated
    }

    private func resolvedSearchKeys() -> [WindowSearchKey] {
        if let searchKeys { return searchKeys }
        let keys = windows.map(\.searchKey)
        searchKeys = keys
        return keys
    }

    private func applyFilter() {
        let query = WindowInfo.normalize(searchQuery)
        guard !query.isEmpty else {
            filteredWindows = windows
            return
        }

        let keys = resolvedSearchKeys()
        var ranked: [RankedWindow] = []
        ranked.reserveCapacity(windows.count)
        for (index, window) in windows.enumerated() {
            guard index < keys.count, let score = keys[index].score(query: query) else { continue }
            ranked.append(RankedWindow(window: window, score: score, order: index))
        }
        ranked.sort { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        filteredWindows = ranked.map(\.window)
    }

    func resetTransientState() {
        pendingConfirmation = nil
        isSearchMode = false
        searchQuery = ""
        isHelpOpen = false
        isPreviewOpen = false
    }

    func refreshWindows(appOnly: Bool = false, targetPID: pid_t? = nil, screens: ScreenSnapshot) {
        extendedFetchTask?.cancel()
        resetTransientState()
        isAppOnlyMode = appOnly
        targetAppPID = targetPID

        let preferences = SwitcherPreferencesManager.shared
        let includeMinimized = preferences.showMinimizedWindows
        let showTabs = preferences.showAppTabs
        let currentSpaceOnly = preferences.currentSpaceOnly

        var base = SwitcherWindowManager.shared.fetchOnScreenWindows(screens: screens)
        if appOnly, let targetPID {
            base = base.filter { $0.pid == targetPID }
        }
        apply(windows: ordered(base), preferredID: nil)

        guard includeMinimized || showTabs || !currentSpaceOnly else { return }

        let preferredID = selectedWindow?.id
        extendedFetchTask = Task { [weak self] in
            var extended = await SwitcherWindowManager.shared.fetchExtendedWindows(
                base: base,
                screens: screens,
                includeMinimized: includeMinimized,
                showTabs: showTabs,
                currentSpaceOnly: currentSpaceOnly
            )
            if appOnly, let targetPID {
                extended = extended.filter { $0.pid == targetPID }
            }
            guard !Task.isCancelled, let self else { return }
            guard Set(extended.map(\.id)) != Set(base.map(\.id)) else { return }
            self.apply(windows: self.ordered(extended), preferredID: preferredID)
        }
    }

    private func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        guard SwitcherPreferencesManager.shared.useRecentOrdering else { return windows }
        return WindowActivationHistory.shared.ordered(windows)
    }

    private func apply(windows newWindows: [WindowInfo], preferredID: CGWindowID?) {
        windows = newWindows

        if let preferredID, let index = filteredWindows.firstIndex(where: { $0.id == preferredID }) {
            selectedIndex = index
        } else {
            selectedIndex = filteredWindows.count > 1 ? 1 : 0
        }

        startThumbnailCapture()
    }

    private func startThumbnailCapture() {
        thumbnailTask?.cancel()
        thumbnailTask = captureThumbnails(
            for: windows,
            priorityID: selectedWindow?.id,
            pointSize: layout.thumbnail
        )
    }

    private func startPreviewCapture() {
        previewTask?.cancel()
        guard let window = selectedWindow else { return }
        previewTask = captureThumbnails(for: [window], priorityID: window.id, pointSize: SwitcherMetrics.previewImageSize)
    }

    private func captureThumbnails(for targets: [WindowInfo], priorityID: CGWindowID?, pointSize: CGSize) -> Task<Void, Never>? {
        guard SwitcherPermissionsManager.shared.hasScreenRecording, !targets.isEmpty else { return nil }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let maxPixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
        return Task { [weak self] in
            await SwitcherWindowManager.shared.captureThumbnails(
                for: targets,
                priorityID: priorityID,
                maxPixelSize: maxPixelSize
            ) { id, image in
                self?.update(thumbnail: image, for: id)
            }
        }
    }

    private func update(thumbnail image: CGImage, for id: CGWindowID) {
        guard let slot = slots[id] else { return }
        if let current = slot.image, current.width > image.width, isPreviewOpen, id == selectedWindow?.id { return }
        slot.image = image
    }

    func releaseContent() {
        cancelPendingWork()
        resetTransientState()
        targetAppPID = nil
        if !windows.isEmpty { windows = [] }
        slots.removeAll()
    }

    func cancelPendingWork() {
        extendedFetchTask?.cancel()
        thumbnailTask?.cancel()
        previewTask?.cancel()
        extendedFetchTask = nil
        thumbnailTask = nil
        previewTask = nil
    }

    func select(id: CGWindowID) {
        guard let index = filteredWindows.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
    }

    func selectNext() {
        let count = filteredWindows.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    func selectPrevious() {
        let count = filteredWindows.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    func cycle(forward: Bool) {
        if forward { selectNext() } else { selectPrevious() }
    }

    func navigate(direction: NavigationDirection, columns: Int) {
        let count = filteredWindows.count
        guard count > 0 else { return }

        switch direction {
        case .left:
            selectPrevious()
        case .right:
            selectNext()
        case .up:
            let target = selectedIndex - columns
            if target >= 0 { selectedIndex = target }
        case .down:
            let target = selectedIndex + columns
            if target < count { selectedIndex = target }
        }
    }

    func navigate(direction: NavigationDirection) {
        navigate(direction: direction, columns: layout.columns)
    }

    @discardableResult
    func quickSelect(number: Int) -> WindowInfo? {
        guard number >= 1, number <= filteredWindows.count else { return nil }
        selectedIndex = number - 1
        return selectedWindow
    }

    private func mutateWindows(_ mutation: () -> Void) {
        withAnimation(.smooth(duration: 0.2)) {
            mutation()
            clampSelection()
        }
    }

    func removeWindows(pid: pid_t) {
        mutateWindows {
            windows.removeAll { $0.pid == pid }
        }
    }

    func removeWindow(id: CGWindowID) {
        mutateWindows {
            windows.removeAll { $0.id == id }
        }
    }

    private func clampSelection() {
        let remaining = filteredWindows.count
        selectedIndex = remaining == 0 ? 0 : min(selectedIndex, remaining - 1)
    }

    func enterSearchMode() { isSearchMode = true }

    func exitSearchMode() {
        isSearchMode = false
        searchQuery = ""
    }

    func openSettings() {
        SwitcherPanelController.shared.hide()
        MainWindowController.shared.show(item: .windowSwitcher)
    }

    func toggleHelp() { isHelpOpen.toggle() }
    func closeHelp() { isHelpOpen = false }
    func togglePreview() { isPreviewOpen.toggle() }
    func closePreview() { isPreviewOpen = false }

    func confirmPending() {
        guard let confirmation = pendingConfirmation else { return }
        pendingConfirmation = nil
        confirmation.perform()
    }

    func cancelPending() {
        pendingConfirmation = nil
    }

    @discardableResult
    func handleDismiss() -> Bool {
        if pendingConfirmation != nil {
            cancelPending()
            return true
        }
        if isHelpOpen {
            closeHelp()
            return true
        }
        if isPreviewOpen {
            closePreview()
            return true
        }
        if isSearchMode {
            if searchQuery.isEmpty {
                exitSearchMode()
            } else {
                searchQuery = ""
            }
            return true
        }
        return false
    }
}
