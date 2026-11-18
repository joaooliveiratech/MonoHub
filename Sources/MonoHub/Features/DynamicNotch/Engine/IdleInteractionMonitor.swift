import AppKit
import CoreGraphics
import Foundation
import Observation

nonisolated struct IdleInteractionSnapshot: Equatable, Sendable {

    let phase: Double

    let ambientTime: Double

    let energy: Double

    let typingEnergy: Double

    let strokeCount: Int

    let isTypingNow: Bool

    let isActiveNow: Bool

    let isVisible: Bool
}

@Observable
@MainActor
final class IdleInteractionMonitor {
    static let shared = IdleInteractionMonitor()

    private(set) var isInteracting: Bool = false
    private(set) var tickDate: Date = Date()

    @ObservationIgnored private(set) var strokeCount: Int = 0
    @ObservationIgnored private(set) var energy: Double = 0.0
    @ObservationIgnored private(set) var typingEnergy: Double = 0.0

    @ObservationIgnored private let startTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    @ObservationIgnored private var lastTickTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    @ObservationIgnored private var lastKeyBoostTimestamp: TimeInterval = 0
    @ObservationIgnored private var lastAnyBoostTimestamp: TimeInterval = 0

    @ObservationIgnored private var continuousPhase: Double = 0.0
    @ObservationIgnored private var interactivePhase: Double = 0.0

    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMouseMonitor: Any?
    @ObservationIgnored private var globalMouseMonitor: Any?
    @ObservationIgnored private var idleTimer: Timer?
    @ObservationIgnored private var renderTimer: Timer?
    @ObservationIgnored private var currentRenderInterval: TimeInterval = 0
    @ObservationIgnored private var activeViewCount: Int = 0
    @ObservationIgnored private var burstTask: Task<Void, Never>?
    @ObservationIgnored private var isMonitoring = false

    private static let sleepAfterIdle: TimeInterval = 1.2

    private init() {}

