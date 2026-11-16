import AppKit
import CoreGraphics
import Foundation

enum FocusDirection: Sendable {
    case left
    case right
    case up
    case down
}

enum HorizontalDirection: Sendable {
    case left
    case right
}

struct ScreenLayout: Sendable, Equatable {
    let bounds: CGRect
    let visibleBounds: CGRect

    init(bounds: CGRect, visibleBounds: CGRect) {
        self.bounds = bounds
        self.visibleBounds = visibleBounds
    }

    static func from(screen: NSScreen, primaryScreenHeight: CGFloat) -> ScreenLayout {
        ScreenLayout(
            bounds: flipped(screen.frame, primaryHeight: primaryScreenHeight),
            visibleBounds: flipped(screen.visibleFrame, primaryHeight: primaryScreenHeight)
        )
    }

    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - (rect.origin.y + rect.size.height),
            width: rect.size.width,
            height: rect.size.height
        )
    }

    static func screen(containing point: CGPoint, in layouts: [ScreenLayout]) -> ScreenLayout? {
        layouts.first { $0.bounds.insetBy(dx: -1, dy: -1).contains(point) } ?? layouts.first
    }

    static func neighbor(of screen: ScreenLayout, toward direction: HorizontalDirection, in layouts: [ScreenLayout]) -> ScreenLayout? {
        neighbor(of: screen, inDirection: direction == .left ? FocusDirection.left : .right, in: layouts)
    }

    static func neighbor(of screen: ScreenLayout, inDirection direction: FocusDirection, in layouts: [ScreenLayout]) -> ScreenLayout? {
        layouts
            .filter { candidate in
                guard candidate != screen else { return false }
                switch direction {
                case .left:
                    return candidate.bounds.midX < screen.bounds.midX
                case .right:
                    return candidate.bounds.midX > screen.bounds.midX
                case .up:
                    return candidate.bounds.midY < screen.bounds.midY
                case .down:
                    return candidate.bounds.midY > screen.bounds.midY
                }
            }
            .min { distance($0, screen, direction: direction) < distance($1, screen, direction: direction) }
    }

    private static func distance(_ a: ScreenLayout, _ b: ScreenLayout, direction: FocusDirection = .left) -> CGFloat {
        switch direction {
        case .left, .right:
            return abs(a.bounds.midX - b.bounds.midX) + abs(a.bounds.midY - b.bounds.midY) * 2
        case .up, .down:
            return abs(a.bounds.midY - b.bounds.midY) + abs(a.bounds.midX - b.bounds.midX) * 2
        }
    }

    static func screen(for frame: CGRect, in layouts: [ScreenLayout]) -> ScreenLayout? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = layouts.first(where: { $0.bounds.contains(center) }) {
            return containing
        }
        return layouts.max { overlapArea(of: frame, with: $0.bounds) < overlapArea(of: frame, with: $1.bounds) }
    }

    private static func overlapArea(of frame: CGRect, with bounds: CGRect) -> CGFloat {
        let intersection = frame.intersection(bounds)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

enum SnapArea: CaseIterable, Sendable, Hashable {
    case leftHalf
    case rightHalf
    case bottomHalf
    case firstThird
    case centerThird
    case lastThird
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case maximize

    var action: WindowAction {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .bottomHalf: return .bottomHalf
        case .firstThird: return .firstThird
        case .centerThird: return .centerThird
        case .lastThird: return .lastThird
        case .topLeftQuarter: return .topLeftQuarter
        case .topRightQuarter: return .topRightQuarter
        case .bottomLeftQuarter: return .bottomLeftQuarter
        case .bottomRightQuarter: return .bottomRightQuarter
        case .maximize: return .maximize
        }
    }

    static func evaluate(
        mousePoint point: CGPoint,
        screen: ScreenLayout,
        threshold: CGFloat = 25,
        bottomEdge: BottomEdgeBehavior = .bottomHalf
    ) -> SnapArea? {
        guard screen.bounds.insetBy(dx: -1, dy: -1).contains(point) else { return nil }

        let edges = screen.visibleBounds
        let cornerThreshold = threshold * 2

        let nearLeft = point.x <= edges.minX + threshold
        let nearRight = point.x >= edges.maxX - threshold
        let nearTop = point.y <= edges.minY + threshold
        let nearBottom = point.y >= edges.maxY - threshold

        let cornerLeft = point.x <= edges.minX + cornerThreshold
        let cornerRight = point.x >= edges.maxX - cornerThreshold
        let cornerTop = point.y <= edges.minY + cornerThreshold
        let cornerBottom = point.y >= edges.maxY - cornerThreshold

        if (nearLeft && cornerTop) || (nearTop && cornerLeft) { return .topLeftQuarter }
        if (nearRight && cornerTop) || (nearTop && cornerRight) { return .topRightQuarter }
        if (nearLeft && cornerBottom) || (nearBottom && cornerLeft) { return .bottomLeftQuarter }
        if (nearRight && cornerBottom) || (nearBottom && cornerRight) { return .bottomRightQuarter }
        if nearTop { return .maximize }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearBottom { return bottomEdgeArea(at: point.x, edges: edges, behavior: bottomEdge) }
        return nil
    }

    private static func bottomEdgeArea(at x: CGFloat, edges: CGRect, behavior: BottomEdgeBehavior) -> SnapArea {
        guard behavior == .thirds else { return .bottomHalf }
        let progress = (x - edges.minX) / max(1, edges.width)
        if progress < 1.0 / 3.0 { return .firstThird }
        if progress < 2.0 / 3.0 { return .centerThird }
        return .lastThird
    }
}
