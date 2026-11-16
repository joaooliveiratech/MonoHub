import SwiftUI
import AVFoundation

struct NotchModulesSection: View {
    @Bindable private var preferences = NotchPreferences.shared
    @Bindable private var camera = CameraMirrorManager.shared
    @Bindable private var teleprompter = TeleprompterManager.shared
    @State private var expandedModules: Set<NotchTab> = []

    private func toggleExpanded(_ tab: NotchTab) {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            if expandedModules.contains(tab) {
                expandedModules.remove(tab)
            } else {
                expandedModules.insert(tab)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized("Click any module or the Customize button to view its options. Use ↑↓ to reorder tabs."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !expandedModules.isEmpty {
                    Button(localized("Collapse Modules")) {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            expandedModules.removeAll()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .fixedSize()
                }
            }
            .padding(.bottom, 2)

            ForEach(preferences.tabOrder, id: \.self) { tab in
                let isEnabled = preferences.isTabEnabled(tab)
                let isExpanded = expandedModules.contains(tab)

                VStack(alignment: .leading, spacing: 0) {

                    HStack(spacing: 10) {
                        ReorderGrip()

                        Button {
                            toggleExpanded(tab)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                    .frame(width: 14)

                                HubSettingRowLabel(
                                    title: tab.title,
                                    subtitle: tab.settingsSubtitle,
                                    systemImage: tab.iconName,
                                    tint: isEnabled ? tab.accentColor : .secondary
                                )

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            toggleExpanded(tab)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(isExpanded ? localized("Hide") : localized("Customize"))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(isExpanded ? tab.accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isExpanded ? tab.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize()

                        Toggle("", isOn: Binding(
                            get: { preferences.isTabEnabled(tab) },
                            set: { preferences.setTab(tab, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .reorderableItem(scope: "notch-tab", item: tab, items: preferences.tabOrder) { preferences.tabOrder = $0 }

                    if isExpanded {
                        Divider()
                            .padding(.horizontal, 12)

                        VStack(alignment: .leading, spacing: 10) {
                            moduleCustomizationContent(for: tab)
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.02))
                        .transition(.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isExpanded ? 0.045 : 0.025))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isExpanded ? tab.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
        .onAppear {
            camera.refreshAuthorization()
            if camera.isAuthorized {
                camera.refreshDevices()
            }
        }
    }

    @ViewBuilder
    private func moduleCustomizationContent(for tab: NotchTab) -> some View {
        switch tab {
        case .home:
            HubToggleRow(
                title: localized("Automatically prioritize active cards at top"),
                isOn: $preferences.homePrioritizeActive
            )
            HubToggleRow(
                title: localized("Display cards in a single column (wide layout)"),
                isOn: $preferences.homeGridSingleColumn
            )
            HubToggleRow(
                title: localized("Show header bar in Home"),
                isOn: $preferences.homeShowHeader
            )
            if preferences.homeShowHeader {
                HStack(spacing: 20) {
                    Toggle(localized("Date"), isOn: $preferences.homeShowHeaderDate)
                    Toggle(localized("Clock"), isOn: $preferences.homeShowHeaderClock)
                    Toggle(localized("Battery"), isOn: $preferences.homeShowHeaderBattery)
                }
                .font(.system(size: 12))
                .padding(.leading, 12)
            }

            Divider()
            Text(localized("Home Dashboard Cards (Order and Visibility)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(preferences.homeCardOrder, id: \.self) { card in
                HStack(spacing: 10) {
                    ReorderGrip()
                    HubSettingRowLabel(title: card.title, subtitle: card.subtitle, systemImage: card.iconName, tint: card.tint)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferences.isHomeCardEnabled(card) },
                        set: { preferences.setHomeCard(card, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .reorderableItem(scope: "notch-home-card", item: card, items: preferences.homeCardOrder) { preferences.homeCardOrder = $0 }
            }

        case .music:
            HubToggleRow(
                title: localized("Show audio output, microphone & voice isolation selector"),
                isOn: $preferences.musicShowAudioRouteSelector
            )
            if preferences.musicShowAudioRouteSelector {
                HubToggleRow(
                    title: localized("Live microphone level meter (VU meter)"),
                    isOn: $preferences.musicEnableMicLevelMeter
                )
                .padding(.leading, 12)
            }
            HubToggleRow(
                title: localized("Show animated visualizer when playing"),
                isOn: $preferences.musicShowVisualizer
            )
            HubToggleRow(
                title: localized("Show elapsed and remaining time under progress bar"),
                isOn: $preferences.musicShowElapsedTimes
            )
            HubToggleRow(
                title: localized("Show Music Live Activity on closed notch"),
                isOn: $preferences.showMusicLiveActivity
            )
            HubToggleRow(
                title: localized("Show quick peek on track change"),
                isOn: $preferences.showTrackChangePeek
            )

        case .timer:
            HubStepperRow(
                title: localized("Default countdown timer duration"),
                value: $preferences.timerDefaultMinutes,
                range: 1...120,
                step: 1,
                valueLabel: String(format: localized("%d min"), preferences.timerDefaultMinutes)
            )
            HubToggleRow(
                title: localized("Play sound alert when countdown finishes"),
                isOn: $preferences.timerPlayCompletionSound
            )
            HubToggleRow(
                title: localized("Show Timer Live Activity on closed notch"),
                isOn: $preferences.showTimerLiveActivity
            )
            HubToggleRow(
                title: localized("Keep paused timer visible on closed notch"),
                isOn: $preferences.showPausedTimerActivity
            )
            HubToggleRow(
                title: localized("Show peek when timer completes"),
                isOn: $preferences.showTimerCompletionPeek
            )

            Divider()
            NotchFocusSettings()

        case .calendar:
            HubToggleRow(
                title: localized("Show all-day events in daily agenda"),
                isOn: $preferences.calendarShowAllDayEvents
            )
            HubStepperRow(
                title: localized("Maximum events listed"),
                value: $preferences.calendarMaxEventsShown,
                range: 2...12,
                step: 1,
                valueLabel: String(format: localized("%d events"), preferences.calendarMaxEventsShown)
            )
            HubToggleRow(
                title: localized("Show upcoming meeting on closed notch (Live Activity)"),
                isOn: $preferences.showCalendarLiveActivity
            )
            HubStepperRow(
                title: localized("Meeting reminder advance time on closed notch"),
                value: $preferences.calendarLiveActivityLeadMinutes,
                range: 0...60,
                step: 5,
                valueLabel: String(format: localized("%d min before"), preferences.calendarLiveActivityLeadMinutes)
            )

        case .reminders:
            HubToggleRow(
                title: localized("Show completed reminders in list"),
                isOn: $preferences.remindersShowCompleted
            )
            HubToggleRow(
                title: localized("Automatically sort by priority and due date"),
                isOn: $preferences.remindersSortByPriority
            )

        case .mirror:
            if camera.isAccessDenied {
                HStack {
                    Text(localized("Camera Permission"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Button(localized("Open System Settings…")) {
                        camera.openPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if !camera.availableDevices.isEmpty {
                HStack {
                    Text(localized("Selected camera"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: Binding<String>(
                        get: { camera.currentDevice?.uniqueID ?? "" },
                        set: { newID in
                            if let device = camera.availableDevices.first(where: { $0.uniqueID == newID }) {
                                camera.selectDevice(device)
                            }
                        }
                    )) {
                        ForEach(camera.availableDevices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            HubToggleRow(
                title: localized("Horizontally mirrored image"),
                isOn: $camera.isMirrored
            )
            HubToggleRow(
                title: localized("Center Stage (Follow Frame)"),
                isOn: $camera.isCenterStageEnabled
            )
            HubToggleRow(
                title: localized("Studio Light (Face Enhancement)"),
                isOn: $camera.isStudioLightEnabled
            )
            HubToggleRow(
                title: localized("Portrait Mode (Soft Vignette)"),
                isOn: $camera.isPortraitEnabled
            )
            HubToggleRow(
                title: localized("Window border Ring Light"),
                isOn: $camera.isRingLightEnabled
            )
            HubToggleRow(
                title: localized("3×3 framing grid"),
                isOn: $camera.showGrid
            )
            HStack {
                Text(localized("Default lens zoom"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $camera.zoomFactor) {
                    Text("1.0×").tag(1.0)
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                }
                .labelsHidden()
                .frame(width: 140)
            }

        case .battery:
            HubToggleRow(
                title: localized("Show Mac thermal state (Nominal / Warm / High)"),
                isOn: $preferences.batteryShowThermalState
            )
            HubToggleRow(
                title: localized("Show battery health and maximum capacity"),
                isOn: $preferences.batteryShowCycleAndCapacity
            )
            HubToggleRow(
                title: localized("Show Live Activity when charging or low battery"),
                isOn: $preferences.showBatteryLiveActivity
            )

        case .bluetooth:
            HubToggleRow(
                title: localized("Hide disconnected paired devices"),
                isOn: $preferences.bluetoothHideDisconnected
            )
            HubToggleRow(
                title: localized("Show Mac battery percentage in Bluetooth bar"),
                isOn: $preferences.bluetoothShowMacBattery
            )

        case .shelf:
            HStack {
                Text(localized("When clicking a file in Shelf"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $preferences.shelfClickAction) {
                    ForEach(ShelfClickAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            HubStepperRow(
                title: localized("Maximum files in Shelf"),
                value: $preferences.shelfMaxItems,
                range: 4...30,
                step: 2,
                valueLabel: String(format: localized("%d files"), preferences.shelfMaxItems)
            )

        case .clipboard:
            HStack {
                Text(localized("When clicking a copied item"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $preferences.clipboardClickAction) {
                    ForEach(ClipboardClickAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            if preferences.clipboardClickAction == .paste {
                HubToggleRow(
                    title: localized("Automatically simulate ⌘V in active app"),
                    subtitle: localized("Requires Accessibility permission in System Settings"),
                    isOn: $preferences.clipboardAutoPaste
                )
            }
            HStack {
                Text(localized("History items limit"))
                    .font(.system(size: 12.5))
                Spacer()
                Picker("", selection: $preferences.clipboardHistoryLimit) {
                    Text(String(format: localized("%d items"), 25)).tag(25)
                    Text(String(format: localized("%d items"), 50)).tag(50)
                    Text(String(format: localized("%d items"), 100)).tag(100)
                    Text(String(format: localized("%d items"), 200)).tag(200)
                }
                .labelsHidden()
                .frame(width: 140)
            }

        case .teleprompter:
            HubToggleRow(
                title: localized("Keep Notch open during auto-scroll"),
                isOn: $preferences.teleprompterKeepOpenWhilePlaying
            )
            HubToggleRow(
                title: localized("Visual eye-contact focus guide (just below camera)"),
                isOn: $teleprompter.showFocusGuide
            )
            HubToggleRow(
                title: localized("Horizontal optical mirroring (flip text)"),
                isOn: $teleprompter.isMirrored
            )
            HubToggleRow(
                title: localized("Enable live FaceTime camera behind Teleprompter"),
                isOn: $teleprompter.isCameraEnabled
            )
            if teleprompter.isCameraEnabled {
                HubSliderRow(
                    title: localized("Background video dimming"),
                    value: $teleprompter.cameraDimming,
                    range: 0.15...0.85,
                    step: 0.05,
                    format: { "\(Int($0 * 100))%" }
                )
            }
            HubSliderRow(
                title: localized("Scroll speed"),
                value: $teleprompter.speed,
                range: 10...100,
                step: 5,
                format: { "\(Int($0)) pt/s" }
            )
            HubSliderRow(
                title: localized("Script font size"),
                value: $teleprompter.fontSize,
                range: 12...28,
                step: 1,
                format: { "\(Int($0)) pt" }
            )

        case .audio:
            HubToggleRow(
                title: localized("Prevent AirPods / Bluetooth from Hijacking Microphone"),
                isOn: Binding(
                    get: { AudioDeviceManager.shared.autoProtectMicrophoneOnBluetooth },
                    set: { AudioDeviceManager.shared.autoProtectMicrophoneOnBluetooth = $0 }
                )
            )
            HubToggleRow(
                title: localized("Automatically switch to default output device when connected"),
                isOn: Binding(
                    get: { AudioDeviceManager.shared.autoSwitchPreferredOutput },
                    set: { AudioDeviceManager.shared.autoSwitchPreferredOutput = $0 }
                )
            )
        }
    }
}

private extension NotchTab {
    var settingsSubtitle: String {
        switch self {
        case .home: return localized("Home dashboard with smart cards")
        case .music: return localized("Current track, artwork, visualizer, and media controls")
        case .audio: return localized("Per-application volume mixer, persistent default microphone lock (anti-AirPods hijack), input gain, and default headphones.")
        case .timer: return localized("Countdown timer and stopwatch with laps")
        case .calendar: return localized("Upcoming events and quick meeting join")
        case .reminders: return localized("Tasks and reminders synchronized with macOS")
        case .mirror: return localized("FaceTime camera mirror with Studio Light, Portrait, and Zoom")
        case .battery: return localized("Charge, thermal state, and power health")
        case .bluetooth: return localized("Connected accessories, AirPods, and battery level")
        case .shelf: return localized("Temporary file shelf and AirDrop sharing")
        case .clipboard: return localized("Smart clipboard history for text, links, colors, and images")
        case .teleprompter: return localized("MacBook camera-aligned reading with auto-scroll and notes")
        }
    }
}

struct NotchLiveActivitySection: View {
    @Bindable private var preferences = NotchPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("When two activities occur simultaneously"))
                        .font(.system(size: 12.5))
                    Text(localized("Configures how closed notch displays simultaneous activities"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $preferences.liveActivityLayout) {
                    ForEach(LiveActivityLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            Divider()

            Text(localized("Closed Notch Priority Order"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(preferences.liveActivityPriority, id: \.self) { kind in
                HStack(spacing: 10) {
                    ReorderGrip()
                    HubSettingRowLabel(title: kind.title, subtitle: kind.subtitle, systemImage: kind.iconName, tint: kind.tint)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferences.isLiveActivityEnabled(kind) },
                        set: { preferences.setLiveActivity(kind, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .reorderableItem(scope: "notch-live-activity", item: kind, items: preferences.liveActivityPriority) { preferences.liveActivityPriority = $0 }
            }

            Divider()

            HubToggleRow(
                title: localized("Keep paused timer visible on closed notch"),
                isOn: $preferences.showPausedTimerActivity
            )
            HubStepperRow(
                title: localized("Show upcoming meeting in advance"),
                value: $preferences.calendarLiveActivityLeadMinutes,
                range: 0...60,
                step: 5,
                valueLabel: String(format: localized("%d min"), preferences.calendarLiveActivityLeadMinutes)
            )
            HubToggleRow(
                title: localized("Alert on track change (Peek)"),
                isOn: $preferences.showTrackChangePeek
            )
            HubToggleRow(
                title: localized("Alert when timer completes (Peek)"),
                isOn: $preferences.showTimerCompletionPeek
            )
            HubToggleRow(
                title: localized("Alert on rate-limit reset (Peek)"),
                isOn: $preferences.showQuotaResetPeek
            )
            HubToggleRow(
                title: localized("Alert on CPU spike and thermal pressure (Peek)"),
                isOn: $preferences.showSystemAlertPeek
            )
        }
    }
}

struct NotchFocusSettings: View {
    @Bindable private var preferences = NotchPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Sync Pomodoro with macOS Focus"),
                subtitle: localized("Turns a Focus on during 🍅 focus sessions and off on breaks, pause, or reset"),
                isOn: $preferences.focusModeEnabled
            )
            if preferences.focusModeEnabled {
                focusField(
                    title: localized("Shortcut to enable Focus"),
                    placeholder: localized("Shortcut name"),
                    text: $preferences.focusEnterShortcut
                )
                focusField(
                    title: localized("Shortcut to disable Focus"),
                    placeholder: localized("Shortcut name"),
                    text: $preferences.focusExitShortcut
                )
                Text(localized("Create both in the Shortcuts app using the “Set Focus” action. macOS offers no direct API to change Focus."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HubToggleRow(
                    title: localized("Block distracting apps during focus"),
                    subtitle: localized("Hides the listed apps while a focus session runs"),
                    isOn: $preferences.focusBlockDistractions
                )
                if preferences.focusBlockDistractions {
                    focusField(
                        title: localized("Blocked app bundle IDs (comma separated)"),
                        placeholder: NotchPreferences.defaultFocusBlockedApps,
                        text: $preferences.focusBlockedApps
                    )
                }
            }
        }
    }

    private func focusField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 12.5))
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }
}
