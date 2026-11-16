import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TimerManager {
    static let shared = TimerManager()

    var model = TimerModel()
    var laps: [TimeInterval] = []

    private(set) var completionCount: Int = 0

    private(set) var isCompleted: Bool = false
    private(set) var lastCompletedPhase: PomodoroPhase? = nil

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var anchorDate: Date?
    @ObservationIgnored private var anchorRemaining: TimeInterval = 0
    @ObservationIgnored private var anchorElapsed: TimeInterval = 0
    @ObservationIgnored private var completionResetTask: Task<Void, Never>?

    private init() {
        let defaultSeconds: TimeInterval = PomodoroPhase.focus.defaultDuration
        model.mode = .pomodoro
        model.pomodoroPhase = .focus
        model.targetDuration = defaultSeconds
        model.remainingSeconds = defaultSeconds
    }

    var isTicking: Bool { ticker != nil }

    func setPreset(_ duration: TimeInterval) {
        isCompleted = false
        completionResetTask?.cancel()
        stop()
        model.targetDuration = duration
        model.remainingSeconds = duration
        model.elapsedTime = 0
        model.mode = .countdown
        laps.removeAll()
        start()
    }

    func setPomodoroPhase(_ phase: PomodoroPhase, autoStart: Bool = false) {
        isCompleted = false
        completionResetTask?.cancel()
        stop()
        model.mode = .pomodoro
        model.pomodoroPhase = phase
        model.targetDuration = phase.defaultDuration
        model.remainingSeconds = phase.defaultDuration
        model.elapsedTime = 0
        laps.removeAll()
        if autoStart {
            start()
        }
    }

    func advancePomodoroCycle() {
        model.completedPomodoros += 1
        let nextPhase: PomodoroPhase = (model.completedPomodoros % 4 == 0) ? .longBreak : .shortBreak
        setPomodoroPhase(nextPhase, autoStart: false)
    }

    func setMode(_ mode: TimerMode) {
        guard mode != model.mode else { return }
        isCompleted = false
        completionResetTask?.cancel()
        pause()
        model.mode = mode
        if mode == .pomodoro {
            model.targetDuration = model.pomodoroPhase.defaultDuration
        } else if mode == .countdown {
            let defaultSec = TimeInterval(max(1, NotchPreferences.shared.timerDefaultMinutes) * 60)
            model.targetDuration = defaultSec
        }
        model.remainingSeconds = model.targetDuration
        model.elapsedTime = 0
        laps.removeAll()
    }

    func addSeconds(_ seconds: TimeInterval) {
        guard model.mode != .stopwatch else { return }
        model.remainingSeconds = max(0, model.remainingSeconds + seconds)
        model.targetDuration = max(model.remainingSeconds, model.targetDuration + seconds)
        if model.isRunning {
            if model.remainingSeconds <= 0 {
                complete()
            } else {
                rebaseAnchor()
            }
        }
    }

    func toggleStartPause() {
        if model.isRunning {
            pause()
        } else {
            start()
        }
    }

    func start() {
        isCompleted = false
        completionResetTask?.cancel()
        guard !model.isRunning || ticker == nil else { return }
        if model.mode != .stopwatch && model.remainingSeconds <= 0 {
            model.remainingSeconds = model.targetDuration
        }
        model.isRunning = true
        rebaseAnchor()
        syncFocus()
    }

    func pause() {
        if model.isRunning, anchorDate != nil {
            tick()
        }
        stopTicker()
        if model.isRunning {
            model.isRunning = false
        }
        syncFocus()
    }

    func reset() {
        isCompleted = false
        completionResetTask?.cancel()
        pause()
        model.remainingSeconds = model.targetDuration
        model.elapsedTime = 0
        laps.removeAll()
    }

    func recordLap() {
        guard model.mode == .stopwatch && model.isRunning else { return }
        laps.insert(model.elapsedTime, at: 0)
    }

    func stop() {
        pause()
    }

    private func syncFocus() {
        let active = model.isRunning && model.mode == .pomodoro && model.pomodoroPhase == .focus
        FocusController.shared.setActive(active)
    }

    private func rebaseAnchor() {
        stopTicker()
        let now = Date()
        anchorDate = now
        anchorRemaining = model.remainingSeconds
        anchorElapsed = model.elapsedTime
        let timer = Timer(fire: now.addingTimeInterval(1), interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        anchorDate = nil
    }

    private func tick() {
        guard let anchorDate else { return }
        let passed = floor(max(0, Date().timeIntervalSince(anchorDate)) + 0.05)
        switch model.mode {
        case .countdown, .pomodoro:
            let remaining = max(0, anchorRemaining - passed)
            if remaining != model.remainingSeconds {
                model.remainingSeconds = remaining
            }
            if remaining <= 0 {
                complete()
            }
        case .stopwatch:
            let elapsed = anchorElapsed + passed
            if elapsed != model.elapsedTime {
                model.elapsedTime = elapsed
            }
        }
    }

    private func complete() {
        stopTicker()
        model.isRunning = false
        let finishedPhase = (model.mode == .pomodoro) ? model.pomodoroPhase : nil
        self.lastCompletedPhase = finishedPhase
        self.isCompleted = true

        if model.mode == .pomodoro {
            if model.pomodoroPhase == .focus {
                model.completedPomodoros += 1
                let nextPhase: PomodoroPhase = (model.completedPomodoros % 4 == 0) ? .longBreak : .shortBreak
                model.pomodoroPhase = nextPhase
                model.targetDuration = nextPhase.defaultDuration
                model.remainingSeconds = nextPhase.defaultDuration
            } else {
                model.pomodoroPhase = .focus
                model.targetDuration = PomodoroPhase.focus.defaultDuration
                model.remainingSeconds = PomodoroPhase.focus.defaultDuration
            }
        } else {
            model.remainingSeconds = model.targetDuration
        }
        syncFocus()
        completionCount += 1
        if NotchPreferences.shared.timerPlayCompletionSound && !AppInfo.isRunningTests {
            if let sound = NSSound(named: "Glass") ?? NSSound(named: "Hero") ?? NSSound(named: "Ping") {
                sound.volume = 1.0
                sound.play()
            } else {
                NSSound.beep()
            }
        }
        NotchHaptics.success()
        LiveActivityCenter.shared.timerDidComplete()

        completionResetTask?.cancel()
        completionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.isCompleted = false
        }
    }
}
