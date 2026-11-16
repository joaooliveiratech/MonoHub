import AppKit
import CoreGraphics
import Foundation
import Observation

private typealias DisplayServicesGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DisplayServicesSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

private let displayServicesHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
}()

private let getBrightnessFunc: DisplayServicesGetBrightnessFunc? = {
    guard let handle = displayServicesHandle,
          let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
    return unsafeBitCast(sym, to: DisplayServicesGetBrightnessFunc.self)
}()

private let setBrightnessFunc: DisplayServicesSetBrightnessFunc? = {
    guard let handle = displayServicesHandle,
          let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
    return unsafeBitCast(sym, to: DisplayServicesSetBrightnessFunc.self)
}()

@Observable
@MainActor
final class DisplayBrightnessManager {
    static let shared = DisplayBrightnessManager()

    private(set) var currentBrightness: Float = 0.8

    private init() {}

    nonisolated static func clamped(_ value: Float) -> Float {
        value.clamped(to: 0...1)
    }

    var isSupported: Bool {
        getBrightnessFunc != nil && setBrightnessFunc != nil
    }

    func refreshBrightness() {
        guard let fn = getBrightnessFunc else { return }
        var brightness: Float = currentBrightness
        if fn(CGMainDisplayID(), &brightness) == 0 {
            currentBrightness = Self.clamped(brightness)
        }
    }

    func setBrightness(_ value: Float) {
        let clamped = Self.clamped(value)
        currentBrightness = clamped

        guard DisplayControlFeature.isActive else {
            if let fn = setBrightnessFunc {
                _ = fn(CGMainDisplayID(), clamped)
            }
            HUDManager.shared.showHUD(type: .brightness, value: clamped, displayTitle: nil)
            return
        }

        let extManager = ExternalDisplayManager.shared
        let target = extManager.resolveTargetDisplay()

        if let target, !target.isBuiltIn, extManager.hasActiveExternalDisplays {
            extManager.setBrightness(displayID: target.id, value: clamped)
            return
        }

        if let fn = setBrightnessFunc {
            _ = fn(CGMainDisplayID(), clamped)
        }

        if DisplayControlPreferences.shared.syncBrightnessWithBuiltIn && extManager.hasActiveExternalDisplays {
            for ext in extManager.activeExternalDisplays {
                extManager.setBrightness(displayID: ext.id, value: clamped)
            }
        }

        let title = DisplayControlPreferences.shared.showDisplayTitleInHUD && extManager.hasActiveExternalDisplays
            ? localized("Built-in Display")
            : nil
        HUDManager.shared.showHUD(type: .brightness, value: clamped, displayTitle: title)
    }

    func increaseBrightness(step: Float = 0.0625) {
        let extManager = ExternalDisplayManager.shared
        if DisplayControlFeature.isActive, extManager.hasActiveExternalDisplays, let target = extManager.resolveTargetDisplay(), !target.isBuiltIn {
            extManager.increaseBrightness(step: step)
        } else {
            refreshBrightness()
            setBrightness(currentBrightness + step)
        }
    }

    func decreaseBrightness(step: Float = 0.0625) {
        let extManager = ExternalDisplayManager.shared
        if DisplayControlFeature.isActive, extManager.hasActiveExternalDisplays, let target = extManager.resolveTargetDisplay(), !target.isBuiltIn {
            extManager.decreaseBrightness(step: step)
        } else {
            refreshBrightness()
            setBrightness(currentBrightness - step)
        }
    }
}
