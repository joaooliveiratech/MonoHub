import SwiftUI
import AppKit

struct HomeDashboardView: View {
    @Bindable private var preferences = NotchPreferences.shared
    private let playbackManager = MediaPlaybackManager.shared
    private let calendarManager = CalendarManager.shared
    private let timerManager = TimerManager.shared
    private let batteryManager = BatteryManager.shared
    private let bluetoothManager = BluetoothManager.shared

    init() {}

    private var activeCards: [HomeCard] {
        var cards = preferences.visibleHomeCards

        if preferences.homePrioritizeActive {

            cards.sort { a, b in
                let aScore = activityScore(for: a)
                let bScore = activityScore(for: b)
                if aScore != bScore {
                    return aScore > bScore
                }
                let aIdx = preferences.homeCardOrder.firstIndex(of: a) ?? 0
                let bIdx = preferences.homeCardOrder.firstIndex(of: b) ?? 0
                return aIdx < bIdx
            }
        }

        return cards
    }

    private func activityScore(for card: HomeCard) -> Int {
        switch card {
        case .music:
            return (playbackManager.isAvailable && playbackManager.currentTrack.isPlaying && !playbackManager.currentTrack.isEmpty) ? 10 : 0
        case .timer:
            return timerManager.model.isRunning ? 10 : 0
        case .calendar:
            if let next = calendarManager.nextUpcomingEvent,
               next.isActiveOrStartingSoon(withinMinutes: preferences.calendarLiveActivityLeadMinutes) {
                return 10
            }
            return 0
        case .battery:
            let b = batteryManager.batteryInfo
            return (b.isCharging || b.percentage <= 20) ? 5 : 0
        case .bluetooth:
            return !bluetoothManager.connectedDevices.isEmpty ? 2 : 0
        case .clipboard:
            if let last = ClipboardManager.shared.lastCopiedItem,
               Date().timeIntervalSince(last.copiedAt) < 60 {
                return 8
            }
            return 1
        case .teleprompter:
            let prompter = TeleprompterManager.shared
            return prompter.isPlaying ? 10 : (prompter.isPinned ? 9 : 2)
        case .aiQuota:
            let enabled = QuotaPreferencesManager.shared.enabledProviders
            let providers = enabled.isEmpty ? [.claude, .codex, .antigravity] : Array(enabled.prefix(3))
            let maxUsage = providers.compactMap { QuotaManager.shared.status(for: $0).primaryUsagePercent }.max() ?? 0
            return maxUsage >= 70 ? 9 : (maxUsage > 0 ? 4 : 1)
        case .heavyProcess:
            let isThermal = SystemMonitorEngine.shared.sensorsData.thermalState != .nominal
            let topCpu = SystemMonitorEngine.shared.cpuData.topProcesses.first?.cpuPercent ?? 0
            return (isThermal || topCpu >= 60.0) ? 10 : 2
        }
    }

