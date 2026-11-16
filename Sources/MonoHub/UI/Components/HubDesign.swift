import SwiftUI

enum HubMetrics {
    static let cardCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let itemSpacing: CGFloat = 12
    static let iconSize: CGFloat = 22
}

struct HubCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat
    var isInteractive: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(.background.secondary))
            .background {
                if isInteractive && isHovered {
                    shape.fill(.fill.quaternary)
                }
            }
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .contentShape(shape)
            .onHover { hovering in
                guard isInteractive else { return }
                isHovered = hovering
            }
    }
}

struct HubFloatingBarModifier: ViewModifier {
    var cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        Group {
            if let cornerRadius {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

extension View {

    func hubFloatingBar(cornerRadius: CGFloat? = 16) -> some View {
        modifier(HubFloatingBarModifier(cornerRadius: cornerRadius))
    }

    func hubCard(
        cornerRadius: CGFloat = HubMetrics.cardCornerRadius,
        padding: CGFloat = HubMetrics.cardPadding,
        isInteractive: Bool = false
    ) -> some View {
        modifier(HubCardModifier(cornerRadius: cornerRadius, padding: padding, isInteractive: isInteractive))
    }
}

struct HubIcon: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = HubMetrics.iconSize

    var body: some View {
        let cornerRadius = size * 0.24
        Image(systemName: systemName)
            .font(.system(size: size * 0.49, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                tint.gradient,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.28), radius: 1.2, x: 0, y: 0.8)
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let text: String
    let icon: String?
    let color: Color

    init(_ text: String, icon: String? = nil, color: Color = .accentColor) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct HubPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubIcon(systemName: systemImage, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

extension HubPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String, systemImage: String, tint: Color) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

struct FeatureDisabledView: View {
    let feature: HubFeature

    var body: some View {
        ContentUnavailableView {
            Label(feature.title, systemImage: feature.systemImage)
        } description: {
            Text(String(format: localized("This module is disabled and uses no resources. %@"), feature.summary))
        } actions: {
            Button(String(format: localized("Enable %@"), feature.title)) {
                FeatureManager.shared.setEnabled(feature, true)
            }
            .buttonStyle(.borderedProminent)
            Button(localized("Manage Modules…")) {
                HubNavigation.shared.select(.modules)
            }
        }
    }
}

@Observable
@MainActor
final class ReorderDragState {
    static let shared = ReorderDragState()

    private(set) var draggingID: String?

    private init() {}

    func begin(_ id: String) {
        draggingID = id
    }

    func end() {
        draggingID = nil
    }
}

struct ReorderGrip: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 14)
            .help(localized("Drag to reorder"))
            .accessibilityHidden(true)
    }
}

struct ReorderableRowModifier: ViewModifier {
    let scope: String
    let id: String
    let orderedIDs: [String]
    let onMove: (_ moving: String, _ target: String) -> Void

    @State private var isTargeted = false
    private let dragState = ReorderDragState.shared

    private var payloadPrefix: String { "monohub.reorder.\(scope)." }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(alignment: indicatorAlignment) {
                if isTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, -4)
                        .allowsHitTesting(false)
                }
            }
            .draggable(beginDrag())
            .dropDestination(for: String.self) { items, _ in
                dragState.end()
                guard let payload = items.first(where: { $0.hasPrefix(payloadPrefix) }) else { return false }
                let moving = String(payload.dropFirst(payloadPrefix.count))
                guard moving != id, orderedIDs.contains(moving) else { return false }
                onMove(moving, id)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }

    private var indicatorAlignment: Alignment {
        guard let dragging = dragState.draggingID,
              let source = orderedIDs.firstIndex(of: dragging),
              let destination = orderedIDs.firstIndex(of: id) else { return .top }
        return source < destination ? .bottom : .top
    }

    private func beginDrag() -> String {
        dragState.begin(id)
        return payloadPrefix + id
    }
}

extension View {
    func reorderable(
        scope: String,
        id: String,
        orderedIDs: [String],
        onMove: @escaping (_ moving: String, _ target: String) -> Void
    ) -> some View {
        modifier(ReorderableRowModifier(scope: scope, id: id, orderedIDs: orderedIDs, onMove: onMove))
    }
}

struct AccordionExpandToolbarButton: View {
    let allExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) { action() }
        } label: {
            Label(
                allExpanded ? localized("Collapse sections") : localized("Expand sections"),
                systemImage: allExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
            )
        }
        .help(allExpanded ? localized("Collapse all sections") : localized("Expand all sections"))
    }
}

extension AccordionExpandToolbarButton {
    init<Section: Hashable & CaseIterable>(expandedSections: Binding<Set<Section>>) {
        let allExpanded = expandedSections.wrappedValue.count == Section.allCases.count
        self.init(allExpanded: allExpanded) {
            expandedSections.wrappedValue = allExpanded ? [] : Set(Section.allCases)
        }
    }
}

struct AccordionOverviewBanner: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    @Environment(\.accordionFilter) private var filter

    var body: some View {
        if filter.isEmpty { banner }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            HubIcon(systemName: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(localized("Click any section below to expand only what you want to configure."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct AccordionFilterKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {

    var accordionFilter: String {
        get { self[AccordionFilterKey.self] }
        set { self[AccordionFilterKey.self] = newValue }
    }
}

extension View {

    func accordionFilter(_ text: Binding<String>) -> some View {
        searchable(text: text, placement: .toolbar, prompt: localized("Filter options…"))
            .environment(\.accordionFilter, text.wrappedValue.trimmingCharacters(in: .whitespaces))
    }

    func reorderableItem<T: Hashable>(
        scope: String,
        item: T,
        items: [T],
        onChange: @escaping ([T]) -> Void
    ) -> some View {
        reorderable(
            scope: scope,
            id: String(describing: item),
            orderedIDs: items.map { String(describing: $0) }
        ) { moving, target in
            guard let from = items.firstIndex(where: { String(describing: $0) == moving }),
                  let to = items.firstIndex(where: { String(describing: $0) == target }) else { return }
            withAnimation(.snappy) {
                onChange(items.moving(from: from, to: to))
            }
        }
    }
}
