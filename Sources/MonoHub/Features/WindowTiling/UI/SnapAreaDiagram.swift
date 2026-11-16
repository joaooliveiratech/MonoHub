import AppKit
import SwiftUI

struct SnapAreaDiagram: View {
    let options: TileOptions
    let bottomEdge: BottomEdgeBehavior

    @State private var hoveredArea: SnapArea?

    private let menuBarHeight: CGFloat = 10
    private let hoverThreshold: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let layout = ScreenLayout(
                bounds: CGRect(origin: .zero, size: proxy.size),
                visibleBounds: CGRect(x: 0, y: menuBarHeight, width: proxy.size.width, height: proxy.size.height - menuBarHeight)
            )

            ZStack(alignment: .topLeading) {

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: menuBarHeight)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                if let hoveredArea {
                    previewTile(for: hoveredArea, in: layout, canvasWidth: proxy.size.width)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "cursorarrow.motionlines")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(localized("Hover edges and corners to preview snap areas"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let area = SnapArea.evaluate(mousePoint: location, screen: layout, threshold: hoverThreshold, bottomEdge: bottomEdge)
                    if area != hoveredArea {
                        hoveredArea = area
                    }
                case .ended:
                    hoveredArea = nil
                }
            }
        }
        .frame(height: 180)
        .animation(.snappy(duration: 0.2), value: hoveredArea)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Snap areas preview"))
        .accessibilityValue(hoveredArea?.action.displayName ?? localized("None"))
    }

    private func previewTile(for area: SnapArea, in layout: ScreenLayout, canvasWidth: CGFloat) -> some View {
        let scale = canvasWidth / max(1, NSScreen.main?.frame.width ?? canvasWidth)
        var scaledOptions = options
        scaledOptions.margin = max(3, options.margin * scale)
        scaledOptions.gap = max(3, options.gap * scale)
        let rect = TileCalculation.calculate(
            action: area.action,
            screen: layout,
            currentFrame: .zero,
            options: scaledOptions
        )

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.25))
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .overlay(
                Text(area.action.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
