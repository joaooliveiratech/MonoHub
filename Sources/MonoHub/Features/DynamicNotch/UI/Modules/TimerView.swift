import SwiftUI

struct TimerView: View {
    private let timerManager = TimerManager.shared
    @State private var pulseCircle = false

    init() {}

    var body: some View {
        HStack(spacing: 22) {
            progressRingView
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    NotchSegmentedControl(
                        options: [
                            .init(id: TimerMode.pomodoro, title: TimerMode.pomodoro.title, icon: "brain.head.profile", tint: .orange),
                            .init(id: TimerMode.countdown, title: TimerMode.countdown.title, icon: "timer", tint: .orange),
                            .init(id: TimerMode.stopwatch, title: TimerMode.stopwatch.title, icon: "stopwatch", tint: .mint)
                        ],
                        selection: Binding(
                            get: { timerManager.model.mode },
                            set: { timerManager.setMode($0) }
                        )
                    )

                    Spacer()

                    if timerManager.model.mode != .stopwatch {
                        HStack(spacing: 5) {
                            ForEach([(-60.0, "-1m"), (60.0, "+1m"), (300.0, "+5m")], id: \.1) { delta, title in
                                Button {
                                    NotchHaptics.tap()
                                    timerManager.addSeconds(delta)
                                } label: {
                                    Text(title)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                                .buttonStyle(NotchSecondaryButtonStyle())
                            }
                        }
                    }
                }

                if timerManager.model.mode == .pomodoro {
                    pomodoroControlsView
                } else if timerManager.model.mode == .countdown {
                    countdownControlsView
                } else {
                    stopwatchControlsView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .notchModule()
    }

    private var progressRingView: some View {
        let mode = timerManager.model.mode
        let isCountdown = mode != .stopwatch
        let accent: Color = {
            switch mode {
            case .pomodoro:
                switch timerManager.model.pomodoroPhase {
                case .focus: return .orange
                case .shortBreak: return .yellow
                case .longBreak: return .mint
                }
            case .countdown:
                return .orange
            case .stopwatch:
                return .mint
            }
        }()

        let ringGradient: LinearGradient = {
            switch mode {
            case .pomodoro:
                switch timerManager.model.pomodoroPhase {
                case .focus:
                    return LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                case .shortBreak:
                    return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                case .longBreak:
                    return LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            case .countdown:
                return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .stopwatch:
                return LinearGradient(colors: [.mint, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }()

        let subtitleText: String = {
            if mode == .pomodoro {
                return timerManager.model.isRunning ? timerManager.model.pomodoroPhase.title.uppercased() : localized("PAUSED")
            } else if mode == .countdown {
                return timerManager.model.isRunning ? localized("COUNTDOWN") : localized("PAUSED")
            } else {
                return timerManager.model.isRunning ? localized("ACTIVE") : localized("STOPWATCH")
            }
        }()

        return ZStack {
            if timerManager.isCompleted {
                Circle()
                    .stroke(accent.opacity(0.85), lineWidth: 3)
                    .frame(width: 104, height: 104)
                    .scaleEffect(pulseCircle ? 1.26 : 0.96)
                    .opacity(pulseCircle ? 0.0 : 0.9)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulseCircle)
                    .onAppear { pulseCircle = true }
                    .onDisappear { pulseCircle = false }
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(timerManager.isCompleted ? 0.25 : (timerManager.model.isRunning ? 0.14 : 0.05)), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 54
                    )
                )
                .frame(width: 104, height: 104)

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 7)
                .frame(width: 104, height: 104)

            Circle()
                .trim(from: 0, to: CGFloat(isCountdown ? (1.0 - timerManager.model.progress) : TimerGlyph.ringProgress(for: timerManager.model)))
                .stroke(ringGradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(timerManager.isCompleted ? 0.6 : 0.35), radius: timerManager.isCompleted ? 10 : 6)
                .animation(.linear(duration: 0.9), value: timerManager.model.remainingSeconds)
                .animation(.linear(duration: 0.9), value: timerManager.model.elapsedTime)

            if timerManager.isCompleted {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(accent)
                        .symbolEffect(.bounce, options: .repeat(2))

                    Text(mode == .pomodoro ? (timerManager.lastCompletedPhase == .focus ? localized("FOCUS COMPLETED!") : localized("BREAK COMPLETED!")) : localized("COMPLETED!"))
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 2) {
                    Text(timerManager.model.formattedDisplay)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: isCountdown))
                        .animation(.snappy(duration: 0.25), value: timerManager.model.formattedDisplay)

                    Text(subtitleText)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(timerManager.model.isRunning ? accent : .white.opacity(0.45))
                }
            }
        }
    }

