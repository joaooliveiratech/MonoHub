import AppKit
import CoreGraphics
import Foundation
import ObjectiveC.runtime

@MainActor
final class VirtualScreenEngine {
    static let shared = VirtualScreenEngine()

    private var activeVirtualObjects: [UUID: AnyObject] = [:]
    private var activeDisplayIDs: [UUID: CGDirectDisplayID] = [:]

    private init() {}

    @discardableResult
    func connectVirtualScreen(_ config: VirtualScreenConfig) -> CGDirectDisplayID? {
        guard DisplayControlGate.isOpen else { return nil }
        if let existingID = activeDisplayIDs[config.id] {
            return existingID
        }

        guard !AppInfo.isRunningTests else {

            let simulatedID = CGDirectDisplayID(0x7F00_0000 | UInt32( config.id.hashValue & 0xFFFF ))
            activeDisplayIDs[config.id] = simulatedID
            return simulatedID
        }

        guard let descClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            return nil
        }

        let descriptor = descClass.init()
        descriptor.setValue(config.name, forKey: "name")
        descriptor.setValue(NSNumber(value: config.maxWidth), forKey: "maxPixelsWide")
        descriptor.setValue(NSNumber(value: config.maxHeight), forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: NSSize(width: 600, height: 340)), forKey: "sizeInMillimeters")
        descriptor.setValue(NSNumber(value: 0xF0F0), forKey: "vendorID")
        descriptor.setValue(NSNumber(value: UInt16(truncatingIfNeeded: config.id.hashValue)), forKey: "productID")
        descriptor.setValue(NSNumber(value: UInt32(truncatingIfNeeded: config.id.hashValue)), forKey: "serialNum")

        typealias InitModeFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
        let initModeSel = NSSelectorFromString("initWithWidth:height:refreshRate:")

        var modeObjects: [AnyObject] = []
        for res in config.aspectRatio.baseResolutions where res.width <= config.maxWidth && res.height <= config.maxHeight {
            let allocated = (modeClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
            if let allocated, let imp = class_getMethodImplementation(modeClass, initModeSel) {
                let fn = unsafeBitCast(imp, to: InitModeFunc.self)
                if let initialized = fn(allocated, initModeSel, UInt32(res.width), UInt32(res.height), config.refreshRate) {
                    modeObjects.append(initialized)
                }
            }
        }

        if modeObjects.isEmpty {
            let allocated = (modeClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
            if let allocated, let imp = class_getMethodImplementation(modeClass, initModeSel) {
                let fn = unsafeBitCast(imp, to: InitModeFunc.self)
                if let initialized = fn(allocated, initModeSel, UInt32(config.maxWidth), UInt32(config.maxHeight), config.refreshRate) {
                    modeObjects.append(initialized)
                }
            }
        }

        let settings = settingsClass.init()
        settings.setValue(NSNumber(value: config.hiDPIEnabled ? 1 : 0), forKey: "hiDPI")
        settings.setValue(modeObjects, forKey: "modes")

        typealias InitDisplayFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
        typealias ApplySettingsFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool

        let initDescSel = NSSelectorFromString("initWithDescriptor:")
        let applySel = NSSelectorFromString("applySettings:")

        guard let allocatedDisplay = (displayClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let initImp = class_getMethodImplementation(displayClass, initDescSel) else {
            return nil
        }

        let initFn = unsafeBitCast(initImp, to: InitDisplayFunc.self)
        guard let virtualDisplay = initFn(allocatedDisplay, initDescSel, descriptor) else {
            return nil
        }

        if let applyImp = class_getMethodImplementation(displayClass, applySel) {
            let applyFn = unsafeBitCast(applyImp, to: ApplySettingsFunc.self)
            _ = applyFn(virtualDisplay, applySel, settings)
        }

        let displayIDNumber = (virtualDisplay as? NSObject)?.value(forKey: "displayID") as? NSNumber
        let assignedID = CGDirectDisplayID(displayIDNumber?.uint32Value ?? 0)

        activeVirtualObjects[config.id] = virtualDisplay
        activeDisplayIDs[config.id] = assignedID

        if let assocUUID = config.associatedDisplayUUID,
           let target = ExternalDisplayManager.shared.displays.first(where: { $0.uuid == assocUUID }),
           assignedID != 0 {
            _ = ResolutionAndLayoutEngine.shared.setMirroring(displayID: target.id, masterDisplayID: assignedID)
        }

        ExternalDisplayManager.shared.refreshDisplays()
        return assignedID
    }

    func disconnectVirtualScreen(id: UUID) {
        activeVirtualObjects.removeValue(forKey: id)
        activeDisplayIDs.removeValue(forKey: id)
        if !AppInfo.isRunningTests {
            ExternalDisplayManager.shared.refreshDisplays()
        }
    }

    func disconnectAll() {
        let ids = Array(activeVirtualObjects.keys)
        for id in ids {
            disconnectVirtualScreen(id: id)
        }
    }

    func activeDisplayID(for id: UUID) -> CGDirectDisplayID? {
        activeDisplayIDs[id]
    }

    func isVirtualDisplayID(_ displayID: CGDirectDisplayID) -> Bool {
        activeDisplayIDs.values.contains(displayID)
    }
}
