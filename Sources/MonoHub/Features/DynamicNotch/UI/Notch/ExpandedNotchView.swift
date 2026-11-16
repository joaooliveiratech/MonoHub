import SwiftUI

struct ExpandedNotchView: View {
    private let preferences = NotchPreferences.shared
    private let center = LiveActivityCenter.shared
    private let teleprompter = TeleprompterManager.shared
    @Namespace private var tabNamespace
    let headerHeight: CGFloat
    let physicalNotchHeight: CGFloat
    let notchGap: CGFloat
    let width: CGFloat
    let onCollapse: () -> Void

    private static let pillWidth: CGFloat = 32
    private static let pillSpacing: CGFloat = 2
    private static let utilityWidth: CGFloat = 26
    private static let utilitySpacing: CGFloat = 5
    private static let selectedLabelWidth: CGFloat = 64
    private static let earInnerMargin: CGFloat = 6

    init(
        headerHeight: CGFloat = 44,
        physicalNotchHeight: CGFloat = 32,
        notchGap: CGFloat = 0,
        width: CGFloat = 620,
        onCollapse: @escaping () -> Void
    ) {
        self.headerHeight = headerHeight
        self.physicalNotchHeight = physicalNotchHeight
        self.notchGap = notchGap
        self.width = width
        self.onCollapse = onCollapse
    }

    private var availableTabs: [NotchTab] {
        preferences.availableTabs
    }

    private var selectedTab: NotchTab {
        preferences.resolvedActiveTab
    }

    private var hasHardwareNotch: Bool {
        notchGap > 0
    }

    private var usesUnifiedBelowNotchBar: Bool {
        hasHardwareNotch && preferences.hardwareNotchTabBarStyle == .belowNotch && headerHeight >= physicalNotchHeight + 28
    }

    private var earWidth: CGFloat {
        max(0, (width - notchGap) / 2 - NotchTheme.horizontalPadding - Self.earInnerMargin)
    }

    private var leadingTabs: [NotchTab] {
        Array(availableTabs.prefix((availableTabs.count + 1) / 2))
    }

    private var trailingTabs: [NotchTab] {
        Array(availableTabs.dropFirst((availableTabs.count + 1) / 2))
    }

    private func stripWidth(_ count: Int) -> CGFloat {
        CGFloat(count) * Self.pillWidth + CGFloat(max(0, count - 1)) * Self.pillSpacing
    }

