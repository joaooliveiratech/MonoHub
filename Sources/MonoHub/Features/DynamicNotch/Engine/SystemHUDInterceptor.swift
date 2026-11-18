import AppKit
import CoreGraphics
import Observation

private let NX_KEYTYPE_SOUND_UP: Int = 0
private let NX_KEYTYPE_SOUND_DOWN: Int = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int = 3
private let NX_KEYTYPE_MUTE: Int = 7

nonisolated private final class SystemHUDTapHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var tap: BackgroundEventTap?

    func set(_ newTap: BackgroundEventTap?) {
        lock.withLock {
            tap = newTap
        }
    }

    func reenable() {
        let current = lock.withLock { tap }
        current?.reenable()
    }
}

nonisolated private func systemHUDEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        SystemHUDInterceptor.reenableTapFromCallback()
        return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == 14 else {
        return Unmanaged.passUnretained(event)
    }

    guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }

    let data1 = nsEvent.data1
    let keyCode = Int((data1 & 0xFFFF0000) >> 16)
    let keyFlags = (data1 & 0x0000FFFF)
    let keyState = (keyFlags & 0xFF00) >> 8
    let isKeyDown = (keyState == 0x0A)
    let isKeyUp = (keyState == 0x0B)

    guard isKeyDown || isKeyUp else {
        return Unmanaged.passUnretained(event)
    }

    let isTargetKey: Bool
    switch keyCode {
    case NX_KEYTYPE_SOUND_UP,
         NX_KEYTYPE_SOUND_DOWN,
         NX_KEYTYPE_MUTE,
         NX_KEYTYPE_BRIGHTNESS_UP,
         NX_KEYTYPE_BRIGHTNESS_DOWN:
        isTargetKey = true
    default:
        isTargetKey = false
    }

    guard isTargetKey else {
        return Unmanaged.passUnretained(event)
    }

    if isKeyDown {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SystemHUDInterceptor.shared.handleKey(keyCode)
            }
        }
    }

    return nil
}

@Observable
@MainActor
final class SystemHUDInterceptor {
    static let shared = SystemHUDInterceptor()
    nonisolated private static let tapHolder = SystemHUDTapHolder()

    private(set) var isInterceptionActive: Bool = false
    private(set) var hasAccessibilityPermission: Bool = false

    @ObservationIgnored private var backgroundTap: BackgroundEventTap?
    @ObservationIgnored private var wantsInterception = false
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    private init() {}

    nonisolated static func reenableTapFromCallback() {
        tapHolder.reenable()
    }

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted {
            hasAccessibilityPermission = trusted
        }
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        if wantsInterception {
            installTap()
        }
    }

    func start() {
        wantsInterception = true
        installTap()
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                SystemHUDInterceptor.shared.installTap()
            }
        }
    }

    func stop() {
        wantsInterception = false
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        removeTap()
    }

    func reEnableTap() {
        backgroundTap?.reenable()
    }

    fileprivate func handleKey(_ keyCode: Int) {
        guard wantsInterception else { return }
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            if DisplayControlFeature.isActive && DisplayControlPreferences.shared.enableVolumeKeys && ExternalDisplayManager.shared.shouldInterceptVolumeKeys() {
                ExternalDisplayManager.shared.increaseVolume()
            } else {
                AudioVolumeManager.shared.increaseVolume()
            }
        case NX_KEYTYPE_SOUND_DOWN:
            if DisplayControlFeature.isActive && DisplayControlPreferences.shared.enableVolumeKeys && ExternalDisplayManager.shared.shouldInterceptVolumeKeys() {
                ExternalDisplayManager.shared.decreaseVolume()
            } else {
                AudioVolumeManager.shared.decreaseVolume()
            }
        case NX_KEYTYPE_MUTE:
            if DisplayControlFeature.isActive && DisplayControlPreferences.shared.enableVolumeKeys && ExternalDisplayManager.shared.shouldInterceptVolumeKeys() {
                ExternalDisplayManager.shared.toggleMute()
            } else {
                AudioVolumeManager.shared.toggleMute()
            }
        case NX_KEYTYPE_BRIGHTNESS_UP:
            DisplayBrightnessManager.shared.increaseBrightness()
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            DisplayBrightnessManager.shared.decreaseBrightness()
        default:
            break
        }
    }

    private func installTap() {
        guard wantsInterception, backgroundTap == nil else { return }
        checkAccessibility()
        guard hasAccessibilityPermission else { return }

        guard let tap = BackgroundEventTap(
            mask: CGEventMask(1 << 14),
            callback: systemHUDEventTapCallback,
            userInfo: nil
        ) else {
            return
        }

        backgroundTap = tap
        Self.tapHolder.set(tap)
        tap.start(name: "MonoHub.SystemHUDTap")
        isInterceptionActive = true
    }

    private func removeTap() {
        Self.tapHolder.set(nil)
        if let tap = backgroundTap {
            tap.invalidate()
            backgroundTap = nil
        }
        if isInterceptionActive {
            isInterceptionActive = false
        }
    }
}
