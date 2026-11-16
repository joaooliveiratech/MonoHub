import CoreGraphics
import Foundation

enum WindowNavigator {
    static func nearest(from source: CGRect, toward direction: FocusDirection, among candidates: [CGRect]) -> Int? {
        var best: (index: Int, score: CGFloat)?

        for (index, candidate) in candidates.enumerated()
        where !candidate.isApproximatelyEqual(to: source) && isBeyondCenter(candidate, of: source, toward: direction) {
            let dx = candidate.midX - source.midX
            let dy = candidate.midY - source.midY
            let (primary, secondary): (CGFloat, CGFloat)
            switch direction {
            case .left: (primary, secondary) = (-dx, dy)
            case .right: (primary, secondary) = (dx, dy)
            case .up: (primary, secondary) = (-dy, dx)
            case .down: (primary, secondary) = (dy, dx)
            }
            guard primary > 1 else { continue }

            let score = primary + abs(secondary) * 2
            if score < best?.score ?? .infinity {
                best = (index, score)
            }
        }
        return best?.index
    }

    private static func isBeyondCenter(_ candidate: CGRect, of source: CGRect, toward direction: FocusDirection) -> Bool {
        switch direction {
        case .left: return candidate.maxX <= source.midX
        case .right: return candidate.minX >= source.midX
        case .up: return candidate.maxY <= source.midY
        case .down: return candidate.minY >= source.midY
        }
    }
}
