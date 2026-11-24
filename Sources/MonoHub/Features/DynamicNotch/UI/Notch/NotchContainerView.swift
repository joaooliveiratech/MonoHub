import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NotchContainerView: View {
    private let preferences = NotchPreferences.shared
    private let center = LiveActivityCenter.shared

    let screen: NSScreen
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var languageRawValue: String = PreferencesManager.shared.language.rawValue
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var collapseTask: Task<Void, Never>?

    init(screen: NSScreen, isExpanded: Binding<Bool>) {
        self.screen = screen
        self._isExpanded = isExpanded
    }

    private func effectiveHeaderHeight(for geometry: ScreenNotchGeometry) -> CGFloat {
        if geometry.hasHardwareNotch && preferences.hardwareNotchTabBarStyle == .splitEars {
            return max(geometry.notchHeight, 36)
        }
        return geometry.expandedHeaderHeight
    }

    private func ambientTint(isExpanded: Bool) -> Color {
        if isExpanded {
            return preferences.resolvedActiveTab.accentColor
        }
        if let primary = center.primary {
            return primary.tint
        }
        if preferences.idleAnimation != .none {
            return preferences.idleAnimation.tint
        }
        return .clear
    }

    var body: some View {
        let geometry = DisplayManager.calculateGeometry(for: screen, preferences: preferences)
        let closedMetrics = center.metrics(for: geometry)
        let hoverBounceActive = isHovering && !isExpanded && preferences.dynamicIslandHoverBounce
        let headerHeight = effectiveHeaderHeight(for: geometry)
        let expandedTargetHeight = preferences.effectiveExpandedHeight(
            for: preferences.resolvedActiveTab,
            headerHeight: headerHeight
        )
        let currentWidth: CGFloat = isExpanded
            ? preferences.openNotchWidth
            : closedMetrics.width + (hoverBounceActive ? 12 : 0)
        let currentHeight: CGFloat = isExpanded
            ? expandedTargetHeight
            : closedMetrics.height + (hoverBounceActive ? 2 : 0)
        let isFlushWithHardwareNotch = geometry.hasHardwareNotch
            && !isExpanded
            && !hoverBounceActive
            && closedMetrics.width <= geometry.notchWidth + 2
        let topRadius: CGFloat = isExpanded ? 0 : preferences.closedTopCornerRadius
        let bottomRadius: CGFloat = isExpanded
            ? preferences.openCornerRadius
            : (center.isPeekEffective(for: center.peek) ? max(preferences.closedBottomCornerRadius, 18) : preferences.closedBottomCornerRadius)
        let earRadius: CGFloat = isExpanded
            ? NotchTheme.expandedEarRadius
            : (geometry.hasHardwareNotch ? preferences.closedTopCornerRadius : 0)
        let shapeWidth = currentWidth + earRadius * 2
        let shape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, earRadius: earRadius)
        let showsBubble = !isExpanded && closedMetrics.hasBubble && (center.secondary != nil || closedMetrics.hasAnimationBubble)
        let tint = ambientTint(isExpanded: isExpanded)
        let morphAnimation = NotchTheme.motion(isExpanded ? NotchTheme.expand : NotchTheme.collapse, reduced: reduceMotion)
        let activityAnimation = NotchTheme.motion(NotchTheme.activity, reduced: reduceMotion)

        ZStack(alignment: .top) {
            notchBody(
                geometry: geometry,
                closedMetrics: closedMetrics,
                headerHeight: headerHeight,
                expandedTargetHeight: expandedTargetHeight,
                currentWidth: currentWidth,
                currentHeight: currentHeight,
                shapeWidth: shapeWidth,
                shape: shape,
                isFlushWithHardwareNotch: isFlushWithHardwareNotch,
                hoverBounceActive: hoverBounceActive,
                ambientTint: tint
            )
            .overlay(alignment: .topTrailing) {
                if showsBubble {
                    if closedMetrics.hasAnimationBubble {
                        animationBubble(closedMetrics: closedMetrics)
                            .offset(x: closedMetrics.animationBubbleWidth + closedMetrics.bubbleSpacing - earRadius)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.25, anchor: .leading).combined(with: .opacity),
                                    removal: .scale(scale: 0.25, anchor: .leading).combined(with: .opacity)
                                )
                            )
                    } else if let secondary = center.secondary {
                        bubble(for: secondary, closedMetrics: closedMetrics)
                            .offset(x: closedMetrics.bubbleDiameter + closedMetrics.bubbleSpacing - earRadius)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.25, anchor: .leading).combined(with: .opacity),
                                    removal: .scale(scale: 0.25, anchor: .leading).combined(with: .opacity)
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
        .animation(morphAnimation, value: isExpanded)
        .animation(activityAnimation, value: closedMetrics)
        .animation(NotchTheme.motion(NotchTheme.islandBounce, reduced: reduceMotion), value: hoverBounceActive)
        .animation(NotchTheme.motion(NotchTheme.content, reduced: reduceMotion), value: expandedTargetHeight)
    }

    @ViewBuilder
    private func notchBackground(
        shape: NotchShape,
        isFlushWithHardwareNotch: Bool,
        hoverBounceActive: Bool,
        ambientTint: Color
    ) -> some View {
        let shadowOpacity: Double = preferences.showNotchShadow && !isFlushWithHardwareNotch
            ? (isExpanded ? 0.62 : (hoverBounceActive ? 0.44 : 0.32))
            : 0

        ZStack {
            if isExpanded && !reduceTransparency {
                // macOS 27 Liquid Glass dark obsidian backing: keeps true-black hardware notch blend
                // at top while refracting desktop wallpaper subtly through the expanded card
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.94),
                                Color.black.opacity(0.76)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .glassEffect(.regular.tint(.black.opacity(0.55)), in: shape)
            } else {
                shape.fill(NotchTheme.notchFill)
            }

            if isExpanded {
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                ambientTint.opacity(0.13),
                                ambientTint.opacity(0.035),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 10,
                            endRadius: 260
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: .black.opacity(shadowOpacity),
            radius: isExpanded ? 26 : (hoverBounceActive ? 12 : 7),
            x: 0,
            y: isExpanded ? 14 : (hoverBounceActive ? 5 : 3)
        )
    }

    private func notchBody(
        geometry: ScreenNotchGeometry,
        closedMetrics: ClosedNotchMetrics,
        headerHeight: CGFloat,
        expandedTargetHeight: CGFloat,
        currentWidth: CGFloat,
        currentHeight: CGFloat,
        shapeWidth: CGFloat,
        shape: NotchShape,
        isFlushWithHardwareNotch: Bool,
        hoverBounceActive: Bool,
        ambientTint: Color
    ) -> some View {
        ZStack(alignment: .top) {
            notchBackground(
                shape: shape,
                isFlushWithHardwareNotch: isFlushWithHardwareNotch,
                hoverBounceActive: hoverBounceActive,
                ambientTint: ambientTint
            )

            ZStack(alignment: .top) {
                if isExpanded {
                    ExpandedNotchView(
                        headerHeight: headerHeight,
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
                            baseHeight: closedMetrics.baseHeight + (hoverBounceActive ? 2 : 0),
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
            .clipShape(shape)

            if preferences.showNotchBorder && !isFlushWithHardwareNotch {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isExpanded ? 0.28 : (hoverBounceActive ? 0.24 : 0.14)),
                                ambientTint.opacity(isExpanded ? 0.20 : 0.08),
                                Color.white.opacity(isExpanded ? 0.11 : 0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: isExpanded ? 0.9 : 0.75
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: shapeWidth, height: currentHeight)
        .contentShape(shape)
        .onHover { hovering in
            handleHover(hovering)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard preferences.enableShelfModule else { return false }
            withAnimation(NotchTheme.motion(NotchTheme.expand, reduced: reduceMotion)) {
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

    @ViewBuilder
    private func bubbleSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let capsule = Capsule(style: .continuous)
        ZStack {
            if reduceTransparency {
                capsule.fill(NotchTheme.notchFill)
            } else {
                capsule
                    .fill(Color.black.opacity(0.84))
                    .glassEffect(.regular.tint(.black.opacity(0.60)), in: capsule)
            }
            if preferences.showNotchBorder {
                capsule.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
            content()
        }
        .shadow(color: .black.opacity(preferences.showNotchShadow ? 0.34 : 0), radius: 7, y: 2.5)
    }

    private func bubble(for kind: LiveActivityKind, closedMetrics: ClosedNotchMetrics) -> some View {
        let d = closedMetrics.bubbleDiameter
        return bubbleSurface {
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

    private func animationBubble(closedMetrics: ClosedNotchMetrics) -> some View {
        let w = closedMetrics.animationBubbleWidth
        let h = closedMetrics.bubbleDiameter
        return bubbleSurface {
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
        withAnimation(NotchTheme.motion(NotchTheme.expand, reduced: reduceMotion)) {
            isExpanded = true
        }
    }

    private func collapse() {
        NotchWindowController.shared.navigationGraceUntil = nil
        withAnimation(NotchTheme.motion(NotchTheme.collapse, reduced: reduceMotion)) {
            isExpanded = false
        }
    }

    private func switchAdjacentTab(step: Int) {
        let tabs = preferences.availableTabs
        guard tabs.count > 1, let currentIdx = tabs.firstIndex(of: preferences.resolvedActiveTab) else { return }
        let nextIdx = max(0, min(tabs.count - 1, currentIdx + step))
        guard nextIdx != currentIdx else { return }
        NotchHaptics.tap()
        withAnimation(NotchTheme.motion(NotchTheme.content, reduced: reduceMotion)) {
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