    private var pomodoroControlsView: some View {
        VStack(alignment: .leading, spacing: 9) {

            HStack(spacing: 6) {
                ForEach(PomodoroPhase.allCases) { phase in
                    let isSelected = timerManager.model.pomodoroPhase == phase
                    Button {
                        NotchHaptics.tap()
                        timerManager.setPomodoroPhase(phase)
                    } label: {
                        HStack(spacing: 4) {
                            Text(phase.emoji)
                                .font(.system(size: 10))
                            Text(phase.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    .buttonStyle(NotchSecondaryButtonStyle(
                        isSelected: isSelected,
                        selectedTint: phase == .focus ? .orange : (phase == .shortBreak ? .yellow : .mint)
                    ))
                }
            }

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    timerManager.toggleStartPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timerManager.model.isRunning ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(timerManager.model.isRunning ? localized("Pause") : (timerManager.model.pomodoroPhase == .focus ? localized("Start Focus") : localized("Start Break")))
                    }
                }
                .buttonStyle(NotchPrimaryButtonStyle(
                    tint: timerManager.model.isRunning ? .orange : .white,
                    foreground: .black
                ))

                Button {
                    NotchHaptics.tap()
                    timerManager.reset()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(localized("Reset"))
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Text(localized("Cycle:"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.tertiaryText)

                    let count = timerManager.model.completedPomodoros
                    let activeInCycle = count == 0 ? 0 : ((count - 1) % 4 + 1)

                    HStack(spacing: 4) {
                        ForEach(1...4, id: \.self) { step in
                            let isDone = (count > 0 && (step <= activeInCycle || count % 4 == 0))
                            Circle()
                                .fill(isDone ? Color.orange : Color.white.opacity(0.18))
                                .frame(width: 12, height: 12)
                                .overlay {
                                    if isDone {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 6, weight: .heavy))
                                            .foregroundStyle(.black)
                                    } else {
                                        Text("\(step)")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                    }
                                }
                                .shadow(color: isDone ? Color.orange.opacity(0.4) : .clear, radius: 2)
                        }
                    }

                    if count > 0 {
                        Text("(\(count))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }

                    Button {
                        NotchHaptics.tap()
                        timerManager.advancePomodoroCycle()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help(localized("Complete pomodoro and advance cycle"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
    }

    private var countdownControlsView: some View {
        VStack(alignment: .leading, spacing: 10) {

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([
                        (60.0, "1m"),
                        (300.0, "5m"),
                        (600.0, "10m"),
                        (900.0, "15m"),
                        (1500.0, "25m 🍅"),
                        (1800.0, "30m"),
                        (3600.0, "1h")
                    ], id: \.0) { sec, label in
                        let isSelected = timerManager.model.targetDuration == sec
                        Button {
                            NotchHaptics.tap()
                            timerManager.setPreset(sec)
                        } label: {
                            Text(label)
                        }
                        .buttonStyle(NotchSecondaryButtonStyle(isSelected: isSelected, selectedTint: .orange))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    timerManager.toggleStartPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timerManager.model.isRunning ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(timerManager.model.isRunning ? localized("Pause") : localized("Start"))
                    }
                }
                .buttonStyle(NotchPrimaryButtonStyle(tint: timerManager.model.isRunning ? .orange : .white, foreground: .black))

                Button {
                    NotchHaptics.tap()
                    timerManager.reset()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(localized("Reset"))
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())
            }
        }
    }

    private var stopwatchControlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    NotchHaptics.tap()
                    timerManager.toggleStartPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timerManager.model.isRunning ? "pause.fill" : "play.fill")
                        Text(timerManager.model.isRunning ? localized("Pause") : localized("Start"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(timerManager.model.isRunning ? Color.orange : Color.green))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                if timerManager.model.isRunning {
                    Button {
                        NotchHaptics.tap()
                        timerManager.recordLap()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flag.fill")
                            Text(localized("Lap"))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    NotchHaptics.tap()
                    timerManager.reset()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(localized("Reset"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !timerManager.laps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(timerManager.laps.enumerated()), id: \.offset) { index, lapTime in
                            HStack(spacing: 4) {
                                Text(String(format: localized("L%d:"), timerManager.laps.count - index))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(formatTime(lapTime))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                }
                .frame(height: 26)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