    private var utilitiesWidth: CGFloat {
        Self.utilityWidth * 3 + Self.utilitySpacing * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .frame(height: headerHeight)

            ZStack(alignment: .topLeading) {
                tabContentView(for: selectedTab)
                    .id(selectedTab)
                    .transition(.notchTab(direction: preferences.tabTransitionDirection))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .animation(NotchTheme.content, value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var headerBar: some View {
        if usesUnifiedBelowNotchBar {
            VStack(spacing: 0) {

                HStack(spacing: 0) {
                    hardwareLeftEarBadge
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(width: notchGap)
                        .allowsHitTesting(false)

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        hardwareRightEarStatus
                        utilityButtons
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: max(physicalNotchHeight, 32))
                .padding(.horizontal, NotchTheme.horizontalPadding)

                HStack(spacing: 8) {
                    tabStrip(availableTabs, capacity: width - NotchTheme.horizontalPadding * 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: max(30, headerHeight - max(physicalNotchHeight, 32)))
                .padding(.horizontal, NotchTheme.horizontalPadding)
            }
        } else if hasHardwareNotch {

            HStack(spacing: 0) {
                tabStrip(leadingTabs, capacity: earWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: notchGap)
                    .allowsHitTesting(false)

                HStack(spacing: Self.utilitySpacing) {
                    tabStrip(trailingTabs, capacity: max(60, earWidth - utilitiesWidth - Self.utilitySpacing))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    utilityButtons
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, NotchTheme.horizontalPadding)
        } else {

            HStack(spacing: 10) {
                tabStrip(availableTabs, capacity: width - NotchTheme.horizontalPadding * 2 - utilitiesWidth - 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                utilityButtons
            }
            .padding(.horizontal, NotchTheme.horizontalPadding)
        }
    }

    private var hardwareLeftEarBadge: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(selectedTab.accentColor.opacity(0.20))
                    .frame(width: 20, height: 20)
                Image(systemName: selectedTab.iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selectedTab.accentColor)
            }

            Text(selectedTab.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            if let primary = center.primary, primary.destinationTab != selectedTab {
                Button {
                    NotchHaptics.tap()
                    withAnimation(NotchTheme.content) {
                        preferences.selectTab(primary.destinationTab)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(primary.tint)
                            .frame(width: 5, height: 5)
                        LiveActivityCompactTrailing(kind: primary)
                            .scaleEffect(0.88)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(localized("Go to live activity"))
            }
        }
    }

    @ViewBuilder
    private var hardwareRightEarStatus: some View {
        TimelineView(.everyMinute) { context in
            Text(NotchFormatters.shortTime.string(from: context.date))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func tabStrip(_ tabs: [NotchTab], capacity: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.pillSpacing) {
                    ForEach(tabs) { tab in
                        let isSelected = selectedTab == tab
                        NotchTabPillButton(
                            tab: tab,
                            isSelected: isSelected,
                            hasLiveActivity: !isSelected && isTabActivityRunning(tab),
                            showLabel: shouldShowLabel(for: tab, isSelected: isSelected, in: tabs, capacity: capacity),
                            namespace: tabNamespace
                        ) {
                            guard !isSelected else { return }
                            NotchHaptics.tap()
                            withAnimation(NotchTheme.content) {
                                preferences.selectTab(tab)
                            }
                        }
                        .id(tab)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if tabs.contains(selectedTab) {
                    proxy.scrollTo(selectedTab, anchor: .center)
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                guard tabs.contains(newTab) else { return }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
    }

    private var utilityButtons: some View {
        HStack(spacing: Self.utilitySpacing) {
            NotchHeaderIconButton(
                systemName: teleprompter.isPinned ? "pin.fill" : "pin",
                tint: teleprompter.isPinned ? .orange : nil,
                helpText: teleprompter.isPinned ? localized("Unpin Notch (collapse on mouse exit)") : localized("Pin Notch open")
            ) {
                NotchHaptics.tap()
                teleprompter.isPinned.toggle()
            }

            NotchHeaderIconButton(
                systemName: "gearshape.fill",
                helpText: localized("Notch Settings")
            ) {
                NotchHaptics.tap()
                NotchStatusItemController.openSettings()
            }

            NotchHeaderIconButton(
                systemName: "chevron.up",
                helpText: localized("Collapse notch")
            ) {
                NotchHaptics.tap()
                teleprompter.isPinned = false
                onCollapse()
            }
        }
    }

    private func shouldShowLabel(for tab: NotchTab, isSelected: Bool, in tabs: [NotchTab], capacity: CGFloat) -> Bool {
        let labelsFit = stripWidth(tabs.count) + Self.selectedLabelWidth <= capacity
        switch preferences.tabLabelStyle {
        case .selectedOnly:
            return isSelected && labelsFit
        case .always:
            return stripWidth(tabs.count) + CGFloat(tabs.count) * Self.selectedLabelWidth <= capacity
        case .iconsOnly:
            return false
        }
    }

    private func isTabActivityRunning(_ tab: NotchTab) -> Bool {
        let active = LiveActivityCenter.shared.activities
        switch tab {
        case .music: return active.contains(.music)
        case .timer: return active.contains(.timer)
        case .calendar: return active.contains(.calendar)
        case .battery: return active.contains(.battery)
        case .shelf: return !ShelfManager.shared.items.isEmpty
        case .clipboard: return !ClipboardManager.shared.items.isEmpty
        case .teleprompter: return TeleprompterManager.shared.isPlaying
        default: return false
        }
    }

    @ViewBuilder
    private func tabContentView(for tab: NotchTab) -> some View {
        switch tab {
        case .home:
            HomeDashboardView()
        case .music:
            MusicPlayerView()
        case .audio:
            NotchAudioMixerView()
        case .timer:
            TimerView()
        case .calendar:
            CalendarView()
        case .reminders:
            RemindersView()
        case .mirror:
            CameraMirrorView()
        case .battery:
            BatteryView()
        case .bluetooth:
            BluetoothView()
        case .shelf:
            ShelfView()
        case .clipboard:
            ClipboardView()
        case .teleprompter:
            TeleprompterView()
        }
    }
}

private struct NotchTabPillButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let hasLiveActivity: Bool
    let showLabel: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5.5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? tab.accentColor : (isHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.62)))
                        .symbolEffect(.bounce.down, value: isSelected)

                    if hasLiveActivity {
                        Circle()
                            .fill(tab.accentColor)
                            .frame(width: 4.5, height: 4.5)
                            .offset(x: 3, y: -2)
                    }
                }

                if showLabel {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .padding(.horizontal, showLabel ? 11 : 8.5)
            .frame(minWidth: 32, minHeight: 28)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    tab.accentColor.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.28),
                                            tab.accentColor.opacity(0.32)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: tab.accentColor.opacity(0.22), radius: 6, y: 1)
                        .matchedGeometryEffect(id: "tab_selection_pill", in: namespace)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.10 : 0.001))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                isHovered = hovering
            }
        }
        .help(tab.title)
    }
}

private struct NotchHeaderIconButton: View {
    let systemName: String
    var tint: Color? = nil
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint ?? Color.white.opacity(isHovered ? 0.98 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill((tint ?? Color.white).opacity(tint != nil ? 0.22 : (isHovered ? 0.18 : 0.09)))
                        .overlay(
                            Circle()
                                .strokeBorder((tint ?? Color.white).opacity(tint != nil ? 0.45 : (isHovered ? 0.24 : 0.08)), lineWidth: 0.75)
                        )
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .help(helpText)
    }
}
