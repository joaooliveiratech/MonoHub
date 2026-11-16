import SwiftUI

struct QuotaUsageBar: View {
    let title: String
    let percent: Double
    let detail: String?
    let pacing: WindowPacing?
    let accentColor: Color
    var isCompact = false
    let subtitle: String?

    init(
        title: String,
        percent: Double,
        detail: String? = nil,
        pacing: WindowPacing? = nil,
        accentColor: Color = .accentColor,
        isCompact: Bool = false,
        subtitle: String? = nil
    ) {
        self.title = title
        self.percent = min(max(percent, 0), 100)
        self.detail = detail
        self.pacing = pacing
        self.accentColor = accentColor
        self.isCompact = isCompact
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: isCompact ? 11 : 12))
                    .foregroundStyle(isCompact ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isCompact, let detail {
                    Text(detail)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    if let pacing {
                        Text(pacing.pace.glyph)
                            .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                            .foregroundStyle(pacingGlyphColor(pacing.pace))
                    }

                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(UsageColor.forRatio(percent / 100, base: .primary))
                        .contentTransition(.numericText(value: percent))
                        .animation(.snappy(duration: 0.3), value: Int(percent))
                }
                .frame(minWidth: 40, alignment: .trailing)
            }

            UsageBar(ratio: percent / 100, tint: UsageColor.forRatio(percent / 100, base: accentColor), height: isCompact ? 5 : 7)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: isCompact ? 9.5 : 10.5))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
            }

            if !isCompact, let summary = fullDetailText {
                Text(summary)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(percent.rounded())) por cento usado" + (detail.map { ", \($0)" } ?? ""))
    }

    private var fullDetailText: String? {
        var parts: [String] = []
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let note = pacing?.paceNote, !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func pacingGlyphColor(_ pace: PaceState) -> Color {
        switch pace {
        case .ahead: percent >= 70 ? .red : .orange
        case .onTrack: .green
        case .under: .blue
        }
    }
}
