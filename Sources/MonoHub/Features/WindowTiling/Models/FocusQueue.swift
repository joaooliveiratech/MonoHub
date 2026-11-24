import CoreGraphics
import Foundation

struct FocusWindowRef: Identifiable, Hashable, Sendable {
    let windowID: CGWindowID
    let pid: pid_t
    var appName: String
    var title: String
    var bounds: CGRect
    var displayIndex: Int
    var lastFocusedAt: Date

    var id: CGWindowID { windowID }

    var displayLabel: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    init(
        windowID: CGWindowID,
        pid: pid_t,
        appName: String,
        title: String = "",
        bounds: CGRect = .zero,
        displayIndex: Int = 0,
        lastFocusedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.pid = pid
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.displayIndex = displayIndex
        self.lastFocusedAt = lastFocusedAt
    }

    static func == (lhs: FocusWindowRef, rhs: FocusWindowRef) -> Bool {
        lhs.windowID == rhs.windowID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }
}

struct FocusStepResult: Equatable, Sendable {
    let target: FocusWindowRef
    let queue: [FocusWindowRef]
    let selectedIndex: Int
}

/// Pure, deterministic MRU (Most Recently Used) focus queue with session-aware stepping.
///
/// Industry-standard TWM behavior (inspired by AeroSpace `focus-back-and-forth`, i3, Hyprland & OS MRU stacks):
/// - Index 0 is the currently focused window; index 1 is the immediately previous window.
/// - Single back-and-forth (`lastWindowTarget`) ping-pongs between index 0 and index 1, automatically
///   falling back to index 2+ if the previous window was closed.
/// - Rapid queue stepping (`step`) freezes the MRU snapshot during the active navigation window so
///   repeated presses traverse `B -> C -> D -> A` cleanly instead of oscillating between `A` and `B`.
///   Once the session settles (`commitSession`), the landed window is promoted to index 0.
struct FocusQueue: Sendable {
    struct CycleSession: Sendable {
        var snapshot: [FocusWindowRef]
        var cursor: Int
        var lastStepTime: Date
    }

    let maxCapacity: Int
    let sessionTimeout: TimeInterval

    private(set) var entries: [FocusWindowRef] = []
    private(set) var session: CycleSession?

    init(maxCapacity: Int = 64, sessionTimeout: TimeInterval = 1.25) {
        self.maxCapacity = max(4, maxCapacity)
        self.sessionTimeout = max(0.3, sessionTimeout)
    }

    var isCycling: Bool {
        session != nil
    }

    mutating func clear() {
        entries.removeAll()
        session = nil
    }

    /// Records a window gaining focus. When a cycle session is active and the recorded window matches
    /// the session's current target, the frozen snapshot is preserved so stepping can continue cleanly.
    mutating func recordFocus(_ ref: FocusWindowRef, now: Date = Date()) {
        if let active = session {
            if now.timeIntervalSince(active.lastStepTime) < sessionTimeout,
               active.snapshot.indices.contains(active.cursor),
               active.snapshot[active.cursor].windowID == ref.windowID {
                var updated = active
                updated.snapshot[active.cursor] = ref
                session = updated
                updateMetadataIfPresent(ref)
                return
            }
            commitSession()
        }

        promote(ref)
    }

