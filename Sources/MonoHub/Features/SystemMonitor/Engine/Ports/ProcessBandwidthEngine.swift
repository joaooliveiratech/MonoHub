import Darwin
import Foundation
import Synchronization

nonisolated struct ProcessBandwidth: Sendable, Equatable, Hashable {
    let pid: pid_t
    let processName: String
    let downloadBytesPerSec: UInt64
    let uploadBytesPerSec: UInt64
    let totalDownloaded: UInt64
    let totalUploaded: UInt64
    let activeSocketCount: Int
    let lastActiveTimestamp: UInt64

    var totalSpeed: UInt64 {
        downloadBytesPerSec &+ uploadBytesPerSec
    }

    var hasTraffic: Bool {
        downloadBytesPerSec > 0 || uploadBytesPerSec > 0
    }
}

nonisolated struct BandwidthSnapshot: Sendable, Equatable {
    let processes: [pid_t: ProcessBandwidth]
    let totalDownloadSpeed: UInt64
    let totalUploadSpeed: UInt64
    let topConsumerPID: pid_t?
    let topConsumerSpeed: UInt64
    let topConsumerName: String?
    let timestamp: UInt64

    static let empty = BandwidthSnapshot(
        processes: [:],
        totalDownloadSpeed: 0,
        totalUploadSpeed: 0,
        topConsumerPID: nil,
        topConsumerSpeed: 0,
        topConsumerName: nil,
        timestamp: 0
    )
}

