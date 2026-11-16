import AppKit
import Carbon.HIToolbox
import Foundation
import os

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private let logger = Logger(subsystem: "com.antigravity.monohub", category: "HotkeyManager")
    private static let hotKeySignature: OSType = 0x4D54494C
    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var actionsByHotKeyID: [UInt32: WindowAction] = [:]
    private var fallbackShortcuts: [ShortcutKey: WindowAction] = [:]
    private var fallbackMonitor: Any?
    private var isSuspended = false
    private var appliedShortcuts: [ShortcutKey: WindowAction]?

    private init() {}

    func start() {
        installEventHandlerIfNeeded()
        reload()
    }

    func stop() {
        unregisterHotKeys()
        isSuspended = false
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func reload() {
        guard eventHandlerRef != nil, !isSuspended else {
            unregisterHotKeys()
            return
        }
        let desired = desiredShortcuts()
        guard desired != appliedShortcuts else { return }
        unregisterHotKeys()
        registerHotKeys(desired)
    }

    private func desiredShortcuts() -> [ShortcutKey: WindowAction] {
        let prefs = TilePreferencesManager.shared
        var shortcuts: [ShortcutKey: WindowAction] = [:]
        for action in WindowAction.allCases {
            if let shortcut = prefs.shortcut(for: action) {
                shortcuts[shortcut] = action
            }
        }

        let vimLeft = ShortcutKey(kVK_ANSI_H, .optionShift)
        if shortcuts[vimLeft] == nil && !prefs.disabledShortcuts.contains(WindowAction.leftHalf.rawValue) {
            shortcuts[vimLeft] = .leftHalf
        }
        let vimRight = ShortcutKey(kVK_ANSI_L, .optionShift)
        if shortcuts[vimRight] == nil && !prefs.disabledShortcuts.contains(WindowAction.rightHalf.rawValue) {
            shortcuts[vimRight] = .rightHalf
        }
        return shortcuts
    }

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterHotKeys()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        reload()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr, hotKeyID.signature == HotkeyManager.hotKeySignature else {
                    return OSStatus(eventNotHandledErr)
                }

                let id = hotKeyID.id
                MainActor.assumeIsolated {
                    HotkeyManager.shared.handleHotKey(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("Failed to install Carbon event handler: \(status)")
        }
    }

    private func registerHotKeys(_ shortcuts: [ShortcutKey: WindowAction]) {
        var fallback: [ShortcutKey: WindowAction] = [:]
        let sortedPairs = shortcuts.sorted { lhs, rhs in
            if lhs.value.rawValue != rhs.value.rawValue {
                return lhs.value.rawValue < rhs.value.rawValue
            }
            return lhs.key.keyCode < rhs.key.keyCode
        }

        for (index, entry) in sortedPairs.enumerated() {
            let shortcut = entry.key
            let action = entry.value
            let id = UInt32(index + 1)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.modifiers.carbonModifiers,
                EventHotKeyID(signature: Self.hotKeySignature, id: id),
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                registeredHotKeys.append(hotKeyRef)
                actionsByHotKeyID[id] = action
            } else {
                let name = action.rawValue
                logger.error("Failed to register hotkey for \(name): \(status)")
                fallback[shortcut] = action
            }
        }

        fallbackShortcuts = fallback
        appliedShortcuts = shortcuts
        updateFallbackMonitor()
    }

    private func unregisterHotKeys() {
        registeredHotKeys.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
        actionsByHotKeyID.removeAll()
        fallbackShortcuts.removeAll()
        appliedShortcuts = nil
        updateFallbackMonitor()
    }

    private func updateFallbackMonitor() {
        if fallbackShortcuts.isEmpty {
            if let fallbackMonitor {
                NSEvent.removeMonitor(fallbackMonitor)
                self.fallbackMonitor = nil
            }
        } else if fallbackMonitor == nil {
            fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleFallback(event)
            }
        }
    }

    private func handleHotKey(id: UInt32) {
        guard let action = actionsByHotKeyID[id] else { return }
        WindowManager.shared.perform(action: action)
    }

    private func handleFallback(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let shortcut = ShortcutKey(keyCode: event.keyCode, modifiers: ShortcutModifiers(nsEventModifiers: event.modifierFlags))
        guard let action = fallbackShortcuts[shortcut] else { return }
        WindowManager.shared.perform(action: action)
    }
}
