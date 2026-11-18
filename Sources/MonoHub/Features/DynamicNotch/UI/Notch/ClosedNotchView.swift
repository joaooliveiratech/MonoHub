import SwiftUI
import AppKit

struct ClosedNotchView: View {
    private let preferences = NotchPreferences.shared
    private let center = LiveActivityCenter.shared
    private let hudManager = HUDManager.shared
    private let batteryManager = BatteryManager.shared

    let hasHardwareNotch: Bool
    let physicalNotchWidth: CGFloat
    let metrics: ClosedNotchMetrics
    var onTapPrimary: (() -> Void)? = nil
    var onTapSecondary: (() -> Void)? = nil

    init(
        hasHardwareNotch: Bool = true,
        physicalNotchWidth: CGFloat = 185,
        metrics: ClosedNotchMetrics,
        onTapPrimary: (() -> Void)? = nil,
        onTapSecondary: (() -> Void)? = nil
    ) {
        self.hasHardwareNotch = hasHardwareNotch
        self.physicalNotchWidth = physicalNotchWidth
        self.metrics = metrics
        self.onTapPrimary = onTapPrimary
        self.onTapSecondary = onTapSecondary
    }

    private var hudVisible: Bool {
        preferences.enableSystemHUD && hudManager.isVisible && hudManager.activeHUD != nil
    }

    private var isCombined: Bool {
        preferences.liveActivityLayout == .combined && center.secondary != nil
    }

    private var hasIdleAnimationEnabled: Bool {
        preferences.idleAnimation != .none
            && (!hasHardwareNotch || preferences.showIdleOnHardwareNotch)
            && (preferences.idleInteractionMode != .onlyWhenTyping || IdleInteractionMonitor.shared.isInteracting)
    }

    private var sharesAnimationSideBySide: Bool {
        center.primary != nil
            && hasIdleAnimationEnabled
            && preferences.idleWithActivityMode == .sideBySide
    }

    private var forcesCombinedForAnimBubble: Bool {
        center.primary != nil
            && center.secondary != nil
            && hasIdleAnimationEnabled
            && preferences.idleWithActivityMode == .detachedBubble
    }

    private var shouldShowIdleContent: Bool {
        center.primary == nil && (!hasHardwareNotch || preferences.showIdleOnHardwareNotch)
    }

    private var shouldShowIdleAnimation: Bool {
        shouldShowIdleContent && preferences.idleAnimation != .none
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if hudVisible, let hud = hudManager.activeHUD {
                    hudBar(hud)
                        .transition(.notchActivity)
                } else if shouldShowIdleAnimation {
                    idleAnimationBar
                        .transition(.notchActivity)
                } else {
                    activityBar
                        .transition(.notchActivity)
                }
            }
            .frame(height: metrics.baseHeight)