    private var shouldShowHeaderBar: Bool {
        preferences.homeShowHeader && (
            preferences.homeShowHeaderDate ||
            preferences.homeShowHeaderClock ||
            preferences.homeShowHeaderBattery
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if shouldShowHeaderBar {
                    headerBar
                        .padding(.bottom, 2)
                }

                if activeCards.isEmpty {
                    emptyHomeState
                } else {
                    let columns = preferences.homeGridSingleColumn
                        ? [GridItem(.flexible(), spacing: 10)]
                        : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(activeCards) { card in
                            cardView(for: card)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .notchModule()
        .onAppear {
            if preferences.showHomeCalendarCard {
                calendarManager.checkAuthorization()
            }
        }
        .task(id: preferences.showHomeBluetoothCard) {
            guard preferences.showHomeBluetoothCard else { return }
            while !Task.isCancelled {
                bluetoothManager.refreshDevices()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if preferences.homeShowHeaderDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))

                    TimelineView(.everyMinute) { context in
                        Text(NotchFormatters.capitalizedLongDate(context.date))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if preferences.homeShowHeaderClock {
                    TimelineView(.everyMinute) { context in
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(NotchTheme.secondaryText)
                            Text(NotchFormatters.shortTime.string(from: context.date))
                                .font(NotchTheme.caption.monospacedDigit())
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }

                if preferences.homeShowHeaderBattery {
                    let battery = batteryManager.batteryInfo
                    HStack(spacing: 4) {
                        Image(systemName: battery.isCharging ? "bolt.fill" : NotchBatteryGlyph.name(for: battery))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotchBatteryGlyph.tint(for: battery))
                        Text("\(battery.percentage)%")
                            .font(NotchTheme.caption.monospacedDigit())
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
        }
        .padding(.horizontal, 2)
        .contextMenu {
            Toggle(localized("Show date"), isOn: $preferences.homeShowHeaderDate)
            Toggle(localized("Show clock"), isOn: $preferences.homeShowHeaderClock)
            Toggle(localized("Show battery"), isOn: $preferences.homeShowHeaderBattery)
            Divider()
            Toggle(localized("Show header"), isOn: $preferences.homeShowHeader)
        }
    }

    private var emptyHomeState: some View {
        NotchEmptyState(
            systemImage: "square.grid.2x2",
            tint: .blue,
            title: localized("No cards enabled"),
            message: localized("Enable Home screen cards in Settings to customize your dashboard."),
            actionTitle: localized("Open Settings")
        ) {
            NotchStatusItemController.openSettings()
        }
        .frame(height: 140)
    }

    @ViewBuilder
    private func cardView(for card: HomeCard) -> some View {
        switch card {
        case .music:
            musicCard
        case .calendar:
            calendarCard
        case .timer:
            timerCard
        case .battery:
            batteryCard
        case .bluetooth:
            bluetoothCard
        case .clipboard:
            clipboardCard
        case .teleprompter:
            teleprompterCard
        case .aiQuota:
            aiQuotaCard
        case .heavyProcess:
            heavyProcessCard
        }
    }

    private var musicCard: some View {
        let track = playbackManager.currentTrack
        let hasActive = playbackManager.isAvailable && !track.isEmpty

        return NotchCard(
            (!hasActive || track.appName.isEmpty) ? localized("Music") : track.appName,
            systemImage: track.playerType.iconName,
            tint: .pink,
            destination: .music,
            accessory: {
                if hasActive && track.isPlaying {
                    EqualizerAnimationView(isAnimating: true, tint: .pink, maxHeight: 11)
                }
            }
        ) {
            HStack(spacing: 10) {

                NotchArtworkView(image: hasActive ? playbackManager.artwork : nil, size: 44, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasActive ? track.title : localized("No playback"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)

                    Text(hasActive ? (track.artist.isEmpty ? track.appName : track.artist) : localized("Tap to open"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)

                    if hasActive && track.duration > 0 {
                        PlaybackTimeline(isPlaying: track.isPlaying) { date in
                            NotchProgressBar(
                                progress: playbackManager.progress(at: date),
                                tint: .pink,
                                height: 3
                            )
                        }
                        .padding(.top, 3)
                    }
                }

                Spacer(minLength: 4)

                if hasActive {

                    Button {
                        NotchHaptics.tap()
                        playbackManager.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .offset(x: track.isPlaying ? 0 : 0.5)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(NotchCircleButtonStyle(size: 28, fill: .white, foreground: .black))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .padding(.trailing, 4)
                }
            }
        }
    }

    private var calendarCard: some View {
        let next = calendarManager.nextUpcomingEvent
        let totalToday = calendarManager.remainingEvents.count

        return NotchCard(
            localized("Calendar"),
            systemImage: "calendar",
            tint: .red,
            destination: .calendar,
            accessory: {
                if let next, next.isNow {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(localized("NOW"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                } else if calendarManager.isAuthorized && totalToday > 0 {
                    Text("\(totalToday)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(0.28))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.red.opacity(0.45), lineWidth: 0.5)
                                )
                        )
                }
            }
        ) {
            if !calendarManager.isAuthorized {
                HStack(spacing: 10) {
                    NotchDateBadge(date: Date(), size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Connect calendar"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)

                        Text(localized("Tap to allow access to events"))
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        NotchHaptics.tap()
                        calendarManager.requestAccess()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(NotchCircleButtonStyle(size: 26, fill: .red, foreground: .white))
                    .help(localized("Allow Calendar access"))
                }
            } else if let next {
                HStack(spacing: 10) {
                    NotchDateBadge(date: next.startDate, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)

                        Text(next.isNow ? String(format: localized("Now • %@"), next.localizedTimeString) : "\(next.localizedTimeString) • \(next.localizedRelativeString)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(next.isNow ? Color.green : NotchTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let url = next.meetingURL {
                        Button {
                            NotchHaptics.tap()
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "video.fill")
                        }
                        .buttonStyle(NotchCircleButtonStyle(size: 26, fill: .green, foreground: .black))
                        .help(localized("Join meeting"))
                    }
                }
            } else {
                HStack(spacing: 10) {
                    NotchDateBadge(date: Date(), size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Free schedule"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                        Text(localized("No upcoming events for today"))
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
    }

    private var timerCard: some View {
        let model = timerManager.model
        let isPomodoro = model.mode == .pomodoro
        let title = isPomodoro ? "Pomodoro" : model.mode.title
        let icon = isPomodoro ? "brain.head.profile" : (model.mode == .stopwatch ? "stopwatch" : "timer")
        let tintColor: Color = isPomodoro ? .orange : (model.mode == .stopwatch ? .mint : .orange)

        return NotchCard(
            title,
            systemImage: icon,
            tint: tintColor,
            destination: .timer,
            onCardTapped: {
                if !model.isRunning && model.mode != .pomodoro {
                    timerManager.setMode(.pomodoro)
                }
            },
            accessory: {
                if model.isRunning {
                    HStack(spacing: 4) {
                        if isPomodoro {
                            Text(model.pomodoroPhase.emoji)
                                .font(.system(size: 8))
                        }
                        Text(localized("ACTIVE"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(tintColor)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tintColor.opacity(0.18)))
                } else if isPomodoro && model.completedPomodoros > 0 {
                    HStack(spacing: 2) {
                        Text("\(model.completedPomodoros)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                        Text("🍅")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
        ) {
            HStack(spacing: 10) {
                TimerGlyph(size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.formattedDisplay)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: model.mode != .stopwatch))
                        .animation(.snappy(duration: 0.25), value: model.formattedDisplay)

                    Text(timerSubtitle(for: model))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    NotchHaptics.tap()
                    timerManager.toggleStartPause()
                } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .offset(x: model.isRunning ? 0 : 0.5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(NotchCircleButtonStyle(
                    size: 28,
                    fill: model.isRunning ? tintColor : Color.white,
                    foreground: .black
                ))
            }
        }
    }

    private func timerSubtitle(for model: TimerModel) -> String {
        switch model.mode {
        case .pomodoro:
            if model.isRunning {
                return String(format: localized("%@ in progress %@"), model.pomodoroPhase.title, model.pomodoroPhase.emoji)
            } else {
                return String(format: localized("%@ paused"), model.pomodoroPhase.title)
            }
        case .countdown:
            return model.isRunning ? localized("In progress") : localized("Paused")
        case .stopwatch:
            return model.isRunning ? localized("Running") : localized("Paused")
        }
    }

    private var batteryCard: some View {
        let battery = batteryManager.batteryInfo

        return NotchCard(
            localized("Battery"),
            systemImage: "battery.100.bolt",
            tint: .green,
            destination: .battery,
            accessory: {
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        ) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0, to: CGFloat(Double(battery.percentage) / 100.0))
                        .stroke(NotchBatteryGlyph.tint(for: battery), lineWidth: 3)
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                    Text("\(battery.percentage)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(battery.isCharging ? localized("Charging") : (battery.isPluggedIn ? localized("On power") : localized("On battery")))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)

                    Text(battery.statusDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var bluetoothCard: some View {
        let devices = bluetoothManager.connectedDevices

        return NotchCard(
            localized("Bluetooth"),
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .indigo,
            destination: .bluetooth,
            accessory: {
                if !devices.isEmpty {
                    Text("\(devices.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.indigo)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.indigo.opacity(0.18)))
                }
            }
        ) {
            if devices.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("No devices"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.primaryText)
                        Text(localized("No connected accessories"))
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(devices.prefix(2)) { dev in
                        HStack(spacing: 5) {
                            Image(systemName: dev.category.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(NotchTheme.primaryText)
                            Text(dev.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            if let b = dev.primaryBattery {
                                Text("\(b)%")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(b <= 20 ? .red : .green)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var clipboardCard: some View {
        let lastItem = ClipboardManager.shared.lastCopiedItem

        return NotchCard(
            localized("Clipboard"),
            systemImage: "doc.on.clipboard.fill",
            tint: .orange,
            destination: .clipboard,
            accessory: {
                if let lastItem {
                    Text(lastItem.relativeTimeString)
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)
                }
            }
        ) {
            if let item = lastItem {
                HStack(spacing: 8) {
                    Group {
                        switch item.type {
                        case .color:
                            if let col = item.colorInfo {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(col.swiftUIColor)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.75)
                                    )
                            } else {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundStyle(Color.orange)
                            }
                        case .image:
                            Image(systemName: "photo.fill")
                                .foregroundStyle(Color.purple)
                        case .link:
                            Image(systemName: "link")
                                .foregroundStyle(Color.indigo)
                        case .text:
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(Color.blue)
                        }
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.previewText)
                            .font(NotchTheme.title)
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)

                        Text(item.type.title + (item.sourceAppName != nil ? " • \(item.sourceAppName!)" : ""))
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        NotchHaptics.tap()
                        ClipboardManager.shared.open(item: item)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(localized("Open with default application"))

                    Button {
                        NotchHaptics.tap()
                        ClipboardManager.shared.paste(item: item)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(localized("Paste or copy"))
                }
            } else {
                HStack {
                    Text(localized("No copied items"))
                        .font(NotchTheme.body)
                        .foregroundStyle(NotchTheme.secondaryText)
                    Spacer()
                }
            }
        }
    }

    private var teleprompterCard: some View {
        let prompter = TeleprompterManager.shared
        let script = prompter.activeScript
        let isPlaying = prompter.isPlaying

        return NotchCard(
            localized("Teleprompter"),
            systemImage: "text.viewfinder",
            tint: .mint,
            destination: .teleprompter,
            accessory: {
                if isPlaying {
                    HStack(spacing: 4) {
                        Circle().fill(Color.mint).frame(width: 6, height: 6)
                        Text(localized("SCROLLING"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.mint)
                    }
                } else if prompter.isPinned {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.mint)
                        Text(localized("PINNED"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.mint)
                    }
                } else {
                    Text(script.formattedReadingTime)
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)
                }
            }
        ) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mint.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.mint.opacity(0.32), lineWidth: 0.75)
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(NotchTheme.title)
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)

                    Text(script.previewSnippet)
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    NotchHaptics.tap()
                    prompter.togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .offset(x: isPlaying ? 0 : 0.5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(NotchCircleButtonStyle(
                    size: 28,
                    fill: isPlaying ? Color.mint : Color.white,
                    foreground: .black
                ))
                .help(isPlaying ? localized("Pause Teleprompter") : localized("Start Teleprompter"))
            }
        }
    }

    private var aiQuotaCard: some View {
        let enabled = QuotaPreferencesManager.shared.enabledProviders
        let providers: [ProviderType] = enabled.isEmpty ? [.claude, .codex, .antigravity] : Array(enabled.prefix(3))
        let maxUsage = providers.compactMap { QuotaManager.shared.status(for: $0).primaryUsagePercent }.max() ?? 0
        let isRefreshing = QuotaManager.shared.isRefreshing

        return NotchCard(
            localized("AI Quotas"),
            systemImage: AIQuotaStyle.symbol,
            tint: AIQuotaStyle.tint,
            onCardTapped: {
                MainWindowController.shared.show(item: .aiQuota)
            },
            accessory: {
                HStack(spacing: 4) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else if maxUsage > 0 {
                        Text("\(Int(maxUsage.rounded()))% \(localized("peak"))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.usageColor(for: maxUsage))
                    }
                }
            }
        ) {
            VStack(spacing: 6) {
                ForEach(providers) { provider in
                    let status = QuotaManager.shared.status(for: provider)
                    let pct = status.primaryUsagePercent ?? (status.hasReading ? 0 : nil)

                    HStack(spacing: 6) {
                        BrandIcon(provider: provider, size: 13)
                        Text(provider.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let pct {
                            NotchProgressBar(progress: pct / 100.0, tint: .usageColor(for: pct), height: 3)
                                .frame(width: 44)

                            Text("\(Int(pct.rounded()))%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.usageColor(for: pct))
                                .frame(width: 28, alignment: .trailing)
                        } else {
                            Text(status.state == .loading ? localized("Checking…") : "--")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var heavyProcessCard: some View {
        let cpu = SystemMonitorEngine.shared.cpuData
        let sensors = SystemMonitorEngine.shared.sensorsData
        let topProcesses = Array(cpu.topProcesses.prefix(2))
        let isThermalWarning = sensors.thermalState != .nominal || (sensors.socTemperature ?? 0) >= 80

        return NotchCard(
            localized("Heavy Processes & Thermal"),
            systemImage: isThermalWarning ? "flame.fill" : "cpu",
            tint: isThermalWarning ? .red : .orange,
            onCardTapped: {
                MainWindowController.shared.show(item: .monitor)
            },
            accessory: {
                HStack(spacing: 4) {
                    if let temp = sensors.socTemperature {
                        Text(Formatting.temperature(temp))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(isThermalWarning ? .red : .secondary)
                    }
                }
            }
        ) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(localized("CPU Total"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                    Spacer()
                    NotchProgressBar(progress: cpu.totalUsage, tint: .orange, height: 3)
                        .frame(width: 44)
                    Text("\(Int(cpu.totalUsage * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NotchTheme.primaryText)
                        .frame(width: 28, alignment: .trailing)
                }

                if !topProcesses.isEmpty {
                    ForEach(topProcesses) { proc in
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(proc.cpuPercent >= 50 ? .red : .orange)
                            Text(proc.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NotchTheme.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(proc.formattedCPU)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(proc.cpuPercent >= 50 ? .red : NotchTheme.secondaryText)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(localized("Thermal State"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NotchTheme.secondaryText)
                        Spacer()
                        Text(sensors.thermalDescription)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isThermalWarning ? .red : .green)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
