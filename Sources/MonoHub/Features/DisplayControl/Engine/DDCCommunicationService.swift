import ApplicationServices
import CoreGraphics
import Foundation
import IOKit

private typealias IOAVServiceCreateWithServiceFunc = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
private typealias IOAVServiceReadI2CFunc = @convention(c) (AnyObject?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, UInt32) -> IOReturn
private typealias IOAVServiceWriteI2CFunc = @convention(c) (AnyObject?, UInt32, UInt32, UnsafePointer<UInt8>?, UInt32) -> IOReturn

nonisolated final class DDCCommunicationService: @unchecked Sendable {
    static let shared = DDCCommunicationService()

    private let queue = DispatchQueue(label: "com.antigravity.monohub.ddc", qos: .userInitiated)
    private let servicesLock = NSLock()
    private var _avServices: [CGDirectDisplayID: AnyObject] = [:]
    private var avServices: [CGDirectDisplayID: AnyObject] {
        get { servicesLock.withLock { _avServices } }
        set { servicesLock.withLock { _avServices = newValue } }
    }
    private var lastWriteTimes: [CGDirectDisplayID: DispatchTime] = [:]

    private let createWithServiceFunc: IOAVServiceCreateWithServiceFunc?
    private let readI2CFunc: IOAVServiceReadI2CFunc?
    private let writeI2CFunc: IOAVServiceWriteI2CFunc?

    private init() {
        let iokitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

        if let handle = iokitHandle {
            if let sym = dlsym(handle, "IOAVServiceCreateWithService") {
                self.createWithServiceFunc = unsafeBitCast(sym, to: IOAVServiceCreateWithServiceFunc.self)
            } else {
                self.createWithServiceFunc = nil
            }

            if let sym = dlsym(handle, "IOAVServiceReadI2C") {
                self.readI2CFunc = unsafeBitCast(sym, to: IOAVServiceReadI2CFunc.self)
            } else {
                self.readI2CFunc = nil
            }

            if let sym = dlsym(handle, "IOAVServiceWriteI2C") {
                self.writeI2CFunc = unsafeBitCast(sym, to: IOAVServiceWriteI2CFunc.self)
            } else {
                self.writeI2CFunc = nil
            }
        } else {
            self.createWithServiceFunc = nil
            self.readI2CFunc = nil
            self.writeI2CFunc = nil
        }

    }

    func refreshServices() {
        guard DisplayControlGate.isOpen else { return }
        queue.async { [weak self] in
            guard let self = self, let createFunc = self.createWithServiceFunc else { return }

            var newServices: [CGDirectDisplayID: AnyObject] = [:]

            var externalProxies: [AnyObject] = []
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)

            if result == KERN_SUCCESS {
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    var isEmbedded = false
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        if let loc = dict["Location"] as? String, loc.caseInsensitiveCompare("Embedded") == .orderedSame {
                            isEmbedded = true
                        }
                    }

                    if !isEmbedded {
                        if let avService = createFunc(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                            externalProxies.append(avService)
                        }
                    }

                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }

            var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            if CGGetActiveDisplayList(16, &activeDisplays, &count) == .success {
                let externalDisplays = (0..<Int(count)).map { activeDisplays[$0] }.filter { CGDisplayIsBuiltin($0) == 0 }

                for (idx, displayID) in externalDisplays.enumerated() {
                    if idx < externalProxies.count {
                        newServices[displayID] = externalProxies[idx]
                    }
                }
            }

            self.avServices = DisplayControlGate.isOpen ? newServices : [:]
        }
    }

    func hasDDCService(for displayID: CGDirectDisplayID) -> Bool {
        avServices[displayID] != nil
    }

    func releaseServices() {
        avServices = [:]
        queue.async { [weak self] in
            self?.lastWriteTimes.removeAll()
        }
    }

    func write(
        displayID: CGDirectDisplayID,
        code: DDCProtocol.VCPCode,
        value: UInt16,
        retries: Int = 3,
        sleepMs: Int = 25
    ) async -> Bool {
        guard DisplayControlGate.isOpen else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, DisplayControlGate.isOpen else {
                    continuation.resume(returning: false)
                    return
                }

                if let last = self.lastWriteTimes[displayID] {
                    let elapsed = DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds
                    let minWait = UInt64(max(5, sleepMs)) * 1_000_000
                    if elapsed < minWait {
                        Thread.sleep(forTimeInterval: Double(minWait - elapsed) / 1_000_000_000.0)
                    }
                }
                self.lastWriteTimes[displayID] = DispatchTime.now()

                guard let writeFunc = self.writeI2CFunc,
                      let service = self.avServices[displayID] else {
                    continuation.resume(returning: false)
                    return
                }

                let packet = DDCProtocol.buildSetVCPPacket(code: code, value: value)
                var success = false

                for attempt in 0..<max(1, retries) {
                    let status = packet.withUnsafeBufferPointer { ptr in
                        writeFunc(
                            service,
                            UInt32(DDCProtocol.i2cAddress7Bit),
                            UInt32(DDCProtocol.sourceAddress),
                            ptr.baseAddress,
                            UInt32(packet.count)
                        )
                    }

                    if status == KERN_SUCCESS {
                        success = true
                        break
                    }

                    if attempt < retries - 1 {
                        Thread.sleep(forTimeInterval: Double(sleepMs) / 1000.0)
                    }
                }

                continuation.resume(returning: success)
            }
        }
    }

    func read(
        displayID: CGDirectDisplayID,
        code: DDCProtocol.VCPCode,
        retries: Int = 3,
        sleepMs: Int = 35
    ) async -> (current: UInt16, max: UInt16)? {
        guard DisplayControlGate.isOpen else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self,
                      DisplayControlGate.isOpen,
                      let writeFunc = self.writeI2CFunc,
                      let readFunc = self.readI2CFunc,
                      let service = self.avServices[displayID] else {
                    continuation.resume(returning: nil)
                    return
                }

                let requestPacket = DDCProtocol.buildGetVCPPacket(code: code)

                for attempt in 0..<max(1, retries) {
                    let writeStatus = requestPacket.withUnsafeBufferPointer { ptr in
                        writeFunc(
                            service,
                            UInt32(DDCProtocol.i2cAddress7Bit),
                            UInt32(DDCProtocol.sourceAddress),
                            ptr.baseAddress,
                            UInt32(requestPacket.count)
                        )
                    }

                    guard writeStatus == KERN_SUCCESS else {
                        if attempt < retries - 1 {
                            Thread.sleep(forTimeInterval: Double(sleepMs) / 1000.0)
                        }
                        continue
                    }

                    Thread.sleep(forTimeInterval: Double(max(20, sleepMs)) / 1000.0)

                    var replyBuffer = [UInt8](repeating: 0, count: 12)
                    let readStatus = replyBuffer.withUnsafeMutableBufferPointer { ptr in
                        readFunc(
                            service,
                            UInt32(DDCProtocol.i2cAddress7Bit),
                            UInt32(DDCProtocol.sourceAddress),
                            ptr.baseAddress,
                            UInt32(ptr.count)
                        )
                    }

                    if readStatus == KERN_SUCCESS {
                        if let result = DDCProtocol.parseVCPReply(reply: replyBuffer, expectedCode: code) {
                            continuation.resume(returning: result)
                            return
                        }
                    }

                    if attempt < retries - 1 {
                        Thread.sleep(forTimeInterval: Double(sleepMs) / 1000.0)
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