    /// Synchronizes the queue against currently live on-screen windows:
    /// - Removes closed windows
    /// - Refreshes metadata (title, bounds, displayIndex) for tracked windows
    /// - Appends newly discovered windows (preserving their z-order) to the tail of the queue
    mutating func sync(with liveWindows: [FocusWindowRef]) {
        guard !liveWindows.isEmpty else {
            entries.removeAll()
            session = nil
            return
        }

        var liveByID: [CGWindowID: FocusWindowRef] = [:]
        liveByID.reserveCapacity(liveWindows.count)
        for window in liveWindows where liveByID[window.windowID] == nil {
            liveByID[window.windowID] = window
        }

        var updated: [FocusWindowRef] = []
        updated.reserveCapacity(min(maxCapacity, liveWindows.count))
        var seen = Set<CGWindowID>()
        seen.reserveCapacity(liveWindows.count)

        for existing in entries {
            guard var fresh = liveByID[existing.windowID], seen.insert(existing.windowID).inserted else { continue }
            fresh.lastFocusedAt = existing.lastFocusedAt
            updated.append(fresh)
        }

        for window in liveWindows where seen.insert(window.windowID).inserted {
            updated.append(window)
        }

        if updated.count > maxCapacity {
            updated.removeLast(updated.count - maxCapacity)
        }
        entries = updated

        if var active = session {
            let currentTargetID = active.snapshot.indices.contains(active.cursor)
                ? active.snapshot[active.cursor].windowID
                : nil
            let filtered = active.snapshot.compactMap { liveByID[$0.windowID] }
            if filtered.isEmpty {
                session = nil
            } else {
                active.snapshot = filtered
                if let targetID = currentTargetID,
                   let newIndex = filtered.firstIndex(where: { $0.windowID == targetID }) {
                    active.cursor = newIndex
                } else {
                    active.cursor = min(active.cursor, filtered.count - 1)
                }
                session = active
            }
        }
    }

    mutating func remove(windowID: CGWindowID) {
        entries.removeAll { $0.windowID == windowID }
        if var active = session {
            active.snapshot.removeAll { $0.windowID == windowID }
            if active.snapshot.isEmpty {
                session = nil
            } else {
                active.cursor = min(active.cursor, active.snapshot.count - 1)
                session = active
            }
        }
    }

    mutating func remove(pid: pid_t) {
        entries.removeAll { $0.pid == pid }
        if var active = session {
            active.snapshot.removeAll { $0.pid == pid }
            if active.snapshot.isEmpty {
                session = nil
            } else {
                active.cursor = min(active.cursor, active.snapshot.count - 1)
                session = active
            }
        }
    }

    /// Commits the active cycle session's landed window to the front (index 0) of the MRU stack.
    @discardableResult
    mutating func commitSession() -> FocusWindowRef? {
        guard let active = session else { return nil }
        session = nil
        guard active.snapshot.indices.contains(active.cursor) else { return nil }
        let landed = active.snapshot[active.cursor]
        promote(landed)
        return landed
    }

    /// Returns a map of `CGWindowID -> MRU rank` (0 = most recent) for MRU-aware directional tie-breaking.
    func mruRanks() -> [CGWindowID: Int] {
        var ranks: [CGWindowID: Int] = [:]
        ranks.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() where ranks[entry.windowID] == nil {
            ranks[entry.windowID] = index
        }
        return ranks
    }

    /// Returns the ordered live queue filtered by the requested scope.
    func orderedQueue(
        liveWindows: [FocusWindowRef],
        scope: FocusScope,
        currentDisplayIndex: Int?
    ) -> [FocusWindowRef] {
        let scopedLive: [FocusWindowRef]
        if scope == .currentDisplay, let display = currentDisplayIndex {
            let matching = liveWindows.filter { $0.displayIndex == display }
            scopedLive = matching.isEmpty ? liveWindows : matching
        } else {
            scopedLive = liveWindows
        }

        var liveByID: [CGWindowID: FocusWindowRef] = [:]
        liveByID.reserveCapacity(scopedLive.count)
        for window in scopedLive where liveByID[window.windowID] == nil {
            liveByID[window.windowID] = window
        }

        var ordered: [FocusWindowRef] = []
        ordered.reserveCapacity(scopedLive.count)
        var seen = Set<CGWindowID>()
        seen.reserveCapacity(scopedLive.count)

        for entry in entries {
            if let fresh = liveByID[entry.windowID], seen.insert(entry.windowID).inserted {
                ordered.append(fresh)
            }
        }
        for window in scopedLive where seen.insert(window.windowID).inserted {
            ordered.append(window)
        }
        return ordered
    }

