import AppKit
import QuartzCore
import SwiftUI

@MainActor
@Observable
private final class FocusQueueHUDState {
    var queue: [FocusWindowRef] = []
    var selectedIndex: Int = 0
    var headerTitle: String = ""
    var headerSymbol: String = "rectangle.stack"
    var scopeTitle: String = ""
}

@MainActor
final class FocusQueuePanel: NSPanel {
    private static var loaded: FocusQueuePanel?

    static var shared: FocusQueuePanel {
        if let loaded { return loaded }
        let panel = FocusQueuePanel()
        loaded = panel
        return panel
    }

    static func release() {
        loaded?.hideTask?.cancel()
        loaded?.hideTask = nil
        loaded?.orderOut(nil)
        loaded = nil
    }

    private let hudState = FocusQueueHUDState()
    private let hostingView: NSHostingView<FocusQueueHUDView>
    private var hideTask: Task<Void, Never>?
    private var isPresented = false

    private init() {
        hostingView = NSHostingView(rootView: FocusQueueHUDView(state: hudState))
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView
    }

    func show(
        queue: [FocusWindowRef],
        selectedIndex: Int,
        headerTitle: String,
        headerSymbol: String,
        on screen: ScreenLayout,
        primaryScreenHeight: CGFloat,
        autoHideAfter duration: TimeInterval = 1.15
    ) {
        guard !queue.isEmpty else {
            hide()
            return
        }

        hideTask?.cancel()

        hudState.queue = queue
        hudState.selectedIndex = min(max(0, selectedIndex), queue.count - 1)
        hudState.headerTitle = headerTitle
        hudState.headerSymbol = headerSymbol
        hudState.scopeTitle = TilePreferencesManager.shared.focusScope.title

        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        let visibleFrame = ScreenLayout.flipped(screen.visibleBounds, primaryHeight: primaryScreenHeight)

        let width = min(contentSize.width, max(260, visibleFrame.width - 48))
        let height = contentSize.height
        let x = visibleFrame.midX - (width / 2)
        let y = visibleFrame.minY + 42
        let targetFrame = CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasPresented = isPresented
        isPresented = true

        if !wasPresented {
            let startY = reduceMotion ? targetFrame.minY : targetFrame.minY - 8
            setFrame(CGRect(x: targetFrame.minX, y: startY, width: targetFrame.width, height: targetFrame.height), display: false)
            alphaValue = 0
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : (wasPresented ? 0.14 : 0.18)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            animator().setFrame(targetFrame, display: true)
            animator().alphaValue = 1
        }

        let delayMs = max(350, Int(duration * 1000))
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard isPresented else { return }
        isPresented = false

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                guard let panel = FocusQueuePanel.loaded, !panel.isPresented else { return }
                panel.orderOut(nil)
            }
        }
    }
}

private struct FocusQueueHUDView: View {
    let state: FocusQueueHUDState

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxVisibleSlots = 6

    private var visibleWindowSlice: [(slotIndex: Int, ref: FocusWindowRef)] {
        let total = state.queue.count
        guard total > Self.maxVisibleSlots else {
            return state.queue.enumerated().map { ($0.offset, $0.element) }
        }
        let half = Self.maxVisibleSlots / 2
        let start = max(0, min(state.selectedIndex - half, total - Self.maxVisibleSlots))
        let end = min(total, start + Self.maxVisibleSlots)
        return (start..<end).map { ($0, state.queue[$0]) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: state.headerSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(state.headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(state.scopeTitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(state.selectedIndex + 1) / \(state.queue.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(visibleWindowSlice, id: \.ref.windowID) { entry in
                        FocusQueueSlotCard(
                            ref: entry.ref,
                            slotNumber: entry.slotIndex + 1,
                            isSelected: entry.slotIndex == state.selectedIndex
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                shape.fill(.background)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
            }
        }
        .clipShape(shape)
        .modifier(LiquidGlassHUDModifier(shape: shape, reduceTransparency: reduceTransparency))
        .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
        .padding(16)
        .animation(reduceMotion ? nil : .snappy(duration: 0.16, extraBounce: 0), value: state.selectedIndex)
    }
}

private struct LiquidGlassHUDModifier: ViewModifier {
    let shape: RoundedRectangle
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

private struct FocusQueueSlotCard: View {
    let ref: FocusWindowRef
    let slotNumber: Int
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                FocusAppIconView(pid: ref.pid, size: 30)

                Text("\(slotNumber)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.12))
                    )
                    .offset(x: 6, y: -4)
            }
            .padding(.top, 2)

            Text(ref.appName)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            if !ref.title.isEmpty && ref.title != ref.appName {
                Text(ref.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 108)
        .background(
            shape.fill(
                isSelected
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(0.045)
            )
        )
        .overlay(
            shape.strokeBorder(
                isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                lineWidth: isSelected ? 1.5 : 0.75
            )
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
    }
}

@MainActor
enum FocusAppIconCache {
    private static var cache: [pid_t: NSImage] = [:]

    static func icon(for pid: pid_t) -> NSImage {
        if let cached = cache[pid] {
            return cached
        }
        let image = NSRunningApplication(processIdentifier: pid)?.icon
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            ?? NSImage()
        if cache.count > 64 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[pid] = image
        return image
    }
}

struct FocusAppIconView: View {
    let pid: pid_t
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: FocusAppIconCache.icon(for: pid))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
