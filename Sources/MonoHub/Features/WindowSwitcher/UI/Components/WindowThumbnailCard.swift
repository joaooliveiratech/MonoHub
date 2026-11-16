import SwiftUI

struct WindowThumbnailCard: View, Equatable {
    let window: WindowInfo
    let slot: ThumbnailSlot
    let isSelected: Bool
    let quickNumber: Int?
    let thumbnailSize: CGSize
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    static func == (lhs: WindowThumbnailCard, rhs: WindowThumbnailCard) -> Bool {
        lhs.window.id == rhs.window.id
            && lhs.window.title == rhs.window.title
            && lhs.window.isMinimized == rhs.window.isMinimized
            && lhs.window.displayIndex == rhs.window.displayIndex
            && lhs.slot === rhs.slot
            && lhs.isSelected == rhs.isSelected
            && lhs.quickNumber == rhs.quickNumber
            && lhs.thumbnailSize == rhs.thumbnailSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SwitcherMetrics.captionSpacing) {
            ThumbnailView(window: window, slot: slot, size: thumbnailSize)
                .overlay(alignment: .topLeading) { quickNumberBadge }
                .overlay(alignment: .topTrailing) { closeButton }

            caption
                .frame(width: thumbnailSize.width, height: SwitcherMetrics.captionHeight)
        }
        .padding(SwitcherMetrics.cardPadding)
        .contentShape(RoundedRectangle(cornerRadius: SwitcherMetrics.cardCornerRadius, style: .continuous))
        .switcherSelectionCard(isSelected: isSelected, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
            onActivate()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.appName), \(window.displayTitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var quickNumberBadge: some View {
        if let quickNumber {
            Text("\(quickNumber)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 21, minHeight: 21)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: Circle())
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if isHovered {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .help(localized("Close window (W)"))
            .accessibilityLabel(localized("Close %@", window.displayTitle))
        }
    }

    private var isCompact: Bool {
        thumbnailSize.width < 220
    }

    private var caption: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            RunningAppIconView(pid: window.pid, size: isCompact ? 18 : 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(window.displayTitle)
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(window.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            WindowStatusGlyphs(window: window)
        }
    }
}

struct ThumbnailView: View {
    let window: WindowInfo
    let slot: ThumbnailSlot
    let size: CGSize?

    @Environment(\.monoReduceMotion) private var reduceMotion

    private var placeholderIconSize: CGFloat {
        size.map { min(64, $0.height * 0.36) } ?? 96
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SwitcherMetrics.thumbnailCornerRadius, style: .continuous)

        ZStack {
            if let image = slot.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .transition(.opacity)
            } else {
                shape
                    .fill(Color.primary.opacity(0.05))
                    .overlay(RunningAppIconView(pid: window.pid, size: placeholderIconSize))
            }
        }
        .frame(width: size?.width, height: size?.height)
        .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: size == nil ? .infinity : nil)
        .monoAnimation(.easeOut(duration: 0.15), value: slot.image == nil, enabled: !reduceMotion)
    }
}

struct WindowStatusGlyphs: View {
    let window: WindowInfo

    var body: some View {
        HStack(spacing: 6) {
            if window.isMinimized {
                Image(systemName: "dock.arrow.down.rectangle")
                    .help(localized("Minimized"))
                    .accessibilityLabel(localized("Minimized"))
            }
            if let display = window.displayIndex {
                Label("\(display)", systemImage: "display")
                    .labelStyle(.titleAndIcon)
                    .help(localized("Display %d", display))
                    .accessibilityLabel(localized("Display %d", display))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
