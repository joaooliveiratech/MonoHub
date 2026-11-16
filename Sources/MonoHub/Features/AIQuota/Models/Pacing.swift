import Foundation

nonisolated enum PaceState: String, Sendable, Equatable {
    case ahead
    case onTrack
    case under

    var glyph: String {
        switch self {
        case .ahead: "↑"
        case .onTrack: "→"
        case .under: "↓"
        }
    }
}

nonisolated struct WindowPacing: Sendable, Equatable {
    let elapsedPercent: Double
    let delta: Double
    let pace: PaceState
    let paceLabel: String
    let paceNote: String?

    static func calculate(
        usedPercent: Double,
        resetsAt: Date?,
        limitWindowSeconds: Int64?,
        now: Date = Date(),
        tolerance: Double = 5.0
    ) -> WindowPacing? {
        guard let resetsAt, resetsAt > now else { return nil }

        let remainingSeconds = resetsAt.timeIntervalSince(now)
        let totalSeconds: Double
        if let limitWindowSeconds, limitWindowSeconds > 0 {
            totalSeconds = Double(limitWindowSeconds)
        } else if remainingSeconds <= 5.5 * 3600 {
            totalSeconds = 5.0 * 3600
        } else if remainingSeconds <= 7.5 * 86400 {
            totalSeconds = 7.0 * 86400
        } else {
            totalSeconds = 30.0 * 86400
        }

        let elapsedSeconds = max(0, totalSeconds - remainingSeconds)
        let elapsedPercent = min(max((elapsedSeconds / totalSeconds) * 100.0, 0.0), 100.0)
        let delta = usedPercent - elapsedPercent

        let pace: PaceState
        let paceLabel: String
        if delta > tolerance {
            pace = .ahead
            paceLabel = "+\(Int(delta.rounded()))% ahead"
        } else if delta < -tolerance {
            pace = .under
            paceLabel = "\(Int(delta.rounded()))% under"
        } else {
            pace = .onTrack
            paceLabel = "on track"
        }

        var paceNote: String?
        if usedPercent >= 100.0 {
            paceNote = "Limit reached"
        } else if elapsedSeconds >= 180.0, usedPercent > 0.0 {
            let burnRate = usedPercent / elapsedSeconds
            let projectedAtReset = usedPercent + (burnRate * remainingSeconds)

            if projectedAtReset > 100.0 {
                let remainingQuota = 100.0 - usedPercent
                let secondsToLimit = remainingQuota / burnRate
                paceNote = "Limit in \(formatDuration(secondsToLimit))"
            } else {
                let leftAtReset = max(0, 100.0 - projectedAtReset)
                paceNote = "~\(Int(leftAtReset.rounded()))% left at reset"
            }
        }

        return WindowPacing(
            elapsedPercent: elapsedPercent,
            delta: delta,
            pace: pace,
            paceLabel: paceLabel,
            paceNote: paceNote
        )
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = max(1, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
