import AppKit
import SwiftUI

struct SnapAreaDiagram: View {
    let options: TileOptions
    let bottomEdge: BottomEdgeBehavior

    @State private var hoveredArea: SnapArea?
    @State private var referenceScreenWidth: CGFloat = NSScreen.main?.frame.width ?? 1728

    private let menuBarHeight: CGFloat = 11
    private let hoverThreshold: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let layout = ScreenLayout(
                bounds: CGRect(origin: .zero, size: proxy.size),
                visibleBounds: CGRect(
                    x: 0,
                    y: menuBarHeight + 4,
                    width: proxy.size.width,
                    height: max(60, proxy.size.height - menuBarHeight - 4)
                )
            )

            ZStack(alignment: .topLeading) {
                // Adaptive macOS 27 desktop backdrop
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.11),
                                Color.indigo.opacity(0.08),
                                Color.primary.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // macOS 27 translucent floating menu bar silhouette
                HStack(spacing: 4) {
                    Circle().fill(Color.primary.opacity(0.22)).frame(width: 4, height: 4)
                    Capsule().fill(Color.primary.opacity(0.16)).frame(width: 24, height: 3.5)
                    Spacer()
                    Capsule().fill(Color.primary.opacity(0.16)).frame(width: 18, height: 3.5)
                    Circle().fill(Color.primary.opacity(0.22)).frame(width: 4, height: 4)
                }
                .padding(.horizontal, 8)
                .frame(height: menuBarHeight)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 6)
                .padding(.top, 4)

                // Subtle floating dock pill at bottom center
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 78, height: 6)
                        Spacer()
                    }
                    .padding(.bottom, 5)
                }
                .allowsHitTesting(false)

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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        .frame(height: 186)
        .animation(.snappy(duration: 0.2, extraBounce: 0), value: hoveredArea)
        .onAppear {
            referenceScreenWidth = NSScreen.main?.frame.width ?? 1728
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Snap areas preview"))
        .accessibilityValue(hoveredArea?.action.displayName ?? localized("None"))
    }

    private func previewTile(for area: SnapArea, in layout: ScreenLayout, canvasWidth: CGFloat) -> some View {
        let scale = canvasWidth / max(1, referenceScreenWidth)
        var scaledOptions = options
        scaledOptions.margin = max(4, options.margin * scale)
        scaledOptions.gap = max(4, options.gap * scale)
        let rect = TileCalculation.calculate(
            action: area.action,
            screen: layout,
            currentFrame: .zero,
            options: scaledOptions
        )

        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            shape
                .fill(Color.accentColor.opacity(0.18))
                .glassEffect(.clear, in: shape)
                .overlay(
                    shape.strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                )

            HStack(spacing: 5) {
                Image(systemName: area.action.sfSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(area.action.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
        }
        .frame(width: max(24, rect.width), height: max(24, rect.height))
        .offset(x: rect.minX, y: rect.minY)
    }
}
