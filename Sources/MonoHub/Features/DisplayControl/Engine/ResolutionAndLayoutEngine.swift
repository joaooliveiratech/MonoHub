import AppKit
import CoreGraphics
import Foundation

private typealias SLSConfigureDisplayRotationFunc = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> CGError

@MainActor
final class ResolutionAndLayoutEngine {
    static let shared = ResolutionAndLayoutEngine()

    private let configureDisplayRotationFunc: SLSConfigureDisplayRotationFunc?

    private init() {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let skyLight,
           let sym = dlsym(skyLight, "SLSConfigureDisplayRotation") ?? dlsym(skyLight, "CGSConfigureDisplayRotation") {
            self.configureDisplayRotationFunc = unsafeBitCast(sym, to: SLSConfigureDisplayRotationFunc.self)
        } else {
            self.configureDisplayRotationFunc = nil
        }
    }

    func availableModes(for displayID: CGDirectDisplayID, includeLowResDuplicates: Bool = true) -> [DisplayModeItem] {
        let options: CFDictionary = [
            kCGDisplayShowDuplicateLowResolutionModes as String: includeLowResDuplicates ? kCFBooleanTrue! : kCFBooleanFalse!
        ] as CFDictionary

        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }

        let currentMode = CGDisplayCopyDisplayMode(displayID)
        let currentModeID = currentMode?.ioDisplayModeID ?? -1

        var maxNativeWidth = 1920
        var maxNativeHeight = 1080
        for m in cfModes where m.width == m.pixelWidth {
            if m.pixelWidth >= maxNativeWidth {
                maxNativeWidth = m.pixelWidth
                maxNativeHeight = m.pixelHeight
            }
        }
        let _ = maxNativeHeight

        var seenKeys = Set<String>()
        var items: [DisplayModeItem] = []

        for mode in cfModes {
            guard mode.isUsableForDesktopGUI() else { continue }
            let w = mode.width
            let h = mode.height
            let pw = mode.pixelWidth
            let ph = mode.pixelHeight
            guard w >= 640 && h >= 480 else { continue }

            let isHiDPI = pw > w
            let rate = mode.refreshRate > 0 ? mode.refreshRate : 60.0
            let rateKey = Int((rate * 10).rounded())
            let dedupKey = "\(w)x\(h)@\(isHiDPI ? "H" : "L")@\(rateKey)"

            let isCurrent = mode.ioDisplayModeID == currentModeID
            if seenKeys.contains(dedupKey) && !isCurrent {
                continue
            }
            seenKeys.insert(dedupKey)

            let isNative = (w == maxNativeWidth && pw == maxNativeWidth)
            let scalePct = maxNativeWidth > 0 ? Int(round(Double(maxNativeWidth) / Double(w) * 100.0)) : 100

            let item = DisplayModeItem(
                id: mode.ioDisplayModeID,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: rate,
                isHiDPI: isHiDPI,
                isNative: isNative,
                isCurrent: isCurrent,
                scalePercentage: scalePct
            )
            items.append(item)
        }

        items.sort { lhs, rhs in
            if lhs.isHiDPI != rhs.isHiDPI {
                return lhs.isHiDPI && !rhs.isHiDPI
            }
            if lhs.width != rhs.width {
                return lhs.width > rhs.width
            }
            if lhs.height != rhs.height {
                return lhs.height > rhs.height
            }
            return lhs.refreshRate > rhs.refreshRate
        }

