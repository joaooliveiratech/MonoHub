import SwiftUI

struct BatteryView: View {
    private let batteryManager = BatteryManager.shared
    private let preferences = NotchPreferences.shared

    init() {}

    private var thermalLabel: (title: String, icon: String, color: Color) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return (localized("Normal thermal"), "thermometer.low", .mint)
        case .fair:
            return (localized("Warm thermal"), "thermometer.medium", .yellow)
        case .serious:
            return (localized("High thermal"), "thermometer.high", .orange)
        case .critical:
            return (localized("Critical thermal"), "flame.fill", .red)
        @unknown default:
            return (localized("Normal thermal"), "thermometer.low", .mint)
        }
    }

    var body: some View {
        let info = batteryManager.batteryInfo
        let thermal = thermalLabel

        HStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 8)
                    .frame(width: 96, height: 96)

                Circle()
                    .trim(from: 0, to: CGFloat(Double(info.percentage) / 100.0))
                    .stroke(
                        LinearGradient(
                            colors: info.isCharging ? [Color.green, Color.mint] : (info.percentage <= 20 ? [Color.red, Color.orange] : [Color.green, Color.teal]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-90))
                    .animation(NotchTheme.content, value: info.percentage)

                VStack(spacing: 2) {
                    if info.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    Text("\(info.percentage)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                NotchSectionLabel(
                    info.isPluggedIn ? localized("Connected to power") : localized("On battery power"),
                    systemImage: info.isPluggedIn ? "powerplug.fill" : "battery.100",
                    tint: info.isCharging ? .green : .white.opacity(0.8)
                )

                Text(info.statusDescription)
                    .font(NotchTheme.largeTitle)
                    .foregroundStyle(NotchTheme.primaryText)

                HStack(spacing: 8) {
                    badgePill(
                        title: info.isLowPowerMode ? localized("Low Power Mode") : localized("Standard power"),
                        icon: info.isLowPowerMode ? "leaf.fill" : "bolt.circle",
                        tint: info.isLowPowerMode ? .yellow : NotchTheme.secondaryText
                    )

                    if preferences.batteryShowThermalState {
                        badgePill(
                            title: thermal.title,
                            icon: thermal.icon,
                            tint: thermal.color
                        )
                    }

                    if preferences.batteryShowCycleAndCapacity {
                        badgePill(
                            title: String(format: localized("Cap. %d%%"), info.maxCapacity),
                            icon: "heart.fill",
                            tint: .green
                        )
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .notchModule()
    }

    private func badgePill(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
