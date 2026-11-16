import Foundation
import AppKit
import Observation

enum NotchPeek: Equatable {
    case track(title: String, artist: String)
    case timerFinished
    case quotaReset(provider: String, window: String)
    case thermalAlert(temperature: Double, state: String)
    case cpuPeak(process: String, usage: Double)
}

struct ClosedNotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var baseHeight: CGFloat
    var bubbleDiameter: CGFloat
    var bubbleSpacing: CGFloat = 6
    var hasAnimationBubble: Bool = false
    var animationBubbleWidth: CGFloat = 52

    var hasBubble: Bool { bubbleDiameter > 0 }
}

@Observable
@MainActor
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()

    private(set) var activities: [LiveActivityKind] = []
    private(set) var peek: NotchPeek?

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTimer: Timer?
    @ObservationIgnored private var boundaryDate: Date?
    @ObservationIgnored private var lastPeekedTitle: String = ""
    @ObservationIgnored private var lastPeekedDate: Date = .distantPast
    private var clockTick: Int = 0

    static let singleWing: CGFloat = 72
    static let combinedWing: CGFloat = 96
    static let hudWing: CGFloat = 84
    static let peekHeight: CGFloat = 40

    private init() {}

    var primary: LiveActivityKind? { activities.first }

    var secondary: LiveActivityKind? {
        guard NotchPreferences.shared.liveActivityLayout != .single else { return nil }
        return activities.dropFirst().first
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observationTask = Task { [weak self] in
            let stream = Observations { @MainActor [weak self] in
                self?.computeActivities() ?? []
            }
            for await resolved in stream {
                guard let self, self.isRunning, !Task.isCancelled else { break }
                if resolved != self.activities {
                    self.activities = resolved
                }
                self.scheduleCalendarBoundary()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observationTask?.cancel()
        observationTask = nil
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        boundaryDate = nil
        peekTask?.cancel()
        peekTask = nil
        if peek != nil { peek = nil }
        if !activities.isEmpty { activities = [] }
    }

    func isPeekEffective(for peek: NotchPeek?) -> Bool {
        guard let peek else { return false }
        if case .track = peek, (primary == .music || secondary == .music) {
            return false
        }
        return true
    }

    static func resolve(priority: [LiveActivityKind], isActive: (LiveActivityKind) -> Bool) -> [LiveActivityKind] {
        priority.filter(isActive)
    }

    static func isTimerActive(_ model: TimerModel, includePaused: Bool) -> Bool {
        if model.isRunning { return true }
        guard includePaused else { return false }
        switch model.mode {
        case .pomodoro, .countdown:
            return model.remainingSeconds > 0 && model.remainingSeconds < model.targetDuration
        case .stopwatch:
            return model.elapsedTime > 0
        }
    }

    static func isBatteryActive(_ info: BatteryInfo) -> Bool {
        info.isCharging || (!info.isPluggedIn && info.percentage <= 20)
    }

    static func nextCalendarBoundary(after now: Date, events: [CalendarEventItem], leadMinutes: Int) -> Date? {
        let lead = TimeInterval(max(0, leadMinutes) * 60)
        var candidates: [Date] = []
        for event in events where !event.isAllDay && event.endDate > now {
            candidates.append(event.startDate.addingTimeInterval(-lead))
            candidates.append(event.startDate)
            candidates.append(event.endDate)
        }
        return candidates.filter { $0 > now }.min()
    }

    static func metrics(
        hasHardwareNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        idleVirtualWidth: CGFloat,
        primary: LiveActivityKind?,
        secondary: LiveActivityKind?,
        layout: LiveActivityLayout,
        hudVisible: Bool,
        hasPeek: Bool,
        hasIdleContent: Bool = false,
        idleWingWidth: CGFloat = 68,
        idleWithActivityMode: NotchIdleWithActivityMode = .whenIdleOnly
    ) -> ClosedNotchMetrics {
        var width: CGFloat
        var bubble: CGFloat = 0
        var hasAnimBubble = false
        let hasTwo = primary != nil && secondary != nil
        let sharesSideBySide = primary != nil && hasIdleContent && idleWithActivityMode == .sideBySide && !hudVisible
        let usesAnimBubble = primary != nil && hasIdleContent && idleWithActivityMode == .detachedBubble && !hudVisible

        if hasHardwareNotch {
            if hudVisible {
                width = notchWidth + hudWing * 2
            } else if primary == nil {
                width = hasIdleContent ? (notchWidth + max(56, idleWingWidth) * 2) : notchWidth
            } else if sharesSideBySide {
                let wing = max(combinedWing, max(68, idleWingWidth) + 18)
                width = notchWidth + wing * 2
            } else if (hasTwo && layout == .combined) || (hasTwo && usesAnimBubble) {
                width = notchWidth + combinedWing * 2
            } else {
                width = notchWidth + singleWing * 2
            }
        } else {
            if hudVisible {
                width = max(idleVirtualWidth, 260)
            } else if primary == nil {
                width = hasIdleContent ? max(idleVirtualWidth, 200) : idleVirtualWidth
            } else if sharesSideBySide {
                let targetWidth: CGFloat = (hasTwo && layout == .combined) ? 350 : 285
                width = max(idleVirtualWidth, targetWidth)
            } else if (hasTwo && layout == .combined) || (hasTwo && usesAnimBubble) {
                width = max(idleVirtualWidth, 330)
            } else {
                width = max(idleVirtualWidth, 210)
            }
        }

        if usesAnimBubble {
            bubble = notchHeight
            hasAnimBubble = true
        } else if hasTwo && !hudVisible {
            if hasHardwareNotch {
                if layout == .split || sharesSideBySide {
                    bubble = notchHeight
                }
            } else if layout == .split {
                bubble = notchHeight
            }
        }

        var height = notchHeight
        if hasPeek && !hudVisible {
            height += peekHeight
            width = max(width, hasHardwareNotch ? notchWidth + 200 : 320)
        }

        return ClosedNotchMetrics(
            width: width,
            height: height,
            baseHeight: notchHeight,
            bubbleDiameter: bubble,
            hasAnimationBubble: hasAnimBubble,
            animationBubbleWidth: 64
        )
    }

    func metrics(for geometry: ScreenNotchGeometry) -> ClosedNotchMetrics {
        let prefs = NotchPreferences.shared
        let hudVisible = prefs.enableSystemHUD && HUDManager.shared.isVisible
        let interactionActive = prefs.idleInteractionMode != .onlyWhenTyping || IdleInteractionMonitor.shared.isInteracting
        let hasIdleContent = prefs.hasIdleContentEnabled
            && (!geometry.hasHardwareNotch || prefs.showIdleOnHardwareNotch)
            && interactionActive
        return LiveActivityCenter.metrics(
            hasHardwareNotch: geometry.hasHardwareNotch,
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight,
            idleVirtualWidth: prefs.closedNotchWidth,
            primary: primary,
            secondary: secondary,
            layout: prefs.liveActivityLayout,
            hudVisible: hudVisible,
            hasPeek: isPeekEffective(for: peek),
            hasIdleContent: hasIdleContent,
            idleWingWidth: prefs.idleWingWidth,
            idleWithActivityMode: prefs.idleWithActivityMode
        )
    }

    func showPeek(_ peek: NotchPeek, duration: TimeInterval = 3.0) {
        guard isRunning, !NotchWindowController.shared.isExpanded else { return }
        if case .track = peek, (primary == .music || secondary == .music) {
            return
        }
        peekTask?.cancel()
        self.peek = peek
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.peek = nil
        }
    }

    func dismissPeek() {
        peekTask?.cancel()
        if peek != nil { peek = nil }
    }

    func trackDidChange(_ track: MusicTrack) {
        let prefs = NotchPreferences.shared
        guard isRunning,
              prefs.showTrackChangePeek,
              prefs.showMusicLiveActivity,
              track.isPlaying,
              !track.isEmpty else { return }

        if primary == .music || secondary == .music {
            return
        }

        if track.title == lastPeekedTitle && abs(lastPeekedDate.timeIntervalSinceNow) < 4.0 {
            return
        }

        lastPeekedTitle = track.title
        lastPeekedDate = Date()
        showPeek(.track(title: track.title, artist: track.artist))
    }

    func timerDidComplete() {
        guard NotchPreferences.shared.showTimerCompletionPeek else { return }
        showPeek(.timerFinished, duration: 4.0)
    }

    func quotaDidReset(provider: String, window: String) {
        guard isRunning,
              FeatureManager.shared.isEnabled(.aiQuota),
              NotchPreferences.shared.showQuotaResetPeek else { return }
        showPeek(.quotaReset(provider: provider, window: window), duration: 4.5)
    }

    func clearAIQuota() {
        if case .quotaReset = peek {
            peekTask?.cancel()
            peek = nil
        }
    }

    func thermalAlertTriggered(temperature: Double, state: String) {
        guard isRunning, NotchPreferences.shared.showSystemAlertPeek else { return }
        showPeek(.thermalAlert(temperature: temperature, state: state), duration: 4.0)
    }

    func cpuPeakTriggered(process: String, usage: Double) {
        guard isRunning, NotchPreferences.shared.showSystemAlertPeek else { return }
        showPeek(.cpuPeak(process: process, usage: usage), duration: 4.0)
    }

    @ObservationIgnored private var lastCPUPeakDate: Date = .distantPast
    @ObservationIgnored private var lastCPUPeakProcess: String = ""
    @ObservationIgnored private var lastThermalAlertDate: Date = .distantPast

    func evaluateSystemHealth(cpu: CPUData, sensors: SensorsData) {
        guard isRunning else { return }
        let now = Date()

        let isThermalSerious = sensors.thermalState == .serious || sensors.thermalState == .critical
        let isThermalHot = (sensors.socTemperature ?? 0) >= NotchPreferences.shared.thermalAlertThreshold
        if (isThermalSerious || isThermalHot) && now.timeIntervalSince(lastThermalAlertDate) > 60 {
            lastThermalAlertDate = now
            let temp = sensors.socTemperature ?? 80.0
            thermalAlertTriggered(temperature: temp, state: sensors.thermalDescription)
        }

        let threshold = NotchPreferences.shared.heavyProcessThreshold
        let top = cpu.topProcesses.first
        let topPercent = top?.cpuPercent ?? 0
        let totalPercent = cpu.totalUsage * 100.0

        let isSpike = topPercent >= threshold || (totalPercent >= threshold && top != nil)

        if isSpike, let top, (top.name != lastCPUPeakProcess || now.timeIntervalSince(lastCPUPeakDate) > 60) {
            lastCPUPeakDate = now
            lastCPUPeakProcess = top.name
            let reportedUsage = max(topPercent, totalPercent)
            cpuPeakTriggered(process: top.name, usage: min(reportedUsage, 100.0))
        }
    }

    static var topProvider: ProviderType {
        let enabled = QuotaPreferencesManager.shared.enabledProviders
        var best: (ProviderType, Double)? = nil
        for p in enabled {
            let st = QuotaManager.shared.status(for: p)
            if let pct = st.primaryUsagePercent ?? (st.windows.first?.effectiveUsedPercent) {
                if best == nil || pct > best!.1 {
                    best = (p, pct)
                }
            }
        }
        if let best { return best.0 }
        return enabled.first ?? .antigravity
    }

    static var isThermalWarning: Bool {
        let s = SystemMonitorEngine.shared.sensorsData
        return s.thermalState != .nominal || (s.socTemperature ?? 0) >= NotchPreferences.shared.thermalAlertThreshold
    }

    static func isAIQuotaActive() -> Bool {
        guard FeatureManager.shared.isEnabled(.aiQuota) else { return false }
        let enabled = QuotaPreferencesManager.shared.enabledProviders
        guard !enabled.isEmpty else { return false }
        return enabled.contains { p in
            let st = QuotaManager.shared.status(for: p)
            return st.hasReading && st.state != .idle
        }
    }

    static func isHeavyProcessActive(
        cpu: CPUData,
        sensors: SensorsData,
        cpuThreshold: Double = 70.0,
        tempThreshold: Double = 80.0
    ) -> Bool {
        if sensors.thermalState != .nominal { return true }
        if (sensors.socTemperature ?? 0) >= tempThreshold { return true }
        if (cpu.topProcesses.first?.cpuPercent ?? 0) >= cpuThreshold { return true }
        if cpu.totalUsage >= (cpuThreshold / 100.0) { return true }
        return false
    }

    var activeCalendarEvent: CalendarEventItem? {
        _ = clockTick
        let lead = NotchPreferences.shared.calendarLiveActivityLeadMinutes
        let events = CalendarManager.shared.upcomingEvents.filter {
            !$0.isAllDay && $0.isActiveOrStartingSoon(withinMinutes: lead)
        }
        if let current = events.first(where: { $0.isNow }) {
            return current
        }
        return events.first
    }

    private func scheduleCalendarBoundary() {
        let prefs = NotchPreferences.shared
        let next: Date? = (isRunning && prefs.showCalendarLiveActivity)
            ? Self.nextCalendarBoundary(
                after: Date(),
                events: CalendarManager.shared.upcomingEvents,
                leadMinutes: prefs.calendarLiveActivityLeadMinutes
            )
            : nil
        if next == boundaryDate, boundaryTimer?.isValid == true { return }
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        boundaryDate = next
        guard let next else { return }
        let timer = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clockTick &+= 1
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private func computeActivities() -> [LiveActivityKind] {
        _ = clockTick
        let prefs = NotchPreferences.shared
        let playback = MediaPlaybackManager.shared
        let track = playback.currentTrack
        let timerModel = TimerManager.shared.model
        let events = CalendarManager.shared.upcomingEvents
        let batteryInfo = BatteryManager.shared.batteryInfo
        let batteryRunning = BatteryManager.shared.isMonitoring
        let leadMinutes = prefs.calendarLiveActivityLeadMinutes

        return LiveActivityCenter.resolve(priority: prefs.liveActivityPriority) { kind in
            guard prefs.isLiveActivityEnabled(kind) else { return false }
            switch kind {
            case .music: return playback.isAvailable && track.isPlaying && !track.isEmpty
            case .timer: return LiveActivityCenter.isTimerActive(timerModel, includePaused: prefs.showPausedTimerActivity)
            case .calendar: return events.contains { !$0.isAllDay && $0.isActiveOrStartingSoon(withinMinutes: leadMinutes) }
            case .battery: return batteryRunning && LiveActivityCenter.isBatteryActive(batteryInfo)
            case .aiQuota: return LiveActivityCenter.isAIQuotaActive()
            case .heavyProcess:
                return LiveActivityCenter.isHeavyProcessActive(
                    cpu: SystemMonitorEngine.shared.cpuData,
                    sensors: SystemMonitorEngine.shared.sensorsData,
                    cpuThreshold: prefs.heavyProcessThreshold,
                    tempThreshold: prefs.thermalAlertThreshold
                )
            }
        }
    }
}
