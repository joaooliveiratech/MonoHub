import SwiftUI

enum UsageColor {
    static func forRatio(_ ratio: Double, base: Color) -> Color {
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return base
    }
}

struct PanelHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HubIcon(systemName: symbol, tint: tint, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            accessory
        }
    }
}

struct HeroValue: View {
    let value: String
    var tint: Color = .primary

    var body: some View {
        Text(value)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .lineLimit(1)
            .fixedSize()
    }
}

struct Platter<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

struct PanelSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            content
        }
    }
}

extension PanelSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .secondary

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var valueTint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

struct InfoList: View {
    let rows: [(String, String, Color)]

    init(_ rows: [(String, String)]) {
        self.rows = rows.map { ($0.0, $0.1, Color.primary) }
    }

    init(tinted rows: [(String, String, Color)]) {
        self.rows = rows
    }

    var body: some View {
        Platter(padding: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                InfoRow(title: row.0, value: row.1, valueTint: row.2)
                    .padding(.horizontal, 10)
                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 10)
                        .opacity(0.6)
                }
            }
        }
    }
}

struct UsageBar: View {
    let ratio: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.1))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * min(max(ratio, 0), 1), height))
                }
            }
            .frame(height: height)
            .animation(.smooth(duration: 0.35), value: ratio)
    }
}

struct BarSegment: Identifiable {
    let id: String
    let title: String
    let value: Double
    let tint: Color
    var detail: String? = nil
}

struct SegmentedBar: View {
    let segments: [BarSegment]
    var height: CGFloat = 10

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.tint)
                        .frame(width: max((proxy.size.width - CGFloat(segments.count - 1) * 1.5) * segment.value / total, 0))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.35), value: segments.map(\.value))
    }
}

struct SegmentLegend: View {
    let segments: [BarSegment]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(segments) { segment in
                GridRow {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(segment.tint)
                        .frame(width: 8, height: 8)
                    Text(segment.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(segment.detail ?? "")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }
}

struct PanelActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.09) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
