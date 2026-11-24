import CoreGraphics
import Foundation

struct WindowNavigationCandidate: Sendable {
    let windowID: CGWindowID
    let bounds: CGRect
    let mruRank: Int?

    init(windowID: CGWindowID = 0, bounds: CGRect, mruRank: Int? = nil) {
        self.windowID = windowID
        self.bounds = bounds
        self.mruRank = mruRank
    }
}

enum WindowNavigator {
    /// Simple geometric directional lookup (kept for lightweight callers and backwards compatibility).
    static func nearest(from source: CGRect, toward direction: FocusDirection, among candidates: [CGRect]) -> Int? {
        let wrapped = candidates.enumerated().map { WindowNavigationCandidate(windowID: CGWindowID($0.offset + 1), bounds: $0.element) }
        return smartNearest(from: source, toward: direction, among: wrapped)
    }

    /// Market-standard directional focus scoring (inspired by i3 / Sway / Hyprland / AeroSpace):
    /// 1. Rewards perpendicular overlap so directly adjacent tiled windows always beat diagonal ones.
    /// 2. Supports partially overlapping windows (checks center progression rather than hard midpoint cutoffs).
    /// 3. Uses MRU recency tie-breaking when two candidates have comparable geometric proximity
    ///    (e.g., two stacked quarters beside a tall half-screen window -> returns to the last-used quarter).
    static func smartNearest(
        from source: CGRect,
        toward direction: FocusDirection,
        among candidates: [WindowNavigationCandidate],
        sourceWindowID: CGWindowID? = nil
    ) -> Int? {
        struct Scored {
            let index: Int
            let edgeDistance: CGFloat
            let geometricScore: CGFloat
            let hasOverlap: Bool
            let mruRank: Int
        }

        var scoredCandidates: [Scored] = []
        scoredCandidates.reserveCapacity(candidates.count)

        for (index, item) in candidates.enumerated() {
            if let sourceWindowID, item.windowID == sourceWindowID { continue }
            let candidate = item.bounds
            if candidate.isApproximatelyEqual(to: source) { continue }

            let dx = candidate.midX - source.midX
            let dy = candidate.midY - source.midY

            let primaryCenter: CGFloat
            let secondaryCenter: CGFloat
            let edgeGap: CGFloat
            let overlap: CGFloat
            let sourceSpan: CGFloat
            let clearsMidpoint: Bool

            switch direction {
            case .left:
                primaryCenter = -dx
                secondaryCenter = abs(dy)
                guard candidate.minX < source.minX - 2, primaryCenter > 4 else { continue }
                edgeGap = max(0, source.minX - candidate.maxX)
                overlap = max(0, min(source.maxY, candidate.maxY) - max(source.minY, candidate.minY))
                sourceSpan = max(1, source.height)
                clearsMidpoint = candidate.maxX <= source.midX

            case .right:
                primaryCenter = dx
                secondaryCenter = abs(dy)
                guard candidate.maxX > source.maxX + 2, primaryCenter > 4 else { continue }
                edgeGap = max(0, candidate.minX - source.maxX)
                overlap = max(0, min(source.maxY, candidate.maxY) - max(source.minY, candidate.minY))
                sourceSpan = max(1, source.height)
                clearsMidpoint = candidate.minX >= source.midX

            case .up:
                primaryCenter = -dy
                secondaryCenter = abs(dx)
                guard candidate.minY < source.minY - 2, primaryCenter > 4 else { continue }
                edgeGap = max(0, source.minY - candidate.maxY)
                overlap = max(0, min(source.maxX, candidate.maxX) - max(source.minX, candidate.minX))
                sourceSpan = max(1, source.width)
                clearsMidpoint = candidate.maxY <= source.midY

            case .down:
                primaryCenter = dy
                secondaryCenter = abs(dx)
                guard candidate.maxY > source.maxY + 2, primaryCenter > 4 else { continue }
                edgeGap = max(0, candidate.minY - source.maxY)
                overlap = max(0, min(source.maxX, candidate.maxX) - max(source.minX, candidate.minX))
                sourceSpan = max(1, source.width)
                clearsMidpoint = candidate.minY >= source.midY
            }

            let overlapRatio = min(1, overlap / sourceSpan)
            let hasOverlap = overlap > 8
            guard hasOverlap || clearsMidpoint else { continue }

            // Directly aligned neighbors (high perpendicular overlap) strongly outrank diagonal ones.
            let alignmentPenalty: CGFloat = hasOverlap
                ? secondaryCenter * (0.45 + (1 - overlapRatio) * 0.65)
                : secondaryCenter * 2.2 + 450

            let score = edgeGap * 1.4 + primaryCenter * 0.35 + alignmentPenalty

            scoredCandidates.append(
                Scored(
                    index: index,
                    edgeDistance: edgeGap,
                    geometricScore: score,
                    hasOverlap: hasOverlap,
                    mruRank: item.mruRank ?? Int.max
                )
            )
        }

        guard let bestGeometric = scoredCandidates.min(by: { $0.geometricScore < $1.geometricScore }) else {
            return nil
        }

        // MRU tie-breaker: among overlapping neighbors at essentially the same adjacent column/row
        // (e.g., stacked Top-Right and Bottom-Right tiles next to a full-height Left Half),
        // prefer the most recently focused window!
        if bestGeometric.hasOverlap {
            let edgeTolerance: CGFloat = 48
            let sameBand = scoredCandidates.filter {
                $0.hasOverlap
                    && abs($0.edgeDistance - bestGeometric.edgeDistance) <= edgeTolerance
                    && $0.mruRank < Int.max
            }
            if let mruWinner = sameBand.min(by: { lhs, rhs in
                if lhs.mruRank != rhs.mruRank { return lhs.mruRank < rhs.mruRank }
                return lhs.geometricScore < rhs.geometricScore
            }) {
                return mruWinner.index
            }
        }

        return bestGeometric.index
    }

