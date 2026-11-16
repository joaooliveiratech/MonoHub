import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NotchContainerView: View {
    private let preferences = NotchPreferences.shared
    private let center = LiveActivityCenter.shared

    let screen: NSScreen
    @Binding var isExpanded: Bool

    @State private var languageRawValue: String = PreferencesManager.shared.language.rawValue
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var collapseTask: Task<Void, Never>?

    init(screen: NSScreen, isExpanded: Binding<Bool>) {
        self.screen = screen
        self._isExpanded = isExpanded
    }

    private var geometry: ScreenNotchGeometry {
        DisplayManager.calculateGeometry(for: screen, preferences: preferences)
    }

    private var closedMetrics: ClosedNotchMetrics {
        center.metrics(for: geometry)
    }

    private var isHoverBounceActive: Bool {
        isHovering && !isExpanded && preferences.dynamicIslandHoverBounce
    }

    private var currentWidth: CGFloat {
        if isExpanded { return preferences.openNotchWidth }
        return closedMetrics.width + (isHoverBounceActive ? 12 : 0)
    }

    private var effectiveHeaderHeight: CGFloat {
        if geometry.hasHardwareNotch && preferences.hardwareNotchTabBarStyle == .splitEars {
            return max(geometry.notchHeight, 36)
        }
        return geometry.expandedHeaderHeight
    }

    private var expandedTargetHeight: CGFloat {
        preferences.effectiveExpandedHeight(for: preferences.resolvedActiveTab, headerHeight: effectiveHeaderHeight)
    }

    private var currentHeight: CGFloat {
        if isExpanded {
            return expandedTargetHeight
        }
        return closedMetrics.height + (isHoverBounceActive ? 2 : 0)
    }

    private var isFlushWithHardwareNotch: Bool {
        geometry.hasHardwareNotch && !isExpanded && !isHoverBounceActive && closedMetrics.width <= geometry.notchWidth + 2
    }

    private var topRadius: CGFloat {
        isExpanded ? 0 : preferences.closedTopCornerRadius
    }

    private var bottomRadius: CGFloat {
        if isExpanded { return preferences.openCornerRadius }
        return center.isPeekEffective(for: center.peek) ? max(preferences.closedBottomCornerRadius, 18) : preferences.closedBottomCornerRadius
    }

    private var earRadius: CGFloat {
        if isExpanded { return NotchTheme.expandedEarRadius }
        return geometry.hasHardwareNotch ? preferences.closedTopCornerRadius : 0
    }

    private var shapeWidth: CGFloat {
        currentWidth + earRadius * 2
    }

    private var currentAnimation: Animation {
        isExpanded ? NotchTheme.expand : NotchTheme.collapse
    }

    private var showsBubble: Bool {
        !isExpanded && closedMetrics.hasBubble && (center.secondary != nil || closedMetrics.hasAnimationBubble)
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchBody
                .overlay(alignment: .topTrailing) {
                    if showsBubble {
                        if closedMetrics.hasAnimationBubble {
                            animationBubble
                                .offset(x: closedMetrics.animationBubbleWidth + closedMetrics.bubbleSpacing - earRadius)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity),
                                        removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)
                                    )
                                )
                        } else if let secondary = center.secondary {
                            bubble(for: secondary)
                                .offset(x: closedMetrics.bubbleDiameter + closedMetrics.bubbleSpacing - earRadius)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity),
                                        removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id(languageRawValue)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            languageRawValue = PreferencesManager.shared.language.rawValue
        }
        .animation(currentAnimation, value: isExpanded)
        .animation(NotchTheme.activity, value: closedMetrics)
        .animation(NotchTheme.activity, value: showsBubble)
        .animation(NotchTheme.islandBounce, value: isHovering)
        .animation(NotchTheme.content, value: preferences.resolvedActiveTab)
        .animation(NotchTheme.content, value: expandedTargetHeight)
    }

    private var notchShape: NotchShape {
        NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, earRadius: earRadius)
    }

    private var ambientTint: Color {
        if isExpanded {
            return preferences.resolvedActiveTab.accentColor
        }
        if let primary = center.primary {
            return primary.tint
        }
        if preferences.idleAnimation != .none {
            return preferences.idleAnimation.accentColor
        }
        return .clear
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            notchShape
                .fill(NotchTheme.notchFill)
                .shadow(
                    color: .black.opacity(preferences.showNotchShadow && !isFlushWithHardwareNotch ? (isExpanded ? 0.72 : (isHoverBounceActive ? 0.50 : 0.35)) : 0),
                    radius: isExpanded ? 28 : (isHoverBounceActive ? 12 : 8),
                    x: 0,
                    y: isExpanded ? 14 : (isHoverBounceActive ? 5 : 3)
                )

            if isExpanded {
                notchShape
                    .fill(
                        RadialGradient(
                            colors: [
                                ambientTint.opacity(0.11),
                                ambientTint.opacity(0.03),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 8,
                            endRadius: 240
                        )
                    )
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .top) {
                if isExpanded {
                    ExpandedNotchView(
                        headerHeight: effectiveHeaderHeight,
                        physicalNotchHeight: geometry.notchHeight,
                        notchGap: geometry.expandedNotchGap,
                        width: preferences.openNotchWidth
                    ) {
                        collapse()
                    }
                    .frame(width: preferences.openNotchWidth, height: expandedTargetHeight, alignment: .top)
                    .transition(.expandedNotchMorph)
                } else {
                    ClosedNotchView(
                        hasHardwareNotch: geometry.hasHardwareNotch,
                        physicalNotchWidth: geometry.notchWidth,
                        metrics: ClosedNotchMetrics(
                            width: currentWidth,
                            height: currentHeight,
                            baseHeight: closedMetrics.baseHeight + (isHoverBounceActive ? 2 : 0),
                            bubbleDiameter: closedMetrics.bubbleDiameter,
                            bubbleSpacing: closedMetrics.bubbleSpacing,
                            hasAnimationBubble: closedMetrics.hasAnimationBubble,
                            animationBubbleWidth: closedMetrics.animationBubbleWidth
                        ),
                        onTapPrimary: {
                            openActivity(center.primary)
                        },
                        onTapSecondary: {
                            openActivity(center.secondary ?? center.primary)
                        }
                    )
                    .frame(width: currentWidth, height: currentHeight, alignment: .top)
                    .transition(.closedNotchMorph)
                }
            }
            .frame(width: shapeWidth, height: currentHeight, alignment: .top)
            .clipShape(notchShape)

            if preferences.showNotchBorder && !isFlushWithHardwareNotch {
                notchShape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isExpanded ? 0.22 : (isHoverBounceActive ? 0.22 : 0.12)),
                                ambientTint.opacity(isExpanded ? 0.16 : 0.06),
                                Color.white.opacity(isExpanded ? 0.08 : 0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: shapeWidth, height: currentHeight)
        .contentShape(notchShape)
        .onHover { hovering in
            handleHover(hovering)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard preferences.enableShelfModule else { return false }
            withAnimation(NotchTheme.expand) {
                preferences.selectTab(.shelf)
                isExpanded = true
            }
            return ShelfManager.shared.handleDrop(providers: providers)
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if !isExpanded {
                        let playback = MediaPlaybackManager.shared
                        if value.translation.width > 30, playback.isAvailable {
                            playback.nextTrack()
                            NotchHaptics.tap()
                        } else if value.translation.width < -30, playback.isAvailable {
                            playback.previousTrack()
                            NotchHaptics.tap()
                        } else if value.translation.height > 30 {
                            expand()
                        }
                    } else {
                        if value.translation.height < -30 && abs(value.translation.height) > abs(value.translation.width) {
                            collapse()
                        } else if abs(value.translation.width) > 40 && abs(value.translation.width) > abs(value.translation.height) {
                            switchAdjacentTab(step: value.translation.width < 0 ? 1 : -1)
                        }
                    }
                }
        )
    }

    private func bubble(for kind: LiveActivityKind) -> some View {
        let d = closedMetrics.bubbleDiameter
        return ZStack {
            Capsule(style: .continuous)
                .fill(NotchTheme.notchFill)
                .shadow(color: .black.opacity(preferences.showNotchShadow ? 0.3 : 0), radius: 6, y: 2)
            if preferences.showNotchBorder {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            LiveActivityMinimalView(kind: kind)
                .id(kind)
                .transition(.notchActivity)
        }
        .frame(width: d, height: d)
        .contentShape(Circle())
        .onTapGesture {
            openActivity(kind)
        }
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    private var animationBubble: some View {
        let w = closedMetrics.animationBubbleWidth
        let h = closedMetrics.bubbleDiameter
        return ZStack {
            Capsule(style: .continuous)
                .fill(NotchTheme.notchFill)
                .shadow(color: .black.opacity(preferences.showNotchShadow ? 0.3 : 0), radius: 6, y: 2)
            if preferences.showNotchBorder {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            NotchIdleAnimationView(
                animation: preferences.idleAnimation,
                speed: preferences.idleAnimationSpeed,
                hasHardwareNotch: false,
                physicalNotchWidth: 0,
                interactionMode: preferences.idleInteractionMode,
                compactSingleWing: true
            )
            .padding(.horizontal, 6)
        }
        .frame(width: w, height: h)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            openActivity(center.primary)
        }
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    private func expand() {
        center.dismissPeek()
        withAnimation(NotchTheme.expand) {
            isExpanded = true
        }
    }

    private func collapse() {
        NotchWindowController.shared.navigationGraceUntil = nil
        withAnimation(NotchTheme.collapse) {
            isExpanded = false
        }
    }

    private func switchAdjacentTab(step: Int) {
        let tabs = preferences.availableTabs
        guard tabs.count > 1, let currentIdx = tabs.firstIndex(of: preferences.resolvedActiveTab) else { return }
        let nextIdx = max(0, min(tabs.count - 1, currentIdx + step))
        guard nextIdx != currentIdx else { return }
        NotchHaptics.tap()
        withAnimation(NotchTheme.content) {
            preferences.selectTab(tabs[nextIdx])
        }
    }

    private func openActivity(_ kind: LiveActivityKind?) {
        if case .timerFinished = center.peek {
            preferences.selectTab(.timer)
        } else if case .quotaReset = center.peek {
            MainWindowController.shared.show(item: .aiQuota)
            return
        } else if case .thermalAlert = center.peek {
            MainWindowController.shared.show(item: .monitor)
            return
        } else if case .cpuPeak = center.peek {
            MainWindowController.shared.show(item: .monitor)
            return
        } else if kind == .aiQuota {
            MainWindowController.shared.show(item: .aiQuota)
            return
        } else if kind == .heavyProcess {
            MainWindowController.shared.show(item: .monitor)
            return
        } else if let kind, preferences.isTabEnabled(kind.destinationTab) {
            preferences.selectTab(kind.destinationTab)
        }
        NotchHaptics.tap()
        expand()
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering

        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            NotchWindowController.shared.navigationGraceUntil = nil

            if preferences.hoverToExpand && !isExpanded {
                hoverTask?.cancel()
                if preferences.hoverDelay <= 0.02 {
                    expand()
                } else {
                    let delay = preferences.hoverDelay
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        if !Task.isCancelled && isHovering && !isExpanded {
                            expand()
                        }
                    }
                }
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil

            if isExpanded {
                if NotchWindowController.shared.isMenuTracking {
                    return
                }

                let teleprompter = TeleprompterManager.shared
                if teleprompter.isPinned || (teleprompter.isPlaying && preferences.teleprompterKeepOpenWhilePlaying) {
                    return
                }

                collapseTask?.cancel()
                collapseTask = Task { @MainActor in
                    while !Task.isCancelled && !isHovering && isExpanded {
                        if NotchWindowController.shared.isMenuTracking {
                            try? await Task.sleep(for: .milliseconds(150))
                            continue
                        }

                        let mouseLoc = NSEvent.mouseLocation
                        let inCorridor = self.isMouseInExpandedCorridor(mouseLoc)
                        let graceUntil = NotchWindowController.shared.navigationGraceUntil
                        let isGraceActive = graceUntil != nil && Date() < graceUntil!

                        if inCorridor && isGraceActive {
                            try? await Task.sleep(for: .milliseconds(80))
                            continue
                        }

                        NotchWindowController.shared.navigationGraceUntil = nil
                        let delay = preferences.autoCollapseDelay
                        if delay > 0.01 {
                            try? await Task.sleep(for: .seconds(delay))
                        }
                        if !Task.isCancelled && !isHovering && isExpanded && !NotchWindowController.shared.isMenuTracking {
                            let tp = TeleprompterManager.shared
                            if !(tp.isPinned || (tp.isPlaying && preferences.teleprompterKeepOpenWhilePlaying)) {
                                collapse()
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private func isMouseInExpandedCorridor(_ mouseLoc: NSPoint) -> Bool {
        let screenFrame = screen.frame
        let midX = screenFrame.midX
        let halfWidth = (preferences.openNotchWidth / 2) + 30
        let isHorizontalMatch = mouseLoc.x >= (midX - halfWidth) && mouseLoc.x <= (midX + halfWidth)
        let previousH = max(NotchWindowController.shared.previousExpandedHeight, preferences.openNotchHeight)
        let minY = screenFrame.maxY - (previousH + 30)
        let isVerticalMatch = mouseLoc.y <= screenFrame.maxY + 5 && mouseLoc.y >= minY
        return isHorizontalMatch && isVerticalMatch
    }
}
