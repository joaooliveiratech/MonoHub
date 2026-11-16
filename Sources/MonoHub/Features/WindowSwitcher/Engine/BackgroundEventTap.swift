import CoreGraphics
import Foundation

nonisolated final class BackgroundEventTap: @unchecked Sendable {
    private let port: CFMachPort
    private let source: CFRunLoopSource
    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    init?(mask: CGEventMask, callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) {
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        self.port = port
        self.source = source
    }

    func start(name: String) {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            lock.withLock { runLoop = loop }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func reenable() {
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func invalidate() {
        CGEvent.tapEnable(tap: port, enable: false)
        let loop = lock.withLock {
            let current = runLoop
            runLoop = nil
            return current
        }
        if let loop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        CFMachPortInvalidate(port)
    }
}