    /// Wrap-around candidate when reaching an edge with no neighbor in `direction`:
    /// picks the farthest window on the opposite edge (e.g. pressing Left at the leftmost tile wraps to the rightmost tile).
    static func wrapAround(
        from source: CGRect,
        toward direction: FocusDirection,
        among candidates: [WindowNavigationCandidate],
        sourceWindowID: CGWindowID? = nil
    ) -> Int? {
        var best: (index: Int, score: CGFloat, mruRank: Int)?

        for (index, item) in candidates.enumerated() {
            if let sourceWindowID, item.windowID == sourceWindowID { continue }
            let candidate = item.bounds
            if candidate.isApproximatelyEqual(to: source) { continue }

            let primaryCoordinate: CGFloat
            let secondaryDistance: CGFloat
            switch direction {
            case .left:
                // Wrap to rightmost window
                primaryCoordinate = -candidate.midX
                secondaryDistance = abs(candidate.midY - source.midY)
            case .right:
                // Wrap to leftmost window
                primaryCoordinate = candidate.midX
                secondaryDistance = abs(candidate.midY - source.midY)
            case .up:
                // Wrap to bottommost window
                primaryCoordinate = -candidate.midY
                secondaryDistance = abs(candidate.midX - source.midX)
            case .down:
                // Wrap to topmost window
                primaryCoordinate = candidate.midY
                secondaryDistance = abs(candidate.midX - source.midX)
            }

            let score = primaryCoordinate + secondaryDistance * 0.25
            let rank = item.mruRank ?? Int.max
            if let current = best {
                if abs(score - current.score) <= 32, rank != current.mruRank {
                    if rank < current.mruRank {
                        best = (index, score, rank)
                    }
                } else if score < current.score {
                    best = (index, score, rank)
                }
            } else {
                best = (index, score, rank)
            }
        }

        return best?.index
    }
}