        return items
    }

    @discardableResult
    func applyMode(_ item: DisplayModeItem, to displayID: CGDirectDisplayID) -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        let options: CFDictionary = [
            kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue!
        ] as CFDictionary

        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return false
        }

        let targetMode = cfModes.first(where: { $0.ioDisplayModeID == item.id }) ?? cfModes.first(where: {
            $0.width == item.width &&
            $0.height == item.height &&
            ($0.pixelWidth > $0.width) == item.isHiDPI &&
            abs(($0.refreshRate > 0 ? $0.refreshRate : 60.0) - item.refreshRate) < 1.0
        })

        guard let mode = targetMode else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let err = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    func currentRotation(for displayID: CGDirectDisplayID) -> DisplayRotation {
        let deg = Int(CGDisplayRotation(displayID).rounded())
        let normalized = ((deg % 360) + 360) % 360
        return DisplayRotation(rawValue: normalized) ?? .degree0
    }

    @discardableResult
    func setRotation(_ rotation: DisplayRotation, for displayID: CGDirectDisplayID) -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        guard let rotateFn = configureDisplayRotationFunc else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let err = rotateFn(config, displayID, Int32(rotation.rawValue))
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    @discardableResult
    func setMainDisplay(_ targetDisplayID: CGDirectDisplayID) -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        var activeIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &activeIDs, &count) == .success, count > 0 else { return false }

        let targetBounds = CGDisplayBounds(targetDisplayID)
        let deltaX = Int32(targetBounds.origin.x.rounded())
        let deltaY = Int32(targetBounds.origin.y.rounded())
        if deltaX == 0 && deltaY == 0 {
            return true
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }

        for i in 0..<Int(count) {
            let id = activeIDs[i]
            if id == targetDisplayID {
                CGConfigureDisplayOrigin(config, id, 0, 0)
            } else {
                let bounds = CGDisplayBounds(id)
                let newX = Int32(bounds.origin.x.rounded()) - deltaX
                let newY = Int32(bounds.origin.y.rounded()) - deltaY
                CGConfigureDisplayOrigin(config, id, newX, newY)
            }
        }

        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    @discardableResult
    func setMirroring(displayID: CGDirectDisplayID, masterDisplayID: CGDirectDisplayID?) -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let master = masterDisplayID ?? kCGNullDirectDisplay
        let err = CGConfigureDisplayMirrorOfDisplay(config, displayID, master)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    func captureCurrentLayout(name: String, displays: [ExternalDisplayDevice]) -> DisplayLayoutAnchor {
        let entries: [DisplayLayoutEntry] = displays.map { dev in
            let mirrorMasterUUID: String? = dev.mirrorMasterDisplayID.flatMap { masterID in
                displays.first(where: { $0.id == masterID })?.uuid
            }
            return DisplayLayoutEntry(
                displayUUID: dev.uuid,
                displayName: dev.name,
                originX: Int32(dev.origin.x.rounded()),
                originY: Int32(dev.origin.y.rounded()),
                width: Int(dev.logicalSize.width.rounded()),
                height: Int(dev.logicalSize.height.rounded()),
                isHiDPI: dev.isHiDPI,
                refreshRate: dev.refreshRate,
                rotation: dev.rotation.rawValue,
                isMainDisplay: dev.isMainDisplay,
                mirrorOfUUID: mirrorMasterUUID
            )
        }
        return DisplayLayoutAnchor(name: name, entries: entries)
    }

    func doesLayoutDiverge(from anchor: DisplayLayoutAnchor, currentDisplays: [ExternalDisplayDevice]) -> Bool {
        for entry in anchor.entries {
            guard let matched = currentDisplays.first(where: { $0.uuid == entry.displayUUID }) else { continue }
            if Int32(matched.origin.x.rounded()) != entry.originX || Int32(matched.origin.y.rounded()) != entry.originY {
                return true
            }
            if matched.rotation.rawValue != entry.rotation {
                return true
            }
            let currentMirrorUUID = matched.mirrorMasterDisplayID.flatMap { masterID in
                currentDisplays.first(where: { $0.id == masterID })?.uuid
            }
            if currentMirrorUUID != entry.mirrorOfUUID {
                return true
            }
        }
        return false
    }

    @discardableResult
    func restoreLayout(_ anchor: DisplayLayoutAnchor, currentDisplays: [ExternalDisplayDevice]) -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }

        for entry in anchor.entries {
            guard let matched = currentDisplays.first(where: { $0.uuid == entry.displayUUID }) else { continue }
            CGConfigureDisplayOrigin(config, matched.id, entry.originX, entry.originY)

            if let mirrorUUID = entry.mirrorOfUUID,
               let master = currentDisplays.first(where: { $0.uuid == mirrorUUID }) {
                CGConfigureDisplayMirrorOfDisplay(config, matched.id, master.id)
            } else {
                CGConfigureDisplayMirrorOfDisplay(config, matched.id, kCGNullDirectDisplay)
            }
        }

        let completed = CGCompleteDisplayConfiguration(config, .forSession) == .success

        for entry in anchor.entries {
            guard let matched = currentDisplays.first(where: { $0.uuid == entry.displayUUID }) else { continue }
            let modes = availableModes(for: matched.id)
            if let targetMode = modes.first(where: {
                $0.width == entry.width &&
                $0.height == entry.height &&
                $0.isHiDPI == entry.isHiDPI
            }) {
                if !targetMode.isCurrent {
                    _ = applyMode(targetMode, to: matched.id)
                }
            }
        }

        return completed
    }
}
