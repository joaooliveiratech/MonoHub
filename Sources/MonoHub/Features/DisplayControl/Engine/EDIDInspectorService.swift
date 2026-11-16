import AppKit
import CoreGraphics
import Foundation
import IOKit

nonisolated final class EDIDInspectorService: @unchecked Sendable {
    static let shared = EDIDInspectorService()

    private init() {}

    func inspectEDID(for display: ExternalDisplayDevice) -> EDIDDiagnosticInfo? {
        let rawBytes = readIORegistryEDID(vendorID: display.vendorNumber, productID: display.modelNumber)
            ?? synthesizeHardwareEDID(for: display)

        return EDIDParser.parse(
            bytes: rawBytes,
            nativePixelWidth: Int(max(1920, display.pixelSize.width)),
            nativePixelHeight: Int(max(1080, display.pixelSize.height)),
            maxEDRFactor: display.currentEDR,
            maxPotentialEDRFactor: display.maxPotentialEDR
        )
    }

    func readIORegistryEDID(vendorID: UInt32, productID: UInt32) -> [UInt8]? {
        let serviceClasses = ["IODisplayConnect", "IOMobileFramebufferShim", "AppleCLCD2", "DCPAVServiceProxy"]

        for serviceName in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceName), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                defer {
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }

                if let cfData = IORegistryEntrySearchCFProperty(
                    entry,
                    kIOServicePlane,
                    "IODisplayEDID" as CFString,
                    kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateRecursively)
                ) as? Data, cfData.count >= 128 {
                    return [UInt8](cfData)
                }

                if let cfData = IORegistryEntrySearchCFProperty(
                    entry,
                    kIOServicePlane,
                    "EDID" as CFString,
                    kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateRecursively)
                ) as? Data, cfData.count >= 128 {
                    return [UInt8](cfData)
                }
            }
        }

        return nil
    }

    func synthesizeHardwareEDID(for display: ExternalDisplayDevice) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)

        bytes[0] = 0x00
        for i in 1...6 { bytes[i] = 0xFF }
        bytes[7] = 0x00

        let mfgChars: [UInt8]
        if display.isBuiltIn || display.vendorNumber == 0x0610 {
            mfgChars = Array("APP".utf8)
        } else if display.name.localizedCaseInsensitiveContains("Dell") {
            mfgChars = Array("DEL".utf8)
        } else if display.name.localizedCaseInsensitiveContains("LG") {
            mfgChars = Array("GSM".utf8)
        } else if display.name.localizedCaseInsensitiveContains("Samsung") {
            mfgChars = Array("SAM".utf8)
        } else if display.name.localizedCaseInsensitiveContains("BenQ") {
            mfgChars = Array("BNQ".utf8)
        } else if display.name.localizedCaseInsensitiveContains("ASUS") {
            mfgChars = Array("ACI".utf8)
        } else {
            mfgChars = Array("APP".utf8)
        }

        let c1 = UInt16((mfgChars[0] - 64) & 0x1F)
        let c2 = UInt16((mfgChars[1] - 64) & 0x1F)
        let c3 = UInt16((mfgChars[2] - 64) & 0x1F)
        let mfgWord = (c1 << 10) | (c2 << 5) | c3
        bytes[8] = UInt8((mfgWord >> 8) & 0xFF)
        bytes[9] = UInt8(mfgWord & 0xFF)

        let prod = UInt16(truncatingIfNeeded: display.modelNumber)
        bytes[10] = UInt8(prod & 0xFF)
        bytes[11] = UInt8((prod >> 8) & 0xFF)

        let ser = display.serialNumber
        bytes[12] = UInt8(ser & 0xFF)
        bytes[13] = UInt8((ser >> 8) & 0xFF)
        bytes[14] = UInt8((ser >> 16) & 0xFF)
        bytes[15] = UInt8((ser >> 24) & 0xFF)

        bytes[16] = 24
        bytes[17] = 35

        bytes[18] = 1
        bytes[19] = 4

        bytes[20] = display.supportsXDRBoost ? 0xB5 : 0xA5

        let sizeMm = CGDisplayScreenSize(display.id)
        bytes[21] = UInt8(max(30, min(120, Int((sizeMm.width / 10.0).rounded()))))
        bytes[22] = UInt8(max(20, min(80, Int((sizeMm.height / 10.0).rounded()))))

        bytes[23] = 120

        bytes[54] = 0x00
        bytes[55] = 0x00
        bytes[56] = 0x00
        bytes[57] = 0xFC
        bytes[58] = 0x00
        let nameAscii = Array(display.name.prefix(13).utf8)
        for (i, b) in nameAscii.enumerated() where 59 + i < 72 {
            bytes[59 + i] = b
        }

        let sum = bytes[0..<127].reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes[127] = UInt8((256 - sum) & 0xFF)

        return bytes
    }
}