nonisolated final class ProcessBandwidthEngine: Sendable {
    static let shared = ProcessBandwidthEngine()

    private typealias NStatManagerRef = OpaquePointer
    private typealias NStatSourceRef = OpaquePointer

    private typealias NStatManagerCreateFunc = @convention(c) (
        CFAllocator?,
        DispatchQueue,
        @escaping @convention(block) (NStatSourceRef) -> Void
    ) -> NStatManagerRef?

    private typealias NStatManagerDestroyFunc = @convention(c) (NStatManagerRef) -> Void
    private typealias NStatManagerAddFunc = @convention(c) (NStatManagerRef) -> Void
    private typealias NStatSourceSetDescriptionBlockFunc = @convention(c) (NStatSourceRef, @escaping @convention(block) (NSDictionary) -> Void) -> Void
    private typealias NStatSourceSetCountsBlockFunc = @convention(c) (NStatSourceRef, @escaping @convention(block) (NSDictionary) -> Void) -> Void
    private typealias NStatSourceSetRemovedBlockFunc = @convention(c) (NStatSourceRef, @escaping @convention(block) () -> Void) -> Void
    private typealias NStatManagerQueryFunc = @convention(c) (NStatManagerRef, @escaping @convention(block) () -> Void) -> Void

    private final class SourceItem: @unchecked Sendable {
        var pid: pid_t = 0
        var name: String = ""
        var rxBytes: UInt64 = 0
        var txBytes: UInt64 = 0
    }

    private final class State: @unchecked Sendable {
        var manager: NStatManagerRef?
        var sources: [NStatSourceRef: SourceItem] = [:]
        var previousPIDTotals: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
        var lastSampleTime: UInt64 = 0
        var latestSnapshot: BandwidthSnapshot = .empty
        var isInitialized = false
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "com.antigravity.monohub.networkstatistics", qos: .utility)

    private let nstatCreate: NStatManagerCreateFunc?
    private let nstatDestroy: NStatManagerDestroyFunc?
    private let nstatAddAllTCP: NStatManagerAddFunc?
    private let nstatAddAllUDP: NStatManagerAddFunc?
    private let nstatQueryAllSources: NStatManagerQueryFunc?
    private let nstatQueryAllDescriptions: NStatManagerQueryFunc?
    private let nstatSetDescriptionBlock: NStatSourceSetDescriptionBlockFunc?
    private let nstatSetCountsBlock: NStatSourceSetCountsBlockFunc?
    private let nstatSetRemovedBlock: NStatSourceSetRemovedBlockFunc?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_NOW)
        if let handle {
            if let sym = dlsym(handle, "NStatManagerCreate") {
                nstatCreate = unsafeBitCast(sym, to: NStatManagerCreateFunc.self)
            } else { nstatCreate = nil }

            if let sym = dlsym(handle, "NStatManagerDestroy") {
                nstatDestroy = unsafeBitCast(sym, to: NStatManagerDestroyFunc.self)
            } else { nstatDestroy = nil }

            if let sym = dlsym(handle, "NStatManagerAddAllTCP") {
                nstatAddAllTCP = unsafeBitCast(sym, to: NStatManagerAddFunc.self)
            } else { nstatAddAllTCP = nil }

            if let sym = dlsym(handle, "NStatManagerAddAllUDP") {
                nstatAddAllUDP = unsafeBitCast(sym, to: NStatManagerAddFunc.self)
            } else { nstatAddAllUDP = nil }

            if let sym = dlsym(handle, "NStatManagerQueryAllSources") {
                nstatQueryAllSources = unsafeBitCast(sym, to: NStatManagerQueryFunc.self)
            } else { nstatQueryAllSources = nil }

            if let sym = dlsym(handle, "NStatManagerQueryAllSourcesDescriptions") {
                nstatQueryAllDescriptions = unsafeBitCast(sym, to: NStatManagerQueryFunc.self)
            } else { nstatQueryAllDescriptions = nil }

            if let sym = dlsym(handle, "NStatSourceSetDescriptionBlock") {
                nstatSetDescriptionBlock = unsafeBitCast(sym, to: NStatSourceSetDescriptionBlockFunc.self)
            } else { nstatSetDescriptionBlock = nil }

            if let sym = dlsym(handle, "NStatSourceSetCountsBlock") {
                nstatSetCountsBlock = unsafeBitCast(sym, to: NStatSourceSetCountsBlockFunc.self)
            } else { nstatSetCountsBlock = nil }

            if let sym = dlsym(handle, "NStatSourceSetRemovedBlock") {
                nstatSetRemovedBlock = unsafeBitCast(sym, to: NStatSourceSetRemovedBlockFunc.self)
            } else { nstatSetRemovedBlock = nil }
        } else {
            nstatCreate = nil
            nstatDestroy = nil
            nstatAddAllTCP = nil
            nstatAddAllUDP = nil
            nstatQueryAllSources = nil
            nstatQueryAllDescriptions = nil
            nstatSetDescriptionBlock = nil
            nstatSetCountsBlock = nil
            nstatSetRemovedBlock = nil
        }

    }

    deinit {
        state.withLock { s in
            if let mgr = s.manager, let destroy = nstatDestroy {
                destroy(mgr)
                s.manager = nil
            }
        }
    }

    private func setupManagerIfNeeded() {
        guard let create = nstatCreate,
              let addTCP = nstatAddAllTCP,
              let addUDP = nstatAddAllUDP,
              let setDesc = nstatSetDescriptionBlock,
              let setCounts = nstatSetCountsBlock else {
            return
        }

        state.withLock { s in
            guard !s.isInitialized else { return }
            s.isInitialized = true

            let mgr = create(kCFAllocatorDefault, queue) { [weak self] source in
                guard let self else { return }
                let item = SourceItem()

                self.state.withLock { inner in
                    inner.sources[source] = item
                }

                setDesc(source) { [weak item] desc in
                    guard let item else { return }
                    if let pidNum = desc["processID"] as? NSNumber {
                        item.pid = pidNum.int32Value
                    }
                    if let pName = desc["processName"] as? String, !pName.isEmpty {
                        item.name = pName
                    }
                }

                setCounts(source) { [weak item] counts in
                    guard let item else { return }
                    if let rx = (counts["rxBytes"] as? NSNumber)?.uint64Value {
                        item.rxBytes = rx
                    }
                    if let tx = (counts["txBytes"] as? NSNumber)?.uint64Value {
                        item.txBytes = tx
                    }
                }

                if let setRemoved = self.nstatSetRemovedBlock {
                    setRemoved(source) { [weak self] in
                        _ = self?.state.withLock { inner in
                            inner.sources.removeValue(forKey: source)
                        }
                    }
                }
            }

            if let mgr {
                s.manager = mgr
                addTCP(mgr)
                addUDP(mgr)
            }
        }
    }

    func latestSnapshot() -> BandwidthSnapshot {
        state.withLock { $0.latestSnapshot }
    }

    func bandwidth(for pid: pid_t) -> ProcessBandwidth? {
        state.withLock { $0.latestSnapshot.processes[pid] }
    }

    func sample() async -> BandwidthSnapshot {
        setupManagerIfNeeded()
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                performSampleAsync { snapshot in
                    continuation.resume(returning: snapshot)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            state.withLock { s in
                if let mgr = s.manager, let destroy = nstatDestroy {
                    destroy(mgr)
                    s.manager = nil
                }
                s.sources.removeAll()
                s.previousPIDTotals.removeAll()
                s.lastSampleTime = 0
                s.latestSnapshot = .empty
                s.isInitialized = false
            }
        }
    }

    private func performSampleAsync(completion: @escaping @Sendable (BandwidthSnapshot) -> Void) {
        let mgr: NStatManagerRef? = state.withLock { $0.manager }
        guard let mgr,
              let queryDescriptions = nstatQueryAllDescriptions,
              let queryCounts = nstatQueryAllSources else {
            completion(state.withLock { $0.latestSnapshot })
            return
        }

        // All NetworkStatistics callbacks execute on `queue`, so chaining them asynchronously
        // avoids blocking Swift Concurrency's cooperative thread pool and eliminates data races
        // on SourceItem fields.
        runQueryWithTimeout(on: mgr, query: queryDescriptions) { [self] in
            guard let activeManager = state.withLock({ $0.manager }) else {
                completion(state.withLock { $0.latestSnapshot })
                return
            }
            runQueryWithTimeout(on: activeManager, query: queryCounts) { [self] in
                completion(finalizeSnapshot())
            }
        }
    }

    private func runQueryWithTimeout(
        on manager: NStatManagerRef,
        query: NStatManagerQueryFunc,
        timeout: DispatchTimeInterval = .milliseconds(400),
        completion: @escaping @Sendable () -> Void
    ) {
        let completed = Atomic<Bool>(false)
        let finish: @Sendable () -> Void = {
            guard !completed.exchange(true, ordering: .acquiringAndReleasing) else { return }
            completion()
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: finish)
        query(manager) {
            finish()
        }
    }

    private func finalizeSnapshot() -> BandwidthSnapshot {
        let now = DispatchTime.now().uptimeNanoseconds

        return state.withLock { s -> BandwidthSnapshot in
            var currentTotals: [pid_t: (name: String, rx: UInt64, tx: UInt64, sockets: Int)] = [:]
            currentTotals.reserveCapacity(s.sources.count)
            for (_, item) in s.sources where item.pid > 0 {
                var entry = currentTotals[item.pid] ?? (name: item.name, rx: 0, tx: 0, sockets: 0)
                entry.rx &+= item.rxBytes
                entry.tx &+= item.txBytes
                entry.sockets += 1
                if !item.name.isEmpty { entry.name = item.name }
                currentTotals[item.pid] = entry
            }

            let elapsedSeconds = s.lastSampleTime > 0 && now > s.lastSampleTime
                ? Double(now - s.lastSampleTime) / 1_000_000_000.0
                : 1.0

            let snapshot = Self.computeSnapshot(
                previous: s.previousPIDTotals,
                current: currentTotals,
                elapsedSeconds: elapsedSeconds,
                timestamp: now
            )

            var newPrevious: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
            newPrevious.reserveCapacity(currentTotals.count)
            for (pid, entry) in currentTotals {
                newPrevious[pid] = (rx: entry.rx, tx: entry.tx)
            }

            s.previousPIDTotals = newPrevious
            s.lastSampleTime = now
            s.latestSnapshot = snapshot
            return snapshot
        }
    }

    static func computeSnapshot(
        previous: [pid_t: (rx: UInt64, tx: UInt64)],
        current: [pid_t: (name: String, rx: UInt64, tx: UInt64, sockets: Int)],
        elapsedSeconds: Double,
        timestamp: UInt64
    ) -> BandwidthSnapshot {
        guard elapsedSeconds > 0 else {
            return .empty
        }

        var processMap: [pid_t: ProcessBandwidth] = [:]
        processMap.reserveCapacity(current.count)

        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var topPID: pid_t?
        var topSpeed: UInt64 = 0
        var topName: String?

        for (pid, entry) in current {
            var rxRate: UInt64 = 0
            var txRate: UInt64 = 0

            if let prev = previous[pid] {
                if entry.rx >= prev.rx {
                    let diff = Double(entry.rx - prev.rx) / elapsedSeconds
                    rxRate = UInt64(clamping: Int64(diff.rounded()))
                }
                if entry.tx >= prev.tx {
                    let diff = Double(entry.tx - prev.tx) / elapsedSeconds
                    txRate = UInt64(clamping: Int64(diff.rounded()))
                }
            }

            let speed = rxRate &+ txRate
            totalDown &+= rxRate
            totalUp &+= txRate

            if speed > topSpeed {
                topSpeed = speed
                topPID = pid
                topName = entry.name
            }

            processMap[pid] = ProcessBandwidth(
                pid: pid,
                processName: entry.name,
                downloadBytesPerSec: rxRate,
                uploadBytesPerSec: txRate,
                totalDownloaded: entry.rx,
                totalUploaded: entry.tx,
                activeSocketCount: entry.sockets,
                lastActiveTimestamp: speed > 0 ? timestamp : 0
            )
        }

        return BandwidthSnapshot(
            processes: processMap,
            totalDownloadSpeed: totalDown,
            totalUploadSpeed: totalUp,
            topConsumerPID: topPID,
            topConsumerSpeed: topSpeed,
            topConsumerName: topName,
            timestamp: timestamp
        )
    }
}
