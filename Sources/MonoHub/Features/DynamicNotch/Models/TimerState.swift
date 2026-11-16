import Foundation

enum PomodoroPhase: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus = "Foco"
    case shortBreak = "Pausa Curta"
    case longBreak = "Pausa Longa"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return localized("Focus")
        case .shortBreak: return localized("Short Break")
        case .longBreak: return localized("Long Break")
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .focus: return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 15 * 60
        }
    }

    var icon: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "leaf.fill"
        }
    }

    var emoji: String {
        switch self {
        case .focus: return "🍅"
        case .shortBreak: return "☕️"
        case .longBreak: return "🌴"
        }
    }
}

enum TimerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case pomodoro = "Pomodoro"
    case countdown = "Timer"
    case stopwatch = "Stopwatch"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pomodoro: return localized("Pomodoro")
        case .countdown: return localized("Timer")
        case .stopwatch: return localized("Stopwatch")
        }
    }

    var icon: String {
        switch self {
        case .pomodoro: return "brain.head.profile"
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch"
        }
    }
}

nonisolated struct TimerPreset: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let durationInSeconds: TimeInterval

    init(label: String, durationInSeconds: TimeInterval) {
        self.label = label
        self.durationInSeconds = durationInSeconds
    }

    static let standardPresets: [TimerPreset] = [
        TimerPreset(label: "1m", durationInSeconds: 60),
        TimerPreset(label: "5m", durationInSeconds: 300),
        TimerPreset(label: "15m", durationInSeconds: 900),
        TimerPreset(label: "25m", durationInSeconds: 1500),
        TimerPreset(label: "45m", durationInSeconds: 2700),
        TimerPreset(label: "1h", durationInSeconds: 3600)
    ]
}

nonisolated struct TimerModel: Sendable, Equatable {
    var mode: TimerMode
    var targetDuration: TimeInterval
    var remainingSeconds: TimeInterval
    var elapsedTime: TimeInterval
    var isRunning: Bool
    var pomodoroPhase: PomodoroPhase
    var completedPomodoros: Int

    init(
        mode: TimerMode = .pomodoro,
        targetDuration: TimeInterval = 1500,
        remainingSeconds: TimeInterval = 1500,
        elapsedTime: TimeInterval = 0,
        isRunning: Bool = false,
        pomodoroPhase: PomodoroPhase = .focus,
        completedPomodoros: Int = 0
    ) {
        self.mode = mode
        self.targetDuration = targetDuration
        self.remainingSeconds = remainingSeconds
        self.elapsedTime = elapsedTime
        self.isRunning = isRunning
        self.pomodoroPhase = pomodoroPhase
        self.completedPomodoros = completedPomodoros
    }

    var progress: Double {
        guard targetDuration > 0 else { return 0 }
        let elapsed = max(0, targetDuration - remainingSeconds)
        return min(max(elapsed / targetDuration, 0), 1)
    }

    var formattedDisplay: String {
        let displaySeconds = mode != .stopwatch ? remainingSeconds : elapsedTime
        let total = Int(max(0, displaySeconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
