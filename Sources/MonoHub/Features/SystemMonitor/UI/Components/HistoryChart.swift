import SwiftUI

struct ChartSeries {
    let values: [Double]
    let tint: Color
}

struct HistoryChart: View {
    let series: [ChartSeries]
    var fixedMaximum: Double?
    var capacity = 60
    var height: CGFloat = 54

    init(values: [Double], tint: Color, fixedMaximum: Double? = 1, height: CGFloat = 54) {
        self.series = [ChartSeries(values: values, tint: tint)]
        self.fixedMaximum = fixedMaximum
        self.height = height
    }

    init(series: [ChartSeries], fixedMaximum: Double? = nil, height: CGFloat = 54) {
        self.series = series
        self.fixedMaximum = fixedMaximum
        self.height = height
    }

    var body: some View {
        Canvas { context, size in
            let gridColor = Color.primary.opacity(0.07)
            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path()
                let y = size.height * fraction
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            var observedMaximum = 0.0
            for item in series {
                for value in item.values where value > observedMaximum {
                    observedMaximum = value
                }
            }
            let maximum = max(fixedMaximum ?? observedMaximum * 1.15, 0.000_1)
            let step = size.width / CGFloat(max(capacity - 1, 1))

            for item in series where item.values.count > 1 {
                let offset = CGFloat(capacity - item.values.count) * step
                var points: [CGPoint] = []
                points.reserveCapacity(item.values.count)
                for (index, value) in item.values.enumerated() {
                    points.append(CGPoint(
                        x: offset + CGFloat(index) * step,
                        y: size.height - CGFloat(min(max(value / maximum, 0), 1)) * (size.height - 3) - 1.5
                    ))
                }
                let line = smoothPath(points)

                var area = line
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                area.addLine(to: CGPoint(x: points[0].x, y: size.height))
                area.closeSubpath()

                context.fill(area, with: .linearGradient(
                    Gradient(colors: [item.tint.opacity(series.count > 1 ? 0.22 : 0.32), item.tint.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(line, with: .color(item.tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }
}

struct ChartLegendItem: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(tint)
                .frame(width: 10, height: 3)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption2.weight(.medium))
    }
}
