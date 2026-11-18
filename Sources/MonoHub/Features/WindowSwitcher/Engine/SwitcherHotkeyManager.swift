import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Synchronization

@MainActor
protocol SwitcherHotkeyManagerDelegate: AnyObject {
    func perform(_ action: HotkeyAction)
}

nonisolated final class SwitcherHotkeyManager: Sendable {
    private enum TriggerModifier: Sendable {
        case option
        case command
    }

    private enum KeyCode {
        static let tab: Int64 = 48
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let escape: Int64 = 53
        static let space: Int64 = 49
        static let backtick: Int64 = 50
        static let w: Int64 = 13
        static let q: Int64 = 12
        static let f: Int64 = 3
        static let n: Int64 = 45
        static let slash: Int64 = 44
        static let m: Int64 = 46
        static let z: Int64 = 6
        static let h: Int64 = 4
        static let j: Int64 = 38
        static let k: Int64 = 40
        static let l: Int64 = 37
        static let leftBracket: Int64 = 33
        static let rightBracket: Int64 = 30
        static let arrowLeft: Int64 = 123
        static let arrowRight: Int64 = 124
        static let arrowDown: Int64 = 125
        static let arrowUp: Int64 = 126
    }

    private static let quickSelectKeys: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    private static let navigationKeys: [Int64: NavigationDirection] = [
        KeyCode.arrowUp: .up, KeyCode.k: .up,
        KeyCode.arrowDown: .down, KeyCode.j: .down,
        KeyCode.arrowLeft: .left, KeyCode.h: .left,
        KeyCode.arrowRight: .right, KeyCode.l: .right
    ]

    private struct State {
        var isOverlayVisible = false
        var isTextEntryActive = false
        var shortcut: ShortcutPreference = .both
        var activeModifier: TriggerModifier?
    }

    static let shared = SwitcherHotkeyManager()

    @MainActor weak var delegate: (any SwitcherHotkeyManagerDelegate)?

    private let tap = Mutex<BackgroundEventTap?>(nil)
    private let state = Mutex(State())
    @MainActor private var modifierPollTimer: Timer?
    @MainActor private var localFlagsMonitor: Any?
    @MainActor private var globalFlagsMonitor: Any?

    private init() {}

    var isRunning: Bool {
        tap.withLock { $0 != nil }
    }

    @MainActor
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue)

        guard let newTap = BackgroundEventTap(
            mask: eventMask,
            callback: switcherHotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        newTap.start(name: "MonoHub.SwitcherHotkeys")
        tap.withLock { $0 = newTap }
        return true
    }

    @MainActor
    func stop() {
        stopModifierPolling()
        let current = tap.withLock { tap in
            let current = tap
            tap = nil
            return current
        }
        current?.invalidate()
        state.withLock {
            $0.isOverlayVisible = false
            $0.isTextEntryActive = false
            $0.activeModifier = nil
        }
    }

    func updateOverlayState(isVisible: Bool, isTextEntryActive: Bool) {
        let hasActiveModifier = state.withLock { state -> Bool in
            state.isOverlayVisible = isVisible
            state.isTextEntryActive = isTextEntryActive
            if !isVisible {
                state.activeModifier = nil
            }
            return isVisible && state.activeModifier != nil && !isTextEntryActive
        }
        Task { @MainActor in
            if hasActiveModifier {
                self.startModifierPolling()
            } else {
                self.stopModifierPolling()
            }
        }
    }

    func setShortcutPreference(_ preference: ShortcutPreference) {
        state.withLock { $0.shortcut = preference }
    }

    @MainActor
    private func startFallbackFlagsMonitors() {
        guard localFlagsMonitor == nil, globalFlagsMonitor == nil else { return }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkModifierReleaseFromNSEvent(event.modifierFlags)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.checkModifierReleaseFromNSEvent(event.modifierFlags)
            }
        }
    }

    @MainActor
    private func stopFallbackFlagsMonitors() {
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
    }

    @MainActor
    private func startModifierPolling() {
        startFallbackFlagsMonitors()
        guard modifierPollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollModifierState()
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        modifierPollTimer = timer
    }

    @MainActor
    private func stopModifierPolling() {
        stopFallbackFlagsMonitors()
        modifierPollTimer?.invalidate()
        modifierPollTimer = nil
    }

    @MainActor
    private func checkModifierReleaseFromNSEvent(_ flags: NSEvent.ModifierFlags) {
        let shouldConfirm = state.withLock { state -> Bool in
            guard let active = state.activeModifier else { return false }
            let released: Bool
            switch active {
            case .option: released = !flags.contains(.option)
            case .command: released = !flags.contains(.command)
            }
            guard released else { return false }
            state.activeModifier = nil
            guard state.isOverlayVisible, !state.isTextEntryActive else { return false }
            state.isOverlayVisible = false
            return true
        }
        if shouldConfirm {
            stopModifierPolling()
            delegate?.perform(.confirm)
        }
    }

    @MainActor
    private func pollModifierState() {
        let hwFlags = CGEventSource.flagsState(.combinedSessionState)
        let nsFlags = NSEvent.modifierFlags
        let shouldConfirm = state.withLock { state -> Bool in
            guard let active = state.activeModifier else { return false }
            let released: Bool
            switch active {
            case .option:
                released = !hwFlags.contains(.maskAlternate) && !nsFlags.contains(.option)
            case .command:
                released = !hwFlags.contains(.maskCommand) && !nsFlags.contains(.command)
            }
            guard released else { return false }
            state.activeModifier = nil
            guard state.isOverlayVisible, !state.isTextEntryActive else { return false }
            state.isOverlayVisible = false
            return true
        }
        if shouldConfirm {
            stopModifierPolling()
            delegate?.perform(.confirm)
        }
    }

    private func send(_ action: HotkeyAction) -> Unmanaged<CGEvent>? {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if case .confirm = action {
                    stopModifierPolling()
                } else if case .cancel = action {
                    stopModifierPolling()
                }
                if let delegate {
                    delegate.perform(action)
                } else {
                    updateOverlayState(isVisible: false, isTextEntryActive: false)
                }
            }
        }
        return nil
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap.withLock { $0?.reenable() }
            return Unmanaged.passUnretained(event)
        }

        let snapshot = state.withLock { $0 }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event, snapshot)
        case .keyDown:
            return handleKeyDown(event, snapshot)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent, _ snapshot: State) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let shouldConfirm = state.withLock { state -> Bool in
            guard let active = state.activeModifier else { return false }
            let released: Bool
            switch active {
            case .option: released = !flags.contains(.maskAlternate)
            case .command: released = !flags.contains(.maskCommand)
            }
            guard released else { return false }
            state.activeModifier = nil
            guard state.isOverlayVisible, !state.isTextEntryActive else { return false }
            state.isOverlayVisible = false
            return true
        }
        guard shouldConfirm else { return Unmanaged.passUnretained(event) }
        return send(.confirm)
    }

    private func trigger(for flags: CGEventFlags, mode: ShortcutPreference) -> TriggerModifier? {
        if flags.contains(.maskAlternate), mode == .optionTab || mode == .both { return .option }
        if flags.contains(.maskCommand), mode == .commandTab || mode == .both { return .command }
        return nil
    }

    private func open(appOnly: Bool, trigger: TriggerModifier, snapshot: State, forward: Bool) -> Unmanaged<CGEvent>? {
        state.withLock {
            $0.activeModifier = trigger
            $0.isOverlayVisible = true
        }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                startModifierPolling()
            }
        }
        if snapshot.isOverlayVisible {
            return send(.cycle(forward: forward))
        }
        return send(.open(appOnly: appOnly))
    }

    private func handleKeyDown(_ event: CGEvent, _ snapshot: State) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let mode = snapshot.shortcut
        let hasShift = flags.contains(.maskShift)

        if keyCode == KeyCode.tab {
            if let trigger = trigger(for: flags, mode: mode) {
                return open(appOnly: false, trigger: trigger, snapshot: snapshot, forward: !hasShift)
            }

            if snapshot.isOverlayVisible {
                return send(.cycle(forward: !hasShift))
            }
        }

        if keyCode == KeyCode.backtick, let trigger = trigger(for: flags, mode: mode) {
            return open(appOnly: true, trigger: trigger, snapshot: snapshot, forward: !hasShift)
        }

        guard snapshot.isOverlayVisible else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            state.withLock {
                $0.activeModifier = nil
                $0.isOverlayVisible = false
            }
            return send(.confirm)
        case KeyCode.escape:
            state.withLock { $0.activeModifier = nil }
            return send(.cancel)
        default:
            break
        }

        guard !snapshot.isTextEntryActive else { return Unmanaged.passUnretained(event) }

        if hasShift && keyCode == KeyCode.h {
            return send(.tile(.left))
        }
        if hasShift && keyCode == KeyCode.l {
            return send(.tile(.right))
        }

        if let direction = Self.navigationKeys[keyCode] {
            return send(.navigate(direction))
        }

        if let number = Self.quickSelectKeys[keyCode] {
            state.withLock {
                $0.activeModifier = nil
                $0.isOverlayVisible = false
            }
            return send(.quickSelect(number))
        }

        switch keyCode {
        case KeyCode.space:
            return send(.togglePreview)
        case KeyCode.m:
            return send(.toggleMinimize)
        case KeyCode.z:
            return send(.toggleZoom)
        case KeyCode.n:
            return send(.moveToNextDisplay)
        case KeyCode.leftBracket:
            return send(.tile(.left))
        case KeyCode.rightBracket:
            return send(.tile(.right))
        case KeyCode.q where flags.contains(.maskCommand):
            return send(.quitApp)
        case KeyCode.w:
            return send(hasShift ? .hideApp : .closeWindow)
        case KeyCode.slash where hasShift:
            return send(.toggleHelp)
        case KeyCode.f, KeyCode.slash:
            return send(.enterSearch)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

nonisolated private func switcherHotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<SwitcherHotkeyManager>.fromOpaque(refcon)
        .takeUnretainedValue()
        .handleEvent(type: type, event: event)
}
