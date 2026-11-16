import SwiftUI

struct BatteryGlyph: View {
    let level: Double
    let isCharging: Bool
    let isConnected: Bool
    var isLowPowerMode = false
    var width: CGFloat = 34

    private var height: CGFloat { width * 0.5 }
    private var clampedLevel: Double { min(max(level, 0), 1) }
    private var indicator: PowerIndicator { PowerIndicator(isCharging: isCharging, isConnected: isConnected) }

    private var fillColor: Color {
        if isCharging { return .green }
        if isLowPowerMode { return .yellow }
        if !isConnected, level <= 0.2 { return .red }
        return .primary
    }

    var body: some View {
        HStack(spacing: width * 0.04) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: max(width / 34, 1))
                GeometryReader { proxy in
                    let inset = max(height * 0.115, 1.5)
                    let inner = proxy.size.width - inset * 2
                    RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                        .fill(fillColor)
                        .frame(width: max(inner * clampedLevel, 2), height: proxy.size.height - inset * 2)
                        .offset(x: inset, y: inset)
                        .animation(.smooth(duration: 0.4), value: level)
                }
                if let symbol = indicator.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: height * (indicator == .charging ? 0.62 : 0.55), weight: .heavy))
                        .foregroundStyle(.primary)
                        .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.9), radius: 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)

            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: width * 0.06, topTrailingRadius: width * 0.06)
                .fill(Color.primary.opacity(0.4))
                .frame(width: width * 0.06, height: height * 0.36)
        }
        .accessibilityElement()
        .accessibilityLabel(localized("Battery %d%%", Int((clampedLevel * 100).rounded())) + indicator.accessibilitySuffix)
    }
}