    /// Instant back-and-forth toggle (AeroSpace / i3 style with automatic dead-window fallback):
    /// Promotes the current window first (if known), then selects the most recent live window != current,
    /// and promotes the selected target to index 0 so a second press returns cleanly to the original window.
    mutating func switchToLastWindow(
        currentID: CGWindowID?,
        liveWindows: [FocusWindowRef],
        scope: FocusScope,
        currentDisplayIndex: Int?,
        now: Date = Date()
    ) -> FocusStepResult? {
        commitSession()
        sync(with: liveWindows)

        if let currentID, let currentRef = liveWindows.first(where: { $0.windowID == currentID }) {
            promote(currentRef)
        }

        let ordered = orderedQueue(liveWindows: liveWindows, scope: scope, currentDisplayIndex: currentDisplayIndex)
        guard ordered.count >= 2 else { return nil }

        let target: FocusWindowRef
        if let currentID, let candidate = ordered.first(where: { $0.windowID != currentID }) {
            target = candidate
        } else {
            target = ordered[1]
        }

        var promotedTarget = target
        promotedTarget.lastFocusedAt = now
        promote(promotedTarget)

        let updatedQueue = orderedQueue(liveWindows: liveWindows, scope: scope, currentDisplayIndex: currentDisplayIndex)
        let selectedIndex = updatedQueue.firstIndex(where: { $0.windowID == target.windowID }) ?? 0
        return FocusStepResult(target: promotedTarget, queue: updatedQueue, selectedIndex: selectedIndex)
    }

    /// Session-aware queue stepping (`direction`: `+1` for next / more-recently-used -> older, `-1` for previous).
    /// First press (`+1`) lands on index 1 (the last window); subsequent presses within `sessionTimeout`
    /// traverse the frozen queue without oscillating.
    mutating func step(
        direction: Int,
        currentID: CGWindowID?,
        liveWindows: [FocusWindowRef],
        scope: FocusScope,
        currentDisplayIndex: Int?,
        now: Date = Date()
    ) -> FocusStepResult? {
        guard direction != 0 else { return nil }

        // Expire stale session if timed out
        if let active = session, now.timeIntervalSince(active.lastStepTime) >= sessionTimeout {
            commitSession()
        }

        sync(with: liveWindows)

        if var active = session, active.snapshot.count >= 2 {
            let count = active.snapshot.count
            let nextCursor = ((active.cursor + direction) % count + count) % count
            active.cursor = nextCursor
            active.lastStepTime = now
            session = active
            let target = active.snapshot[nextCursor]
            return FocusStepResult(target: target, queue: active.snapshot, selectedIndex: nextCursor)
        }

        // Start a fresh cycle session from current MRU order
        if let currentID, let currentRef = liveWindows.first(where: { $0.windowID == currentID }) {
            promote(currentRef)
        }

        let ordered = orderedQueue(liveWindows: liveWindows, scope: scope, currentDisplayIndex: currentDisplayIndex)
        guard ordered.count >= 2 else { return nil }

        let startIndex = currentID.flatMap { id in ordered.firstIndex(where: { $0.windowID == id }) } ?? 0
        let count = ordered.count
        let nextCursor = ((startIndex + direction) % count + count) % count

        session = CycleSession(snapshot: ordered, cursor: nextCursor, lastStepTime: now)
        let target = ordered[nextCursor]
        return FocusStepResult(target: target, queue: ordered, selectedIndex: nextCursor)
    }

    private mutating func promote(_ ref: FocusWindowRef) {
        entries.removeAll { $0.windowID == ref.windowID }
        entries.insert(ref, at: 0)
        if entries.count > maxCapacity {
            entries.removeLast(entries.count - maxCapacity)
        }
    }

    private mutating func updateMetadataIfPresent(_ ref: FocusWindowRef) {
        guard let index = entries.firstIndex(where: { $0.windowID == ref.windowID }) else { return }
        var existing = entries[index]
        existing.appName = ref.appName
        existing.title = ref.title
        existing.bounds = ref.bounds
        existing.displayIndex = ref.displayIndex
        entries[index] = existing
    }
}
