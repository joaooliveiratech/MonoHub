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

    @ObservationIgnored private(set) var strokeCount: Int = 0
    @ObservationIgnored private(set) var energy: Double = 0.0
    @ObservationIgnored private(set) var typingEnergy: Double = 0.0

    @ObservationIgnored private let startTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    @ObservationIgnored private var lastTickTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    @ObservationIgnored private var lastKeyBoostTimestamp: TimeInterval = 0
    @ObservationIgnored private var lastAnyBoostTimestamp: TimeInterval = 0
    @ObservationIgnored private var lastKeyIdleSeconds: CFTimeInterval = 999
    @ObservationIgnored private var lastClickIdleSeconds: CFTimeInterval = 999

    @ObservationIgnored private var continuousPhase: Double = 0.0
    @ObservationIgnored private var interactivePhase: Double = 0.0

    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMouseMonitor: Any?
    @ObservationIgnored private var globalMouseMonitor: Any?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var burstTask: Task<Void, Never>?
    @ObservationIgnored private var isMonitoring = false

    private static let sleepAfterIdle: TimeInterval = 1.3

    private init() {}

    func ensureStarted() {
        guard !isMonitoring, !AppInfo.isRunningTests else { return }
        guard NotchPreferences.shared.idleAnimation != .none else { return }
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
                    IdleInteractionMonitor.shared.wake()
                }
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.wake()
            }
        }
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        burstTask?.cancel()
        burstTask = nil
        sleepTimer()
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

    private func wake() {
        guard isMonitoring, pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func sleepTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func recordKeyFromMonitor() {
        let now = Date().timeIntervalSinceReferenceDate
        advancePhases(to: now)
        if now - lastKeyBoostTimestamp > 0.025 {
            strokeCount &+= 1
            lastKeyBoostTimestamp = now
        }
        typingEnergy = min(1.0, max(typingEnergy + 0.45, 0.85))
        energy = min(1.0, max(energy + 0.45, 0.85))
        lastAnyBoostTimestamp = now
        wake()
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

        wake()

        if AppInfo.isRunningTests {
            isInteracting = true
        }
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

    private func tick() {
        let prefs = NotchPreferences.shared
        guard prefs.idleAnimation != .none else {
            if isInteracting { isInteracting = false }
            return
        }

        let now = Date().timeIntervalSinceReferenceDate

        if !AppInfo.isRunningTests && prefs.idleInteractionMode != .alwaysActive {
            let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            let leftClickIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
            let rightClickIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
            let clickIdle = min(leftClickIdle, rightClickIdle)

            let isFreshKey = keyIdle < 0.095 && (keyIdle + 0.006 < lastKeyIdleSeconds || keyIdle < 0.025)
            if isFreshKey {
                if now - lastKeyBoostTimestamp > 0.032 {
                    strokeCount &+= 1
                    lastKeyBoostTimestamp = now
                }
                typingEnergy = min(1.0, max(typingEnergy + 0.42, 0.82))
                energy = min(1.0, max(energy + 0.42, 0.82))
                lastAnyBoostTimestamp = now
            } else if clickIdle < 0.095 && clickIdle + 0.006 < lastClickIdleSeconds {
                energy = min(1.0, max(energy + 0.28, 0.62))
                lastAnyBoostTimestamp = now
            }

            lastKeyIdleSeconds = keyIdle
            lastClickIdleSeconds = clickIdle
        }

        advancePhases(to: now)

        let curEnergy = decayedEnergy(at: now)
        let curTyping = decayedTypingEnergy(at: now)
        energy = curEnergy
        typingEnergy = curTyping

        let activeNow = curEnergy > 0.08 || curTyping > 0.08
        if isInteracting != activeNow {
            isInteracting = activeNow
        }

        if !activeNow && (now - lastAnyBoostTimestamp >= Self.sleepAfterIdle) && prefs.idleInteractionMode != .alwaysActive {
            sleepTimer()
        }
    }

    private func advancePhases(to now: TimeInterval) {
        let dt = min(0.25, max(0.0, now - lastTickTimestamp))
        guard dt > 0 else { return }
        lastTickTimestamp = now

        let speed = max(0.4, min(2.5, NotchPreferences.shared.idleAnimationSpeed))
        let curEnergy = decayedEnergy(at: now)

        continuousPhase += dt * speed
        let interactiveRate = curEnergy > 0.08 ? (0.55 + curEnergy * 0.55) : 0.16
        interactivePhase += dt * speed * interactiveRate
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
        let extraDt = min(0.15, max(0.0, now - lastTickTimestamp))
        let speed = max(0.4, min(2.5, speedMultiplier))

        if mode == .alwaysActive {
            let phase = continuousPhase + extraDt * speed
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
