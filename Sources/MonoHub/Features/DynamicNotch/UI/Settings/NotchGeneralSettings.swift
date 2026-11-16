import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum NotchIdlePreviewStyle: String, CaseIterable {
    case continuous
    case hardwareCutout
    case sharedWithMusic
}

struct NotchIdleAnimationSection: View {
    @Bindable private var preferences = NotchPreferences.shared
    @State private var previewStyle: NotchIdlePreviewStyle = DisplayManager.shared.hasPhysicalNotch ? .hardwareCutout : .continuous

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(preferences.idleAnimation.accentColor)
                        Text(localized("Live Preview"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize()
                    }

                    Spacer(minLength: 4)

                    if preferences.idleAnimation != .none && preferences.idleInteractionMode != .alwaysActive {
                        Button {
                            IdleInteractionMonitor.shared.simulateTypingBurst(strokes: 8)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(localized("Test Keypress"))
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            )
                            .foregroundStyle(Color.accentColor)
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }

                    HStack(spacing: 2) {
                        previewModePill(title: localized("Continuous"), isSelected: previewStyle == .continuous) {
                            previewStyle = .continuous
                        }
                        previewModePill(title: "MacBook", isSelected: previewStyle == .hardwareCutout) {
                            previewStyle = .hardwareCutout
                        }
                        previewModePill(title: localized("Music + Animation"), isSelected: previewStyle == .sharedWithMusic) {
                            previewStyle = .sharedWithMusic
                        }
                    }
                    .padding(2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
                    .fixedSize()
                }
                .frame(height: 24)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.15, blue: 0.22),
                                    Color(red: 0.07, green: 0.08, blue: 0.13)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 32)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    HStack(spacing: 6) {
                        ZStack {
                            NotchShape(topCornerRadius: 6, bottomCornerRadius: 13, earRadius: 6)
                                .fill(Color.black)
                                .shadow(color: .black.opacity(0.55), radius: 6, y: 2)

                            if previewStyle == .sharedWithMusic {
                                sharedActivityPreviewContent
                            } else if preferences.idleAnimation != .none {
                                NotchIdleAnimationView(
                                    animation: preferences.idleAnimation,
                                    speed: preferences.idleAnimationSpeed,
                                    hasHardwareNotch: previewStyle == .hardwareCutout,
                                    physicalNotchWidth: 112,
                                    interactionMode: preferences.idleInteractionMode
                                )
                                .padding(.horizontal, 10)
                            } else {
                                Text(localized("Discreet notch (no animation)"))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.horizontal, 14)
                            }

                            if previewStyle == .hardwareCutout || (previewStyle == .sharedWithMusic && DisplayManager.shared.hasPhysicalNotch) {
                                cameraCutoutBadge
                            }
                        }
                        .frame(width: previewPillWidth, height: 32)

                        if previewStyle == .sharedWithMusic && preferences.idleWithActivityMode == .detachedBubble && preferences.idleAnimation != .none {
                            ZStack {
                                Capsule(style: .continuous)
                                    .fill(Color.black)
                                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                    )
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
                            .frame(width: 52, height: 30)
                        }
                    }
                }
                .frame(height: 46)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Behavior and Interaction with Mac"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(NotchIdleInteractionMode.allCases) { mode in
                        let isSelected = preferences.idleInteractionMode == mode
                        Button {
                            preferences.idleInteractionMode = mode
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mode.shortTitle)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(mode == .interactive ? localized("Reacts to typing/clicks") : (mode == .alwaysActive ? localized("Animates continuously") : localized("Hides when idle")))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(preferences.idleInteractionMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Split with Music, Timer and Live Activities"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(NotchIdleWithActivityMode.allCases) { mode in
                        let isSelected = preferences.idleWithActivityMode == mode
                        Button {
                            preferences.idleWithActivityMode = mode
                            previewStyle = .sharedWithMusic
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.pink : .secondary)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? Color.pink.opacity(0.15) : Color.primary.opacity(0.05))
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mode.shortTitle)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(mode == .sideBySide ? localized("Music/Timer + Animation") : (mode == .detachedBubble ? localized("Bubble animation") : localized("Pauses during activity")))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Color.pink)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.pink.opacity(0.09) : Color.primary.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(isSelected ? Color.pink.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(preferences.idleWithActivityMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(localized("Nerd / Geek Animation Style"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(NotchIdleAnimation.allCases) { anim in
                    let isSelected = preferences.idleAnimation == anim
                    Button {
                        preferences.idleAnimation = anim
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? anim.accentColor : anim.accentColor.opacity(0.14))
                                    .frame(width: 28, height: 28)
                                Image(systemName: anim.iconName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.black : anim.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(anim.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(anim.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(anim.accentColor)
                                    .font(.system(size: 13.5))
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? anim.accentColor.opacity(0.11) : Color.primary.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(isSelected ? anim.accentColor.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: 1)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if preferences.idleAnimation != .none {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HubSliderRow(
                        title: localized("Animation speed"),
                        subtitle: localized("Adjusts base pace of movements and effects"),
                        value: $preferences.idleAnimationSpeed,
                        range: 0.5...2.5,
                        step: 0.1,
                        format: { String(format: "%.1fx", $0) }
                    )

                    HubToggleRow(
                        title: localized("Show on sides of MacBook physical Notch"),
                        subtitle: localized("Expands small wings around camera when notch is closed"),
                        isOn: $preferences.showIdleOnHardwareNotch
                    )

                    if preferences.showIdleOnHardwareNotch {
                        HubSliderRow(
                            title: localized("Width of each side wing on MacBook"),
                            subtitle: localized("Space reserved left and right of physical camera"),
                            value: $preferences.idleWingWidth.doubleValue,
                            range: 48...110,
                            step: 2,
                            format: { "\(Int($0)) pt" }
                        )
                    }
                }
            }
        }
    }

    private var previewPillWidth: CGFloat {
        switch previewStyle {
        case .continuous:
            return 220
        case .hardwareCutout:
            return 276
        case .sharedWithMusic:
            return DisplayManager.shared.hasPhysicalNotch ? 286 : 244
        }
    }

    private var cameraCutoutBadge: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(white: 0.06))
            .frame(width: 108, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
            )
            .overlay(
                HStack(spacing: 4) {
                    Circle().fill(Color.green.opacity(0.65)).frame(width: 4.5, height: 4.5)
                    Text(localized("Camera"))
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
            )
    }

    @ViewBuilder
    private var sharedActivityPreviewContent: some View {
        let hasCutout = DisplayManager.shared.hasPhysicalNotch
        HStack(spacing: 0) {

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 17, height: 17)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                EqualizerAnimationView(isAnimating: true, tint: .pink, maxHeight: 11)
            }
            .frame(maxWidth: .infinity, alignment: hasCutout ? .center : .leading)

            if hasCutout {
                Color.clear.frame(width: 112, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5, height: 14)
                    .padding(.horizontal, 8)
            }

            Group {
                if preferences.idleWithActivityMode == .sideBySide && preferences.idleAnimation != .none {
                    NotchIdleAnimationView(
                        animation: preferences.idleAnimation,
                        speed: preferences.idleAnimationSpeed,
                        hasHardwareNotch: false,
                        physicalNotchWidth: 0,
                        interactionMode: preferences.idleInteractionMode,
                        compactSingleWing: true
                    )
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("04:20")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: hasCutout ? .center : .trailing)
        }
        .padding(.horizontal, 10)
    }

    private func previewModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                        .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 2, y: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

struct NotchGeneralSection: View {
    @Bindable private var preferences = NotchPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Show shortcut icon in menu bar"),
                subtitle: localized("Allows opening or configuring Dynamic Notch from top of screen"),
                isOn: $preferences.showInMenuBar
            )

            Divider()

            HubToggleRow(
                title: localized("Expand automatically on cursor hover"),
                subtitle: localized("Opens notch panel when hovering mouse over it"),
                isOn: $preferences.hoverToExpand
            )

            if preferences.hoverToExpand {
                HubSliderRow(
                    title: localized("Hover delay to expand"),
                    subtitle: localized("Time required hovering over notch before expanding"),
                    value: $preferences.hoverDelay,
                    range: 0.05...1.0,
                    step: 0.05,
                    format: { String(format: "%.2f s", $0) }
                )
            }

            HubSliderRow(
                title: localized("Collapse delay"),
                subtitle: localized("Time before closing notch after cursor leaves"),
                value: $preferences.autoCollapseDelay,
                range: 0...0.8,
                step: 0.02,
                format: { $0 <= 0.01 ? localized("Immediate") : String(format: "%.2f s", $0) }
            )

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Action when scrolling over closed notch"))
                        .font(.system(size: 12.5))
                    Text(localized("Quick adjustment using two fingers on trackpad or mouse wheel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $preferences.scrollAction) {
                    ForEach(ScrollAction.allCases) { action in
                        Text(action.description).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Tab label display"))
                        .font(.system(size: 12.5))
                    Text(localized("Controls how titles appear on top bar of expanded notch"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $preferences.tabLabelStyle) {
                    ForEach(TabLabelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            Divider()

            HubToggleRow(
                title: localized("Dynamic Island hover bounce effect"),
                isOn: $preferences.dynamicIslandHoverBounce
            )

            HubToggleRow(
                title: localized("Haptic feedback on Trackpad (Haptics)"),
                isOn: $preferences.hapticFeedback
            )
        }
    }
}

struct NotchDisplaySection: View {
    @Bindable private var preferences = NotchPreferences.shared
    private let displayManager = DisplayManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Active displays"))
                        .font(.system(size: 12.5))
                    Text(localized("Choose where Dynamic Notch should be displayed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $preferences.displayTargetMode) {
                    ForEach(DisplayTargetMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            HubToggleRow(
                title: localized("Virtual notch on displays without physical cutout"),
                subtitle: localized("Creates dynamic island at top of external monitors or Macs without cutout"),
                isOn: $preferences.enableVirtualNotch
            )

            if !displayManager.screenInfos.isEmpty {
                Divider()

                ForEach(displayManager.screenInfos) { screen in
                    HStack {
                        screenLabel(screen)
                        Spacer()
                        if preferences.displayTargetMode == .custom {
                            Toggle("", isOn: Binding(
                                get: { preferences.customEnabledDisplayIDs.contains(screen.id) },
                                set: { preferences.setDisplayEnabled(id: screen.id, isEnabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        } else {
                            Text(screen.notchTypeDescription)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Hardware DDC/CI Display Control"))
                        .font(.system(size: 12.5, weight: .medium))
                    Text(localized("Configure hardware brightness, volume, and input switching for external screens"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Manage External Displays…")) {
                    MainWindowController.shared.show(item: .displayControl)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func screenLabel(_ screen: ScreenInfo) -> some View {
        HubSettingRowLabel(
            title: screen.name,
            subtitle: "\(screen.resolutionString) pt • \(screen.notchTypeDescription)",
            systemImage: screen.isBuiltin ? "laptopcomputer" : "display",
            tint: screen.isBuiltin ? .indigo : .teal
        )
    }
}

struct NotchExclusionSection: View {
    @Bindable private var preferences = NotchPreferences.shared
    @State private var runningApps: [AppMetadata] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Automatically hide in fullscreen applications"),
                subtitle: localized("Collapses and hides notch during full-screen videos, games, or presentations"),
                isOn: $preferences.hideInFullScreenApps
            )

            if !preferences.excludedAppBundleIDs.isEmpty {
                Divider()
                ForEach(preferences.excludedAppBundleIDs, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID) {
                        preferences.setAppExcluded(bundleID: bundleID, excluded: false)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Menu(localized("Add running application")) {
                    let available = runningApps.filter { !preferences.isAppExcluded(bundleID: $0.bundleIdentifier) }
                    if available.isEmpty {
                        Text(localized("No other running applications"))
                    } else {
                        ForEach(available) { app in
                            Button(app.name) {
                                preferences.setAppExcluded(bundleID: app.bundleIdentifier, excluded: true)
                            }
                        }
                    }
                }
                .fixedSize()
                .onAppear(perform: refreshRunningApps)

                Button(localized("Choose from Applications…"), action: chooseApplication)
                    .buttonStyle(.bordered)
                    .fixedSize()

                Spacer()
            }
        }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != AppInfo.bundleIdentifier }
            .compactMap { $0.bundleIdentifier.map { AppMetadata(bundleIdentifier: $0, iconSize: NSSize(width: 22, height: 22)) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = localized("Add")
        panel.message = localized("Select applications where notch should not appear")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier {
                preferences.setAppExcluded(bundleID: identifier, excluded: true)
            }
        }
    }
}

private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var reference: AppMetadata?

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference?.name ?? bundleID)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                if let icon = reference?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "app.dashed")
                }
            }
            Spacer()
            Button(localized("Remove"), action: onRemove)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .task(id: bundleID) {
            reference = AppMetadata(bundleIdentifier: bundleID, iconSize: NSSize(width: 22, height: 22))
        }
    }
}

struct NotchHUDSection: View {
    @Bindable private var preferences = NotchPreferences.shared
    private let interceptor = SystemHUDInterceptor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubToggleRow(
                title: localized("Replace system volume and brightness HUD"),
                subtitle: localized("Shows audio, brightness, and power changes integrated in the notch"),
                isOn: $preferences.enableSystemHUD
            )

            if preferences.enableSystemHUD {
                Divider()
                HStack {
                    Text(localized("Accessibility Permission"))
                        .font(.system(size: 12.5))
                    Spacer()
                    if interceptor.hasAccessibilityPermission {
                        Label(localized("Granted"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button(localized("Allow in Settings…")) {
                            interceptor.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            interceptor.checkAccessibility()
        }
    }
}

struct NotchSizeSection: View {
    @Bindable private var preferences = NotchPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localized("Tab bar on MacBook with physical Notch"))
                        .font(.system(size: 12.5))
                    Text(preferences.hardwareNotchTabBarStyle.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $preferences.hardwareNotchTabBarStyle) {
                    ForEach(HardwareNotchTabBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 250)
            }

            Divider()

            HubToggleRow(
                title: localized("Automatically adjust height to active module"),
                subtitle: localized("Adapts expanded panel height to each tab's content"),
                isOn: $preferences.autoAdjustHeight
            )

            if !preferences.autoAdjustHeight {
                HubSliderRow(
                    title: localized("Fixed expanded height"),
                    value: $preferences.openNotchHeight.doubleValue,
                    range: 160...380,
                    step: 5,
                    format: { "\(Int($0)) pt" }
                )
            }

            HubSliderRow(
                title: localized("Expanded notch width"),
                value: $preferences.openNotchWidth.doubleValue,
                range: 480...760,
                step: 10,
                format: { "\(Int($0)) pt" }
            )

            HubSliderRow(
                title: localized("Corner rounding"),
                value: $preferences.openCornerRadius.doubleValue,
                range: 16...32,
                step: 1,
                format: { "\(Int($0)) pt" }
            )

            Divider()

            HubSliderRow(
                title: localized("Closed virtual notch width"),
                subtitle: localized("Used on external displays without physical camera cutout"),
                value: $preferences.closedNotchWidth.doubleValue,
                range: 140...320,
                step: 5,
                format: { "\(Int($0)) pt" }
            )

            HubSliderRow(
                title: localized("Closed virtual notch height"),
                value: $preferences.closedNotchHeight.doubleValue,
                range: 24...44,
                step: 1,
                format: { "\(Int($0)) pt" }
            )

            Divider()

            HubToggleRow(
                title: localized("Show subtle glowing border"),
                isOn: $preferences.showNotchBorder
            )

            HubToggleRow(
                title: localized("Show drop shadow"),
                isOn: $preferences.showNotchShadow
            )
        }
    }
}

struct NotchResetSection: View {
    @State private var isConfirming = false

    var body: some View {
        HStack {
            Spacer()
            Button(localized("Restore notch defaults…"), role: .destructive) {
                isConfirming = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
                localized("Restore all notch settings?"),
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button(localized("Restore defaults"), role: .destructive) {
                    NotchPreferences.shared.resetToDefaults()
                }
                Button(localized("Cancel"), role: .cancel) {}
            } message: {
                Text(localized("Sizes, animations, modules, cards, live activities, displays and excluded apps return to default."))
            }
        }
        .padding(.top, 4)
    }
}