    func ensureStarted() {
        guard !isMonitoring, !AppInfo.isRunningTests else { return }
        guard NotchPreferences.shared.idleAnimation != .none else { return }
        guard !NotchWindowController.shared.isDisplayAsleep, !AppExclusionManager.shared.isSuppressed else { return }
        isMonitoring = true
        lastTickTimestamp = Date().timeIntervalSinceReferenceDate

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.recordKeyFromMonitor()
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recordKeyFromMonitor()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    IdleInteractionMonitor.shared.recordMouseFromMonitor()
                }
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recordMouseFromMonitor()
            }
        }
        syncRenderTimer()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        burstTask?.cancel()
        burstTask = nil
        cancelIdleTimer()
        stopRenderTimer()
        for monitor in [localMonitor, globalMonitor, localMouseMonitor, globalMouseMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        localMonitor = nil
        globalMonitor = nil
        localMouseMonitor = nil
        globalMouseMonitor = nil
        energy = 0
        typingEnergy = 0
        if isInteracting { isInteracting = false }
    }

    func registerActiveView() {
        activeViewCount += 1
        syncRenderTimer()
    }

    func unregisterActiveView() {
        activeViewCount = max(0, activeViewCount - 1)
        syncRenderTimer()
    }

    func syncRenderTimer() {
        guard isMonitoring,
              !AppInfo.isRunningTests,
              activeViewCount > 0,
              NotchPreferences.shared.idleAnimation != .none,
              !NotchWindowController.shared.isDisplayAsleep,
              !AppExclusionManager.shared.isSuppressed,
              !NotchWindowController.shared.isExpanded else {
            stopRenderTimer()
            return
        }
        let mode = NotchPreferences.shared.idleInteractionMode
        guard mode == .alwaysActive || isInteracting else {
            stopRenderTimer()
            return
        }
        let desiredInterval: TimeInterval = isInteracting ? 0.125 : 0.25
        if let timer = renderTimer, timer.isValid, abs(currentRenderInterval - desiredInterval) < 0.001 {
            return
        }
        stopRenderTimer()
        currentRenderInterval = desiredInterval
        let timer = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tickDate = Date()
            }
        }
        timer.tolerance = desiredInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func stopRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
        currentRenderInterval = 0
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func scheduleIdleSleep() {
        guard isMonitoring, !AppInfo.isRunningTests else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = max(0.0, now - lastAnyBoostTimestamp)
        let remaining = max(0.1, Self.sleepAfterIdle - elapsed)
        let targetDate = Date(timeIntervalSinceNow: remaining)
        if let timer = idleTimer, timer.isValid {
            timer.fireDate = targetDate
            return
        }
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkIdleSleep()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func checkIdleSleep() {
        idleTimer = nil
        guard isMonitoring else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = max(0.0, now - lastAnyBoostTimestamp)
        if elapsed < Self.sleepAfterIdle {
            scheduleIdleSleep()
            return
        }
        advancePhases(to: now)
        energy = 0
        typingEnergy = 0
        if isInteracting {
            isInteracting = false
            tickDate = Date()
            syncRenderTimer()
        }
    }

    private func recordKeyFromMonitor() {
        guard !NotchWindowController.shared.isDisplayAsleep, !AppExclusionManager.shared.isSuppressed else { return }
        let now = Date().timeIntervalSinceReferenceDate
        advancePhases(to: now)
        if now - lastKeyBoostTimestamp > 0.025 {
            strokeCount &+= 1
            lastKeyBoostTimestamp = now
        }
        typingEnergy = min(1.0, max(typingEnergy + 0.45, 0.85))
        energy = min(1.0, max(energy + 0.45, 0.85))
        lastAnyBoostTimestamp = now
        if !isInteracting {
            isInteracting = true
            tickDate = Date()
            syncRenderTimer()
        }
        scheduleIdleSleep()
    }

    private func recordMouseFromMonitor() {
        guard !NotchWindowController.shared.isDisplayAsleep, !AppExclusionManager.shared.isSuppressed else { return }
        let now = Date().timeIntervalSinceReferenceDate
        advancePhases(to: now)
        energy = min(1.0, max(energy + 0.28, 0.62))
        lastAnyBoostTimestamp = now
        if !isInteracting {
            isInteracting = true
            tickDate = Date()
            syncRenderTimer()
        }
        scheduleIdleSleep()
    }

    func recordEvent(isKey: Bool = true) {
        let now = Date().timeIntervalSinceReferenceDate
        advancePhases(to: now)

        if isKey {
            strokeCount &+= 1
            lastKeyBoostTimestamp = now
            typingEnergy = min(1.0, max(typingEnergy + 0.48, 0.88))
            energy = min(1.0, max(energy + 0.48, 0.88))
            lastAnyBoostTimestamp = now
        } else {
            energy = min(1.0, max(energy + 0.30, 0.65))
            lastAnyBoostTimestamp = now
        }

        if !isInteracting {
            isInteracting = true
            tickDate = Date()
            syncRenderTimer()
        }
        scheduleIdleSleep()
    }

    func simulateTypingBurst(strokes: Int = 8) {
        ensureStarted()
        burstTask?.cancel()
        recordEvent(isKey: true)
        guard strokes > 1 else { return }
        burstTask = Task { @MainActor [weak self] in
            for _ in 1..<strokes {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self else { return }
                self.recordEvent(isKey: true)
            }
        }
    }

    private func advancePhases(to now: TimeInterval) {
        let rawDt = max(0.0, now - lastTickTimestamp)
        guard rawDt > 0 else { return }
        let interactiveDt = min(30.0, rawDt)
        lastTickTimestamp = now

        let speed = max(0.4, min(2.5, NotchPreferences.shared.idleAnimationSpeed))
        let curEnergy = decayedEnergy(at: now)

        continuousPhase += rawDt * speed
        let interactiveRate = curEnergy > 0.08 ? (0.55 + curEnergy * 0.55) : 0.16
        interactivePhase += interactiveDt * speed * interactiveRate
    }

    private func decayedEnergy(at now: TimeInterval) -> Double {
        let elapsed = max(0.0, now - lastAnyBoostTimestamp)
        if elapsed < 0.28 {
            return energy
        } else if elapsed < 1.15 {
            let factor = 1.0 - ((elapsed - 0.28) / 0.87)
            return max(0.0, energy * max(0.0, factor))
        } else {
            return 0.0
        }
    }

    private func decayedTypingEnergy(at now: TimeInterval) -> Double {
        let elapsed = max(0.0, now - lastKeyBoostTimestamp)
        if elapsed < 0.24 {
            return typingEnergy
        } else if elapsed < 0.65 {
            let factor = 1.0 - ((elapsed - 0.24) / 0.41)
            return max(0.0, typingEnergy * max(0.0, factor))
        } else {
            return 0.0
        }
    }

    func snapshot(
        at date: Date,
        mode: NotchIdleInteractionMode,
        speedMultiplier: Double = 1.0
    ) -> IdleInteractionSnapshot {
        let now = date.timeIntervalSinceReferenceDate
        let ambient = max(0.0, now - startTimestamp)
        let rawExtraDt = max(0.0, now - lastTickTimestamp)
        let speed = max(0.4, min(2.5, speedMultiplier))

        if mode == .alwaysActive {
            let phase = continuousPhase + rawExtraDt * speed
            let syntheticStrokes = Int(phase * 5.5)
            return IdleInteractionSnapshot(
                phase: phase,
                ambientTime: ambient,
                energy: 1.0,
                typingEnergy: 1.0,
                strokeCount: syntheticStrokes,
                isTypingNow: true,
                isActiveNow: true,
                isVisible: true
            )
        }

        let curEnergy = decayedEnergy(at: now)
        let curTyping = decayedTypingEnergy(at: now)
        let interactiveRate = curEnergy > 0.08 ? (0.55 + curEnergy * 0.55) : 0.16
        let extraDt = min(30.0, rawExtraDt)
        let phase = interactivePhase + extraDt * speed * interactiveRate
        let typingNow = curTyping > 0.12
        let activeNow = curEnergy > 0.10 || typingNow
        let visible = (mode == .onlyWhenTyping) ? (curEnergy > 0.04 || curTyping > 0.04) : true

        return IdleInteractionSnapshot(
            phase: phase,
            ambientTime: ambient,
            energy: curEnergy,
            typingEnergy: curTyping,
            strokeCount: strokeCount,
            isTypingNow: typingNow,
            isActiveNow: activeNow,
            isVisible: visible
        )
    }
}