            if let peek = center.peek, !hudVisible, center.isPeekEffective(for: peek) {
                NotchPeekRow(peek: peek)
                    .frame(height: LiveActivityCenter.peekHeight)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        switch peek {
                        case .quotaReset:
                            MainWindowController.shared.show(item: .aiQuota)
                        case .thermalAlert, .cpuPeak:
                            MainWindowController.shared.show(item: .monitor)
                        default:
                            onTapPrimary?()
                        }
                    }
                    .transition(.notchActivity)
            }
        }
        .frame(width: metrics.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapPrimary?()
        }
        .animation(NotchTheme.activity, value: center.activities)
        .animation(NotchTheme.activity, value: center.peek)
        .animation(NotchTheme.activity, value: hudVisible)
        .animation(NotchTheme.activity, value: preferences.idleAnimation)
    }

    private var idleAnimationBar: some View {
        NotchIdleAnimationView(
            animation: preferences.idleAnimation,
            speed: preferences.idleAnimationSpeed,
            hasHardwareNotch: hasHardwareNotch,
            physicalNotchWidth: physicalNotchWidth,
            interactionMode: preferences.idleInteractionMode
        )
        .padding(.horizontal, hasHardwareNotch ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapPrimary?()
        }
    }

    @ViewBuilder
    private var activityBar: some View {
        if !hasHardwareNotch && sharesAnimationSideBySide, let primary = center.primary {
            virtualNotchSharedActivityBar(primary: primary)
        } else {
            standardActivityBar
        }
    }

    private func virtualNotchSharedActivityBar(primary: LiveActivityKind) -> some View {
        HStack(spacing: 0) {
            compactCombinedActivityView(for: primary)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapPrimary?()
                }

            verticalDivider

            NotchIdleAnimationView(
                animation: preferences.idleAnimation,
                speed: preferences.idleAnimationSpeed,
                hasHardwareNotch: false,
                physicalNotchWidth: 0,
                interactionMode: preferences.idleInteractionMode,
                compactSingleWing: isCombined
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("virtual-shared-idle-\(preferences.idleAnimation.rawValue)")
            .contentShape(Rectangle())
            .onTapGesture {
                onTapPrimary?()
            }

            if isCombined, let secondary = center.secondary {
                verticalDivider

                compactCombinedActivityView(for: secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapSecondary?()
                    }
            }
        }
        .padding(.horizontal, 12)
    }

    private var verticalDivider: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.white.opacity(0.16))
            .frame(width: 1.5, height: 14)
            .padding(.horizontal, 8)
    }

    private var standardActivityBar: some View {
        let usesCombinedWings = isCombined || forcesCombinedForAnimBubble || sharesAnimationSideBySide
        return HStack(spacing: 0) {
            leadingWing
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: hasHardwareNotch ? (usesCombinedWings ? .center : .leading) : .leading
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapPrimary?()
                }

            if hasHardwareNotch {
                Color.clear
                    .frame(width: physicalNotchWidth, height: metrics.baseHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapPrimary?()
                    }
            } else if usesCombinedWings {
                verticalDivider
            } else if center.primary != nil {
                Spacer(minLength: 10)
            }

            trailingWing
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: hasHardwareNotch ? (usesCombinedWings ? .center : .trailing) : .trailing
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if (isCombined || forcesCombinedForAnimBubble) && !sharesAnimationSideBySide {
                        onTapSecondary?()
                    } else {
                        onTapPrimary?()
                    }
                }
        }
        .padding(.horizontal, hasHardwareNotch ? 12 : 14)
    }

    private func compactCombinedActivityView(for kind: LiveActivityKind) -> some View {
        HStack(spacing: 5) {
            LiveActivityCompactLeading(kind: kind, showsLabel: false)
            LiveActivityCompactTrailing(kind: kind)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var leadingWing: some View {
        if let primary = center.primary {
            if isCombined || forcesCombinedForAnimBubble || sharesAnimationSideBySide {
                compactCombinedActivityView(for: primary)
                    .id("combined-leading-\(primary.rawValue)")
                    .transition(.notchActivity)
            } else {
                LiveActivityCompactLeading(
                    kind: primary,
                    showsLabel: !hasHardwareNotch && (primary == .music || primary == .calendar)
                )
                .id("leading-\(primary.rawValue)")
                .transition(.notchActivity)
            }
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        if let primary = center.primary {
            if sharesAnimationSideBySide {
                NotchIdleAnimationView(
                    animation: preferences.idleAnimation,
                    speed: preferences.idleAnimationSpeed,
                    hasHardwareNotch: false,
                    physicalNotchWidth: 0,
                    interactionMode: preferences.idleInteractionMode,
                    compactSingleWing: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("trailing-idle-\(preferences.idleAnimation.rawValue)")
                .transition(.notchActivity)
            } else if isCombined || forcesCombinedForAnimBubble, let secondary = center.secondary {
                compactCombinedActivityView(for: secondary)
                    .id("combined-trailing-\(secondary.rawValue)")
                    .transition(.notchActivity)
            } else {
                LiveActivityCompactTrailing(kind: primary)
                .id("trailing-\(primary.rawValue)")
                .transition(.notchActivity)
            }
        }
    }

    @ViewBuilder
    private func hudBar(_ hud: HUDEvent) -> some View {
        let isMic = hud.type == .micMute || hud.type == .micVolume
        let tint: Color = hud.isMuted ? .red : (isMic ? .green : .white)
        let iconName: String = isMic ? (hud.isMuted ? "mic.slash.fill" : "mic.fill") : (hud.customIconName ?? hud.type.iconName)

        if hasHardwareNotch {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                    if let title = hud.displayTitle {
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Text(hud.percentageString)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(hud.isMuted && isMic ? .red : .white)
                        .contentTransition(.numericText(value: Double(hud.value)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: physicalNotchWidth, height: 1)

                if isMic && hud.isMuted {
                    Text(localized("Muted").uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.2)))
                        .foregroundStyle(.red)
                        .frame(width: LiveActivityCenter.hudWing - 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    NotchProgressBar(progress: Double(isMic && !hud.isMuted && hud.value == 0 ? 1.0 : hud.value), tint: tint, height: 5)
                        .frame(width: LiveActivityCenter.hudWing - 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hud.value)
        } else {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                if let title = hud.displayTitle {
                    Text(title)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if isMic && hud.isMuted {
                    Text(localized("Microphone Muted"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                } else {
                    NotchProgressBar(progress: Double(isMic && !hud.isMuted && hud.value == 0 ? 1.0 : hud.value), tint: tint, height: 4)
                    Text(hud.percentageString)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hud.value)
        }
    }
}

struct LiveActivityCompactLeading: View {
    let kind: LiveActivityKind
    var showsLabel: Bool = false

    private let playback = MediaPlaybackManager.shared
    private let timer = TimerManager.shared
    private let center = LiveActivityCenter.shared
    private let battery = BatteryManager.shared

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .music:
                NotchArtworkView(image: playback.artwork, size: 20, cornerRadius: 5)
                if showsLabel {
                    label(playback.currentTrack.title)
                }
            case .timer:
                TimerGlyph(size: 18)
            case .calendar:
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                if showsLabel, let event = center.activeCalendarEvent {
                    label(event.title)
                }
            case .battery:
                let info = battery.batteryInfo
                Image(systemName: info.isCharging ? "bolt.fill" : NotchBatteryGlyph.name(for: info))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchBatteryGlyph.tint(for: info))
                if showsLabel {
                    label(info.isCharging ? localized("Charging") : localized("Low battery"))
                }
            case .aiQuota:
                let provider = LiveActivityCenter.topProvider
                BrandIcon(provider: provider, size: 14)
                if showsLabel {
                    label(provider.displayName)
                }
            case .heavyProcess:
                let isThermal = LiveActivityCenter.isThermalWarning
                Image(systemName: isThermal ? "flame.fill" : "cpu.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isThermal ? .red : .orange)
                if showsLabel {
                    let name = isThermal ? localized("Thermal Alert") : (SystemMonitorEngine.shared.cpuData.topProcesses.first?.name ?? "CPU")
                    label(name)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

struct LiveActivityCompactTrailing: View {
    let kind: LiveActivityKind

    private let playback = MediaPlaybackManager.shared
    private let timer = TimerManager.shared
    private let center = LiveActivityCenter.shared
    private let battery = BatteryManager.shared

    var body: some View {
        switch kind {
        case .music:
            EqualizerAnimationView(isAnimating: playback.currentTrack.isPlaying, tint: .pink, maxHeight: 12)
        case .timer:
            let model = timer.model
            Text(model.formattedDisplay)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TimerGlyph.tint(for: model))
                .opacity(model.isRunning ? 1 : 0.6)
                .contentTransition(.numericText(countsDown: model.mode == .countdown))
                .animation(.snappy(duration: 0.3), value: model.formattedDisplay)
        case .calendar:
            let activeEvent = center.activeCalendarEvent
            let isNow = activeEvent?.isNow ?? true
            let badgeColor: Color = isNow ? .green : .orange
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(badgeColor)
                TimelineView(.everyMinute) { _ in
                    Text(activeEvent?.shortIslandCountdown ?? "Agora")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(badgeColor)
                }
            }
        case .battery:
            let info = battery.batteryInfo
            Text("\(info.percentage)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchBatteryGlyph.tint(for: info))
        case .aiQuota:
            let status = QuotaManager.shared.status(for: LiveActivityCenter.topProvider)
            let percent = status.primaryUsagePercent ?? status.peakUsagePercent
            HStack(spacing: 4) {
                NotchProgressRing(progress: percent / 100.0, tint: .usageColor(for: percent), lineWidth: 2)
                    .frame(width: 13, height: 13)
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.usageColor(for: percent))
            }
        case .heavyProcess:
            let isThermal = LiveActivityCenter.isThermalWarning
            if isThermal, let temp = SystemMonitorEngine.shared.sensorsData.socTemperature {
                Text(Formatting.temperature(temp))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            } else if let top = SystemMonitorEngine.shared.cpuData.topProcesses.first {
                Text("\(Int(top.cpuPercent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            } else {
                Text("\(Int((SystemMonitorEngine.shared.cpuData.totalUsage * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct LiveActivityMinimalView: View {
    let kind: LiveActivityKind

    private let playback = MediaPlaybackManager.shared
    private let battery = BatteryManager.shared

    var body: some View {
        switch kind {
        case .music:
            ZStack {
                NotchArtworkView(image: playback.artwork, size: 22, cornerRadius: 11)
            }
        case .timer:
            TimerGlyph(size: 20)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        case .battery:
            let info = battery.batteryInfo
            ZStack {
                NotchProgressRing(progress: Double(info.percentage) / 100, tint: NotchBatteryGlyph.tint(for: info), lineWidth: 2)
                    .frame(width: 20, height: 20)
                Image(systemName: info.isCharging ? "bolt.fill" : "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(NotchBatteryGlyph.tint(for: info))
            }
        case .aiQuota:
            let provider = LiveActivityCenter.topProvider
            let status = QuotaManager.shared.status(for: provider)
            let percent = status.primaryUsagePercent ?? status.peakUsagePercent
            ZStack {
                NotchProgressRing(progress: percent / 100.0, tint: .usageColor(for: percent), lineWidth: 2)
                    .frame(width: 20, height: 20)
                BrandIcon(provider: provider, size: 10)
            }
        case .heavyProcess:
            let isThermal = LiveActivityCenter.isThermalWarning
            Image(systemName: isThermal ? "flame.fill" : "cpu.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isThermal ? .red : .orange)
        }
    }
}

struct NotchPeekRow: View {
    let peek: NotchPeek
    private let playback = MediaPlaybackManager.shared

    var body: some View {
        HStack(spacing: 8) {
            switch peek {
            case .track(let title, let artist):
                NotchArtworkView(image: playback.artwork, size: 24, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                EqualizerAnimationView(isAnimating: true, tint: .pink, maxHeight: 12)
            case .timerFinished:
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, options: .repeat(3))
                Text(localized("Timer completed"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(localized("Tap to open"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
            case .quotaReset(let provider, let window):
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .repeat(2))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(provider) \(localized("Reset"))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(window.isEmpty ? localized("Rate-limit window restored") : "\(localized("Window")) \(window) \(localized("renewed (100% available)"))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(localized("100% available"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            case .thermalAlert(let temp, let state):
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeat(2))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(localized("Thermal Alert")): \(state)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(localized("SoC at")) \(Formatting.temperature(temp)) • \(localized("High load"))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Formatting.temperature(temp))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            case .cpuPeak(let process, let usage):
                Image(systemName: "cpu.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeat(2))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(localized("CPU Spike")): \(process)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(localized("Elevated system usage"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(Int(usage.rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct TimerGlyph: View {
    let size: CGFloat
    private let timer = TimerManager.shared

    static func tint(for model: TimerModel) -> Color {
        switch model.mode {
        case .pomodoro:
            return model.pomodoroPhase == .focus ? .orange : (model.pomodoroPhase == .shortBreak ? .yellow : .mint)
        case .countdown:
            return .orange
        case .stopwatch:
            return .mint
        }
    }

    static func ringProgress(for model: TimerModel) -> Double {
        switch model.mode {
        case .countdown, .pomodoro:
            guard model.targetDuration > 0 else { return 0 }
            return model.remainingSeconds / model.targetDuration
        case .stopwatch:
            return Double(Int(model.elapsedTime) % 60) / 60
        }
    }

    var body: some View {
        let model = timer.model
        let tint = TimerGlyph.tint(for: model)
        ZStack {
            NotchProgressRing(progress: TimerGlyph.ringProgress(for: model), tint: tint, lineWidth: 2.2)
                .animation(.linear(duration: 0.9), value: model.remainingSeconds)
            Image(systemName: model.isRunning ? (model.mode == .stopwatch ? "stopwatch" : (model.mode == .pomodoro ? model.pomodoroPhase.icon : "timer")) : "pause.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
    }
}

enum NotchBatteryGlyph {
    static func name(for info: BatteryInfo) -> String {
        if info.isCharging { return "battery.100.bolt" }
        switch info.percentage {
        case 0...10: return "battery.0"
        case 11...35: return "battery.25"
        case 36...60: return "battery.50"
        case 61...85: return "battery.75"
        default: return "battery.100"
        }
    }

    static func tint(for info: BatteryInfo) -> Color {
        if info.isCharging { return .green }
        if info.percentage <= 20 { return .red }
        return .white.opacity(0.8)
    }
}
