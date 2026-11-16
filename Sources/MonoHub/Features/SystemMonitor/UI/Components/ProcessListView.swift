import AppKit
import SwiftUI

struct ProcessListView: View {
    let items: [ProcessItem]
    let metric: ProcessMetric
    let tint: Color

    var body: some View {
        let maximum = max(items.map(value(of:)).max() ?? 1, 0.001)
        Platter(padding: 5) {
            VStack(spacing: 2) {
                ForEach(items) { item in
                    ProcessRow(
                        item: item,
                        metric: metric,
                        ratio: min(max(value(of: item) / maximum, 0), 1),
                        tint: tint
                    )
                }
            }
        }
    }

    private func value(of item: ProcessItem) -> Double {
        switch metric {
        case .cpu: return item.cpuPercent
        case .memory: return Double(item.residentMemoryBytes)
        case .gpu: return item.gpuPercent
        case .energy: return max(item.energyImpact, item.powerWatts * 10, item.recentEnergyJoules * 0.1)
        case .disk: return Double(item.diskBytesPerSec)
        }
    }
}

private struct ProcessRow: View {
    let item: ProcessItem
    let metric: ProcessMetric
    let ratio: Double
    let tint: Color
    @State private var isHovering = false

    var body: some View {
        let badges = item.usageBadges(excluding: metric, maxCount: 3)

        HStack(alignment: .center, spacing: 8) {
            Image(nsImage: AppIconCache.shared.icon(for: item.bundlePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    Text(formattedPrimaryValue)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryValueColor)
                        .contentTransition(.numericText())
                }

                HStack(alignment: .center, spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 44, height: 3)
                        Capsule()
                            .fill(tint.opacity(0.85))
                            .frame(width: max(44 * ratio, 3), height: 3)
                            .animation(.smooth(duration: 0.3), value: ratio)
                    }

                    if !badges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(badges) { badge in
                                ResourceUsagePill(badge: badge)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { isHovering = $0 }
        .help(item.detailedHelpSummary)
    }

    private var formattedPrimaryValue: String {
        switch metric {
        case .cpu: return item.formattedCPU
        case .memory: return item.formattedMemory
        case .gpu: return item.formattedGPU
        case .energy: return item.formattedPower
        case .disk: return item.formattedDiskSpeed
        }
    }

    private var primaryValueColor: Color {
        switch metric {
        case .cpu:
            if item.cpuPercent >= 50 { return .red }
            if item.cpuPercent >= 25 { return .orange }
            return .primary
        case .energy:
            if item.powerWatts >= 5.0 || item.energyImpact >= 50 { return .red }
            if item.powerWatts >= 1.5 || item.energyImpact >= 20 { return .orange }
            return .primary
        default:
            return .primary
        }
    }
}

private struct ResourceUsagePill: View {
    let badge: ProcessUsageBadge

    var body: some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(pillColor)
                .frame(width: 4.5, height: 4.5)
            Text("\(badge.label) \(badge.value)")
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 4.5)
        .padding(.vertical, 1.5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var pillColor: Color {
        switch badge.metric {
        case .cpu: return ModuleType.cpu.tint
        case .memory: return ModuleType.ram.tint
        case .gpu: return ModuleType.gpu.tint
        case .energy: return .orange
        case .disk: return ModuleType.disk.tint
        case nil: return .secondary
        }
    }
}

struct TopProcessesSection: View {
    let items: [ProcessItem]
    let metric: ProcessMetric
    let tint: Color
    let isEnabled: Bool
    var customTitle: String? = nil

    var body: some View {
        if isEnabled {
            PanelSection(title: customTitle ?? localized("Top Processes")) {
                Text(metric.title)
            } content: {
                if items.isEmpty {
                    Platter {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(localized("Collecting samples…"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProcessListView(items: items, metric: metric, tint: tint)
                }
            }
        }
    }
}
