import SwiftUI

struct SwitcherView: View {
    @Bindable var viewModel: SwitcherViewModel
    private let preferences = SwitcherPreferencesManager.shared
    private let permissions = SwitcherPermissionsManager.shared

    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onLayoutChange: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        viewModel: SwitcherViewModel,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onLayoutChange: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onLayoutChange = onLayoutChange
    }

    private var isFullscreen: Bool {
        preferences.isFullscreen
    }

    var body: some View {
        let accent = preferences.accent.color

        ZStack {
            if isFullscreen {
                dimmingLayer(opacity: 0.25)
            }

            if let sheet = viewModel.activeSheet {
                if isFullscreen {
                    mainPanel
                    dimmingLayer(opacity: 0.3)
                }
                sheetView(sheet)
                    .switcherSheetChrome(size: sheetSize(sheet), isFloating: !isFullscreen)
                    .transition(isFullscreen ? .scale(scale: 0.97).combined(with: .opacity) : .identity)
                    .zIndex(10)
            } else {
                mainPanel
            }

            if let confirmation = viewModel.pendingConfirmation {
                Color.black.opacity(0.3)
                    .onTapGesture { viewModel.cancelPending() }
                    .transition(.opacity)
                    .zIndex(19)
                ConfirmationOverlayView(
                    confirmation: confirmation,
                    onConfirm: { viewModel.confirmPending() },
                    onCancel: { viewModel.cancelPending() }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.monoAccent, accent)
        .environment(\.monoReduceMotion, reduceMotion)
        .tint(accent)
        .monoAnimation(.smooth(duration: 0.2), value: viewModel.activeSheet, enabled: !reduceMotion && isFullscreen)
        .monoAnimation(.smooth(duration: 0.16), value: viewModel.pendingConfirmation?.id, enabled: !reduceMotion)
        .onChange(of: preferences.displayMode) { _, _ in onLayoutChange() }
        .onChange(of: preferences.thumbnailSize) { _, _ in onLayoutChange() }
        .onChange(of: permissions.showsBanner) { _, _ in onLayoutChange() }
    }

    private func sheetSize(_ sheet: SwitcherSheet) -> CGSize {
        CGSize(
            width: min(sheet.size.width, viewModel.availableSpace.width),
            height: min(sheet.size.height, viewModel.availableSpace.height)
        )
    }

    @ViewBuilder
    private func sheetView(_ sheet: SwitcherSheet) -> some View {
        switch sheet {
        case .help:
            HelpOverlayView(onClose: { viewModel.closeHelp() })
        case .preview:
            if let selected = viewModel.selectedWindow {
                QuickLookView(
                    window: selected,
                    slot: viewModel.slot(for: selected.id),
                    onClose: { viewModel.closePreview() },
                    onConfirm: onConfirm
                )
            }
        }
    }

    private var mainPanel: some View {
        let layout = viewModel.layout

        return VStack(spacing: 0) {
            header
                .frame(height: SwitcherMetrics.headerControlHeight)
                .padding(.horizontal, SwitcherMetrics.gridHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if permissions.showsBanner {
                PermissionsBannerView()
                    .padding(.horizontal, SwitcherMetrics.gridHorizontalPadding)
                    .padding(.bottom, 8)
            }

            WindowGrid(viewModel: viewModel, layout: layout, onConfirm: onConfirm)
                .frame(height: layout.gridHeight)

            ShortcutLegend()
                .frame(height: 20)
                .padding(.horizontal, SwitcherMetrics.gridHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .switcherGlassPanel()
        .shadow(color: .black.opacity(0.35), radius: isFullscreen ? 30 : 0, y: isFullscreen ? 16 : 0)
    }

    private func dimmingLayer(opacity: Double) -> some View {
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture(perform: handleBackdropTap)
    }

    private func handleBackdropTap() {
        if !viewModel.handleDismiss() {
            onCancel()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SearchBarView(
                text: $viewModel.searchQuery,
                isSearchMode: viewModel.isSearchMode,
                onEnter: { viewModel.enterSearchMode() },
                onExit: { viewModel.exitSearchMode() }
            )

            if viewModel.isAppOnlyMode {
                Text(localized("Current App"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            }

            Spacer(minLength: 8)

            let count = viewModel.filteredWindows.count
            Text(count == 1 ? localized("1 window") : localized("%d windows", count))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ToolbarIconButton(
                    symbol: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: isFullscreen ? localized("Centered Floating Mode") : localized("Full Screen Mode"),
                    action: { preferences.toggleDisplayMode() }
                )
                ToolbarIconButton(
                    symbol: "keyboard",
                    help: localized("Keyboard Shortcuts (?)"),
                    action: { viewModel.toggleHelp() }
                )
                ToolbarIconButton(
                    symbol: "gearshape",
                    help: localized("Settings in MonoHub"),
                    action: { viewModel.openSettings() }
                )
            }
        }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: SwitcherMetrics.headerControlHeight, height: SwitcherMetrics.headerControlHeight)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct WindowGrid: View {
    let viewModel: SwitcherViewModel
    let layout: SwitcherLayout
    let onConfirm: () -> Void

    @Environment(\.monoReduceMotion) private var reduceMotion

    var body: some View {
        let windows = viewModel.filteredWindows
        let selectedID = viewModel.selectedWindow?.id
        let quickNumbers = viewModel.quickNumbers()
        let columns = Array(
            repeating: GridItem(.fixed(layout.card.width), spacing: SwitcherMetrics.columnSpacing),
            count: layout.columns
        )

        if windows.isEmpty {
            EmptyState(query: viewModel.searchQuery)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: SwitcherMetrics.rowSpacing) {
                        ForEach(windows) { window in
                            WindowThumbnailCard(
                                window: window,
                                slot: viewModel.slot(for: window.id),
                                isSelected: window.id == selectedID,
                                quickNumber: quickNumbers[window.id],
                                thumbnailSize: layout.thumbnail,
                                onSelect: { viewModel.select(id: window.id) },
                                onActivate: onConfirm,
                                onClose: { SwitcherPanelController.shared.close(window: window) }
                            )
                            .equatable()
                            .id(window.id)
                        }
                    }
                    .padding(.horizontal, SwitcherMetrics.gridHorizontalPadding)
                    .padding(.vertical, SwitcherMetrics.gridVerticalPadding)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(!layout.isScrollable)
                .scrollIndicators(layout.isScrollable ? .automatic : .hidden)
                .onChange(of: selectedID) { _, newID in
                    guard layout.isScrollable, let newID else { return }
                    if reduceMotion {
                        proxy.scrollTo(newID)
                    } else {
                        withAnimation(.smooth(duration: 0.15)) { proxy.scrollTo(newID) }
                    }
                }
            }
        }
    }
}

private struct EmptyState: View {
    let query: String

    var body: some View {
        if query.isEmpty {
            ContentUnavailableView(
                localized("No Open Windows"),
                systemImage: "macwindow",
                description: Text(localized("Open windows will appear here."))
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

private struct QuickLookView: View {
    let window: WindowInfo
    let slot: ThumbnailSlot
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SwitcherSheetHeader(
                title: window.displayTitle,
                subtitle: window.appName,
                closeHelp: localized("Close Quick Look (Space)"),
                onClose: onClose
            ) {
                RunningAppIconView(pid: window.pid, size: 36)
            }

            ThumbnailView(window: window, slot: slot, size: nil)

            HStack(spacing: 14) {
                WindowStatusGlyphs(window: window)
                SwitcherShortcutHint(key: "W", description: localized("Close"))
                SwitcherShortcutHint(key: "M", description: localized("Minimize"))
                SwitcherShortcutHint(key: "Z", description: localized("Zoom"))

                Spacer(minLength: 8)

                Button(localized("Switch to Window"), action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(20)
    }
}

private struct ShortcutLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                legend(ShortcutCatalog.legend)
                legend(ShortcutCatalog.legend.suffix(2))
            }

            Spacer(minLength: 8)

            Text("v\(AppInfo.version)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func legend(_ items: some RandomAccessCollection<ShortcutItem>) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(items)) { SwitcherShortcutHint($0) }
        }
    }
}
