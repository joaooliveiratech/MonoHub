import SwiftUI

struct HubAccordionSection<Content: View>: View {
    let title: String
    let subtitle: String
    var badgeText: String? = nil
    var badgeColor: Color = .accentColor
    let systemImage: String
    let tint: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHoveringHeader = false
    @Environment(\.accordionFilter) private var filter

    private var matchesFilter: Bool {
        filter.isEmpty
            || title.localizedCaseInsensitiveContains(filter)
            || subtitle.localizedCaseInsensitiveContains(filter)
            || (badgeText?.localizedCaseInsensitiveContains(filter) ?? false)
    }

    var body: some View {
        if matchesFilter { section }
    }

    private var section: some View {
        let shown = isExpanded || !filter.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    HubIcon(systemName: systemImage, tint: tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let badgeText, !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(badgeColor.opacity(0.13))
                            )
                            .fixedSize()
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(shown ? 90 : 0))
                        .frame(width: 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(isHoveringHeader && !shown ? 0.025 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringHeader = hovering
            }

            if shown {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(shown ? tint.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct HubSettingRowLabel: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            HubIcon(systemName: systemImage, tint: tint)
        }
    }
}

private struct HubSettingRowTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HubToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubSettingRowTitle(title: title, subtitle: subtitle)

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

struct HubSliderRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubSettingRowTitle(title: title, subtitle: subtitle)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .labelsHidden()
                    .frame(width: 165)

                Text(format(value))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .frame(minWidth: 58, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

struct HubStepperRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let valueLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubSettingRowTitle(title: title, subtitle: subtitle)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(valueLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
