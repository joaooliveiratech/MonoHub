import SwiftUI

private struct SwitcherGlassPanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(shape.fill(.background))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .clipShape(shape)
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        }
    }
}

private struct SwitcherFieldBackgroundModifier: ViewModifier {
    @Environment(\.monoAccent) private var accent

    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(isFocused ? 0.11 : 0.075),
                                Color.primary.opacity(isFocused ? 0.07 : 0.045)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule().strokeBorder(
                    isFocused
                        ? AnyShapeStyle(accent.opacity(0.85))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.primary.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        ),
                    lineWidth: isFocused ? 1.5 : 0.75
                )
            )
    }
}

private struct SwitcherSelectionCardModifier: ViewModifier {
    @Environment(\.monoAccent) private var accent
    @Environment(\.monoReduceMotion) private var reduceMotion

    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SwitcherMetrics.cardCornerRadius, style: .continuous)

        return content
            .background(
                ZStack {
                    if isSelected {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.26),
                                    accent.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else if isHovered {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.09),
                                    Color.primary.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            )
            .overlay(
                shape.strokeBorder(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(
                            Color.primary.opacity(isHovered ? 0.14 : 0)
                        ),
                    lineWidth: isSelected ? 2.2 : 0.75
                )
            )
            .shadow(color: isSelected ? accent.opacity(0.22) : .clear, radius: 10, y: 3)
            .scaleEffect(isSelected ? 1.012 : (isHovered ? 1.005 : 1.0))
            .monoAnimation(.snappy(duration: 0.15, extraBounce: 0), value: isSelected, enabled: !reduceMotion)
            .monoAnimation(.easeOut(duration: 0.12), value: isHovered, enabled: !reduceMotion)
    }
}

private struct SwitcherSheetChromeModifier: ViewModifier {
    let size: CGSize
    let isFloating: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .switcherGlassPanel()
            .shadow(color: .black.opacity(0.35), radius: isFloating ? 0 : 30, y: isFloating ? 0 : 16)
    }
}

extension View {
    func switcherGlassPanel(cornerRadius: CGFloat = SwitcherMetrics.panelCornerRadius) -> some View {
        modifier(SwitcherGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func switcherFieldBackground(isFocused: Bool) -> some View {
        modifier(SwitcherFieldBackgroundModifier(isFocused: isFocused))
    }

    func switcherSelectionCard(isSelected: Bool, isHovered: Bool) -> some View {
        modifier(SwitcherSelectionCardModifier(isSelected: isSelected, isHovered: isHovered))
    }

    func switcherSheetChrome(size: CGSize, isFloating: Bool) -> some View {
        modifier(SwitcherSheetChromeModifier(size: size, isFloating: isFloating))
    }

    func switcherSurfaceTile(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(
            shape.fill(
                LinearGradient(
                    colors: [Color.primary.opacity(0.085), Color.primary.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.primary.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.65
            )
        )
    }
}
