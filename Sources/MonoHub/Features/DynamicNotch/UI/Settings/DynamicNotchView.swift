import SwiftUI
import AppKit

enum NotchSettingsSectionID: String, CaseIterable, Identifiable {
    case idleAnimations
    case modules
    case general
    case liveActivities
    case appearance
    case displays
    case systemHUD
    case exclusions

    var id: String { rawValue }
}

struct DynamicNotchView: View {
    private let windowController = NotchWindowController.shared
    @Bindable private var preferences = NotchPreferences.shared

    @State private var expandedSections: Set<NotchSettingsSectionID> = []
    @State private var filterText = ""

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AccordionOverviewBanner(
                    title: localized("Dynamic Notch Center"),
                    systemImage: "slider.horizontal.below.square.and.square.filled"
                )

                HubAccordionSection(
                    title: localized("Notch Animations (Nerd & Interactive Mode)"),
                    subtitle: localized("Bongo Cat, Lord of the Rings, Samurai, Star Wars, Pokémon, Pac-Man and live activity split"),
                    badgeText: preferences.idleAnimation == .none ? localized("Disabled") : "\(preferences.idleAnimation.title) • \(preferences.idleInteractionMode.shortTitle)",
                    badgeColor: preferences.idleAnimation.accentColor,
                    systemImage: preferences.idleAnimation == .none ? "sparkles" : preferences.idleAnimation.iconName,
                    tint: preferences.idleAnimation == .none ? .purple : preferences.idleAnimation.accentColor,
                    isExpanded: $expandedSections.contains(.idleAnimations)
                ) {
                    NotchIdleAnimationSection()
                }

                HubAccordionSection(
                    title: localized("Modules, Tabs and Customization"),
                    subtitle: localized("Enable, reorder, and expand each module to configure its features"),
                    badgeText: localized("%d of %d active", preferences.availableTabs.count, NotchTab.allCases.count),
                    badgeColor: .blue,
                    systemImage: "square.grid.2x2.fill",
                    tint: .blue,
                    isExpanded: $expandedSections.contains(.modules)
                ) {
                    NotchModulesSection()
                }

                HubAccordionSection(
                    title: localized("Interaction and General Behavior"),
                    subtitle: localized("Hover to expand, scroll gestures, tab labels, and haptic feedback"),
                    badgeText: preferences.hoverToExpand ? localized("Hover (%@)", String(format: "%.2fs", preferences.hoverDelay)) : localized("On click"),
                    badgeColor: .teal,
                    systemImage: "hand.point.up.left.fill",
                    tint: .teal,
                    isExpanded: $expandedSections.contains(.general)
                ) {
                    NotchGeneralSection()
                }

                HubAccordionSection(
                    title: localized("Live Activities (Dynamic Island)"),
                    subtitle: localized("Priority between Music, Timer, Calendar, and Battery when notch is closed"),
                    badgeText: preferences.liveActivityLayout.title,
                    badgeColor: .pink,
                    systemImage: "waveform.badge.magnifyingglass",
                    tint: .pink,
                    isExpanded: $expandedSections.contains(.liveActivities)
                ) {
                    NotchLiveActivitySection()
                }

                HubAccordionSection(
                    title: localized("Size, MacBook Layout and Appearance"),
                    subtitle: localized("MacBook hardware notch optimization, expanded dimensions, corners, and shadow"),
                    badgeText: localized("%d pt", Int(preferences.openNotchWidth)),
                    badgeColor: .indigo,
                    systemImage: "macbook",
                    tint: .indigo,
                    isExpanded: $expandedSections.contains(.appearance)
                ) {
                    NotchSizeSection()
                }

                HubAccordionSection(
                    title: localized("Displays and Monitors"),
                    subtitle: localized("Choose which displays show the hardware or virtual notch"),
                    badgeText: preferences.displayTargetMode.localizedTitle,
                    badgeColor: .cyan,
                    systemImage: "display.2",
                    tint: .cyan,
                    isExpanded: $expandedSections.contains(.displays)
                ) {
                    NotchDisplaySection()
                }

                HubAccordionSection(
                    title: localized("Volume & Brightness HUD"),
                    subtitle: localized("Replace default macOS HUD with a compact indicator inside the notch"),
                    badgeText: preferences.enableSystemHUD ? localized("Enabled") : localized("Disabled"),
                    badgeColor: preferences.enableSystemHUD ? .green : .secondary,
                    systemImage: "speaker.wave.3.fill",
                    tint: .green,
                    isExpanded: $expandedSections.contains(.systemHUD)
                ) {
                    NotchHUDSection()
                }

                HubAccordionSection(
                    title: localized("Excluded Apps and Fullscreen"),
                    subtitle: localized("Automatically hide the notch in fullscreen or specific applications"),
                    badgeText: localized("%d excluded", preferences.excludedAppBundleIDs.count),
                    badgeColor: .orange,
                    systemImage: "eye.slash.fill",
                    tint: .orange,
                    isExpanded: $expandedSections.contains(.exclusions)
                ) {
                    NotchExclusionSection()
                }

                NotchResetSection()
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    windowController.toggleExpanded()
                } label: {
                    Label(
                        windowController.isExpanded ? localized("Stop preview") : localized("Preview notch"),
                        systemImage: windowController.isExpanded ? "stop.fill" : "play.fill"
                    )
                }
                .help(windowController.isExpanded ? localized("Collapse notch on all displays") : localized("Expand notch on all displays"))

                AccordionExpandToolbarButton(expandedSections: $expandedSections)
            }
        }
        .accordionFilter($filterText)
    }
}
