import AppKit
import Carbon
import Observation

@Observable
final class ScreenshotHotkeyService {
    static let shared = ScreenshotHotkeyService()

    @ObservationIgnored weak var delegate: (any CaptureRequestHandler)?

    private(set) var unavailableRequests: Set<CaptureRequest> = []

    @ObservationIgnored private var hotKeyRefs: [EventHotKeyRef] = []
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var isStarted = false

    nonisolated private static let signature = OSType(0x4D534854)

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installEventHandlerIfNeeded()
        reload()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        unregisterHotkeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        unavailableRequests = []
    }

    func suspend() {
        unregisterHotkeys()
    }

    func resume() {
        guard isStarted else { return }
        reload()
    }

    func reload() {
        guard isStarted else { return }
        unregisterHotkeys()

        var unavailable: Set<CaptureRequest> = []
        let preferences = ScreenshotPreferences.shared
        for request in CaptureRequest.allCases where !register(request, shortcut: preferences.shortcut(for: request)) {
            unavailable.insert(request)
        }
        if unavailable != unavailableRequests {
            unavailableRequests = unavailable
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr, hotKeyID.signature == ScreenshotHotkeyService.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let id = hotKeyID.id
                Task { @MainActor in
                    ScreenshotHotkeyService.shared.handleHotKey(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        if status != noErr {
            ScreenshotLogger.captureError("carbon event handler registration failed", status: status)
        }
    }

    private func register(_ request: CaptureRequest, shortcut: KeyShortcut) -> Bool {
        guard shortcut.isValidGlobalShortcut else { return false }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: request.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            ScreenshotLogger.captureError("hotkey registration failed", status: status)
            return false
        }
        hotKeyRefs.append(hotKeyRef)
        return true
    }

    private func handleHotKey(id: UInt32) {
        guard let request = CaptureRequest(rawValue: id) else { return }
        delegate?.handleCaptureRequest(request)
    }

    private func unregisterHotkeys() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
}
