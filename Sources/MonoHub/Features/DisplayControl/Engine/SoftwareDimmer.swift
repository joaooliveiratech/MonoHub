import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

nonisolated final class SoftwareDimmer: @unchecked Sendable {
    static let shared = SoftwareDimmer()

    private let lock = NSLock()
    private var originalTables: [CGDirectDisplayID: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])] = [:]
    private var currentFactors: [CGDirectDisplayID: Float] = [:]
    private var currentColorAdjustments: [CGDirectDisplayID: DisplayColorAdjustment] = [:]

    private var modifiedDisplays: Set<CGDirectDisplayID> = []

    private init() {}

    private func captureOriginalLocked(displayID: CGDirectDisplayID) {
        guard originalTables[displayID] == nil else { return }

        var count: UInt32 = 0
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = [CGGammaValue](repeating: 0, count: 256)
        var blue = [CGGammaValue](repeating: 0, count: 256)

        let status = CGGetDisplayTransferByTable(displayID, 256, &red, &green, &blue, &count)
        if status == .success && count > 0 {
            originalTables[displayID] = (red: red, green: green, blue: blue)
        } else {
            let linear: [CGGammaValue] = (0..<256).map { CGGammaValue(Double($0) / 255.0) }
            originalTables[displayID] = (red: linear, green: linear, blue: linear)
        }
    }

    func applyDimming(displayID: CGDirectDisplayID, factor: Float) {
        guard DisplayControlGate.isOpen else { return }
        let clampedFactor = max(0.01, min(1.0, factor))
        lock.lock()
        captureOriginalLocked(displayID: displayID)
        currentFactors[displayID] = clampedFactor
        let colorAdj = currentColorAdjustments[displayID] ?? DisplayColorAdjustment()
        let base = originalTables[displayID]
        lock.unlock()

        guard let base else { return }
        applyCompositeTransfer(displayID: displayID, base: base, factor: clampedFactor, color: colorAdj)
    }

    func applyColorAdjustment(displayID: CGDirectDisplayID, adjustment: DisplayColorAdjustment) {
        guard DisplayControlGate.isOpen else { return }
        lock.lock()
        captureOriginalLocked(displayID: displayID)
        currentColorAdjustments[displayID] = adjustment
        let factor = currentFactors[displayID] ?? 1.0
        let base = originalTables[displayID]
        lock.unlock()

        guard let base else { return }
        applyCompositeTransfer(displayID: displayID, base: base, factor: factor, color: adjustment)
    }

    static func computeTransferTables(
        base: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]),
        factor: Float,
        color: DisplayColorAdjustment
    ) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        let count = base.red.count
        var modRed = [CGGammaValue](repeating: 0, count: count)
        var modGreen = [CGGammaValue](repeating: 0, count: count)
        var modBlue = [CGGammaValue](repeating: 0, count: count)

        let kelvinRGB = DisplayColorAdjustment.kelvinToRGB(kelvin: color.temperatureKelvin)
        let rScale = max(0.0, min(1.5, factor * color.redGain * kelvinRGB.r))
        let gScale = max(0.0, min(1.5, factor * color.greenGain * kelvinRGB.g))
        let bScale = max(0.0, min(1.5, factor * color.blueGain * kelvinRGB.b))

        let gammaExp = max(0.25, min(3.0, 1.0 - color.gammaOffset))
        let contrast = max(0.2, min(2.0, color.softwareContrast))

        for i in 0..<count {
            func transformChannel(_ sample: CGGammaValue, scale: Float) -> CGGammaValue {
                var v = Float(sample)
                if abs(gammaExp - 1.0) > 0.005 {
                    v = pow(max(0.0, v), gammaExp)
                }
                if abs(contrast - 1.0) > 0.005 {
                    v = (v - 0.5) * contrast + 0.5
                }
                v *= scale
                v = max(0.0, min(1.0, v))
                if color.isInverted {
                    v = 1.0 - v
                }
                return CGGammaValue(v)
            }

            let rVal = transformChannel(base.red[i], scale: rScale)
            let gVal = transformChannel(base.green[i], scale: gScale)
            let bVal = transformChannel(base.blue[i], scale: bScale)

            if color.isGrayscale {
                let luma = 0.2126 * rVal + 0.7152 * gVal + 0.0722 * bVal
                modRed[i] = luma
                modGreen[i] = luma
                modBlue[i] = luma
            } else {
                modRed[i] = rVal
                modGreen[i] = gVal
                modBlue[i] = bVal
            }
        }

        return (modRed, modGreen, modBlue)
    }

    private func applyCompositeTransfer(
        displayID: CGDirectDisplayID,
        base: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]),
        factor: Float,
        color: DisplayColorAdjustment
    ) {
        if factor >= 0.999 && color.isIdentity {

            lock.lock()
            let wasModified = modifiedDisplays.remove(displayID) != nil
            lock.unlock()
            if wasModified {
                CGDisplayRestoreColorSyncSettings()
            }
            return
        }

        lock.lock()
        modifiedDisplays.insert(displayID)
        lock.unlock()
        var tables = Self.computeTransferTables(base: base, factor: factor, color: color)
        _ = CGSetDisplayTransferByTable(displayID, UInt32(tables.red.count), &tables.red, &tables.green, &tables.blue)
    }

    var hasModifiedDisplays: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !modifiedDisplays.isEmpty
    }

    func restore(displayID: CGDirectDisplayID) {
        lock.lock()
        originalTables.removeValue(forKey: displayID)
        currentFactors.removeValue(forKey: displayID)
        currentColorAdjustments.removeValue(forKey: displayID)
        let wasModified = modifiedDisplays.remove(displayID) != nil
        lock.unlock()

        if wasModified {
            CGDisplayRestoreColorSyncSettings()
        }
    }

    func restoreAll() {
        lock.lock()
        let wasModified = !modifiedDisplays.isEmpty
        originalTables.removeAll()
        currentFactors.removeAll()
        currentColorAdjustments.removeAll()
        modifiedDisplays.removeAll()
        lock.unlock()

        if wasModified {
            CGDisplayRestoreColorSyncSettings()
        }
    }
}
