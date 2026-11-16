import AppKit
import CoreGraphics
import Foundation

enum TileCalculation {
    static func calculate(
        action: WindowAction,
        screen: ScreenLayout,
        currentFrame: CGRect,
        options: TileOptions = TileOptions(),
        cycleIndex: Int = 0
    ) -> CGRect {
        let margin = options.margin
        let gap = options.gap
        let step = options.step
        let base = screen.visibleBounds
        let usable = CGRect(
            x: base.origin.x + margin,
            y: base.origin.y + margin,
            width: max(100, base.size.width - (margin * 2)),
            height: max(100, base.size.height - (margin * 2))
        )

        let halfGap = gap / 2.0
        let cycle = cycleIndex % 3

        switch action {
        case .leftHalf:
            let w = splitDimension(total: usable.width, halfGap: halfGap, cycle: cycle)
            return CGRect(x: usable.minX, y: usable.minY, width: w, height: usable.height)

        case .rightHalf:
            let w = splitDimension(total: usable.width, halfGap: halfGap, cycle: cycle)
            let x = usable.maxX - w
            return CGRect(x: x, y: usable.minY, width: w, height: usable.height)

        case .topHalf:
            let h = splitDimension(total: usable.height, halfGap: halfGap, cycle: cycle)
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: h)

        case .bottomHalf:
            let h = splitDimension(total: usable.height, halfGap: halfGap, cycle: cycle)
            let y = usable.maxY - h
            return CGRect(x: usable.minX, y: y, width: usable.width, height: h)

        case .topLeftQuarter:
            return quarter(left: true, top: true, in: usable, halfGap: halfGap)

        case .topRightQuarter:
            return quarter(left: false, top: true, in: usable, halfGap: halfGap)

        case .bottomLeftQuarter:
            return quarter(left: true, top: false, in: usable, halfGap: halfGap)

        case .bottomRightQuarter:
            return quarter(left: false, top: false, in: usable, halfGap: halfGap)

        case .firstThird:
            let w = (usable.width / 3.0) - halfGap
            return CGRect(x: usable.minX, y: usable.minY, width: w, height: usable.height)

        case .centerThird:
            let w = (usable.width / 3.0) - gap
            let x = usable.minX + (usable.width / 3.0) + halfGap
            return CGRect(x: x, y: usable.minY, width: w, height: usable.height)

        case .lastThird:
            let w = (usable.width / 3.0) - halfGap
            return CGRect(x: usable.maxX - w, y: usable.minY, width: w, height: usable.height)

        case .firstTwoThirds:
            let w = (usable.width * 2.0 / 3.0) - halfGap
            return CGRect(x: usable.minX, y: usable.minY, width: w, height: usable.height)

        case .lastTwoThirds:
            let w = (usable.width * 2.0 / 3.0) - halfGap
            return CGRect(x: usable.maxX - w, y: usable.minY, width: w, height: usable.height)

        case .maximize:
            return options.marginOnMaximize ? usable : base

        case .almostMaximize:
            let inset = (1 - options.almostMaximizeRatio.clamped(to: 0.5...1)) / 2
            return usable.insetBy(dx: usable.width * inset, dy: usable.height * inset)

        case .maximizeHeight:
            return CGRect(x: currentFrame.origin.x, y: usable.minY, width: currentFrame.width, height: usable.height)

        case .maximizeWidth:
            return CGRect(x: usable.minX, y: currentFrame.origin.y, width: usable.width, height: currentFrame.height)

        case .center:
            var targetW = currentFrame.width
            var targetH = currentFrame.height
            if cycle == 1 {
                targetW = usable.width * 0.75
                targetH = usable.height * 0.75
            } else if cycle == 2 {
                targetW = usable.width * 0.50
                targetH = usable.height * 0.50
            }
            targetW = min(targetW, usable.width)
            targetH = min(targetH, usable.height)
            let x = usable.minX + (usable.width - targetW) / 2.0
            let y = usable.minY + (usable.height - targetH) / 2.0
            return CGRect(x: x, y: y, width: targetW, height: targetH)

        case .restore, .nextDisplay, .previousDisplay, .focusLeft, .focusRight, .focusUp, .focusDown:
            return currentFrame

        case .moveLeft:
            let x = max(usable.minX, currentFrame.origin.x - step)
            return CGRect(x: x, y: currentFrame.origin.y, width: currentFrame.width, height: currentFrame.height)

        case .moveRight:
            let x = min(usable.maxX - currentFrame.width, currentFrame.origin.x + step)
            return CGRect(x: x, y: currentFrame.origin.y, width: currentFrame.width, height: currentFrame.height)

        case .moveUp:
            let y = max(usable.minY, currentFrame.origin.y - step)
            return CGRect(x: currentFrame.origin.x, y: y, width: currentFrame.width, height: currentFrame.height)

        case .moveDown:
            let y = min(usable.maxY - currentFrame.height, currentFrame.origin.y + step)
            return CGRect(x: currentFrame.origin.x, y: y, width: currentFrame.width, height: currentFrame.height)

        case .makeLarger:
            let newW = min(usable.width, currentFrame.width + step)
            let newH = min(usable.height, currentFrame.height + step)
            let deltaW = newW - currentFrame.width
            let deltaH = newH - currentFrame.height
            let newX = max(usable.minX, min(usable.maxX - newW, currentFrame.origin.x - (deltaW / 2.0)))
            let newY = max(usable.minY, min(usable.maxY - newH, currentFrame.origin.y - (deltaH / 2.0)))
            return CGRect(x: newX, y: newY, width: newW, height: newH)

        case .makeSmaller:
            let newW = max(200, currentFrame.width - step)
            let newH = max(150, currentFrame.height - step)
            let deltaW = currentFrame.width - newW
            let deltaH = currentFrame.height - newH
            let newX = currentFrame.origin.x + (deltaW / 2.0)
            let newY = currentFrame.origin.y + (deltaH / 2.0)
            return CGRect(x: newX, y: newY, width: newW, height: newH)
        }
    }

    private static func quarter(left: Bool, top: Bool, in usable: CGRect, halfGap: CGFloat) -> CGRect {
        CGRect(
            x: left ? usable.minX : usable.midX + halfGap,
            y: top ? usable.minY : usable.midY + halfGap,
            width: (usable.width / 2.0) - halfGap,
            height: (usable.height / 2.0) - halfGap
        )
    }

    private static func splitDimension(total: CGFloat, halfGap: CGFloat, cycle: Int) -> CGFloat {
        if cycle == 1 {
            return (total * 2.0 / 3.0) - halfGap
        } else if cycle == 2 {
            return (total / 3.0) - halfGap
        } else {
            return (total / 2.0) - halfGap
        }
    }

    static func translate(
        frame: CGRect,
        from source: ScreenLayout,
        to target: ScreenLayout
    ) -> CGRect {
        let src = source.visibleBounds
        let dst = target.visibleBounds

        let relX = (frame.origin.x - src.origin.x) / max(1, src.width)
        let relY = (frame.origin.y - src.origin.y) / max(1, src.height)
        let relW = frame.width / max(1, src.width)
        let relH = frame.height / max(1, src.height)

        let targetW = min(dst.width, max(200, relW * dst.width))
        let targetH = min(dst.height, max(150, relH * dst.height))
        let targetX = dst.origin.x + (relX * dst.width)
        let targetY = dst.origin.y + (relY * dst.height)

        let clampedX = min(max(dst.minX, targetX), dst.maxX - targetW)
        let clampedY = min(max(dst.minY, targetY), dst.maxY - targetH)

        return CGRect(x: clampedX, y: clampedY, width: targetW, height: targetH)
    }

    static func traversalTarget(
        for action: WindowAction,
        frame: CGRect,
        screen: ScreenLayout,
        layouts: [ScreenLayout],
        options: TileOptions = TileOptions(),
        wasJustApplied: Bool = false
    ) -> (CGRect, ScreenLayout)? {
        guard layouts.count > 1 else { return nil }

        let margin = options.margin
        let base = screen.visibleBounds
        let usable = CGRect(
            x: base.origin.x + margin,
            y: base.origin.y + margin,
            width: max(100, base.size.width - (margin * 2)),
            height: max(100, base.size.height - (margin * 2))
        )

        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .firstThird, .lastThird, .firstTwoThirds, .lastTwoThirds,
             .topLeftQuarter, .bottomLeftQuarter, .topRightQuarter, .bottomRightQuarter:
            let direction: FocusDirection
            let landing: WindowAction
            switch action {
            case .leftHalf:
                direction = .left
                landing = .rightHalf
            case .rightHalf:
                direction = .right
                landing = .leftHalf
            case .topHalf:
                direction = .up
                landing = .bottomHalf
            case .bottomHalf:
                direction = .down
                landing = .topHalf
            case .firstThird:
                direction = .left
                landing = .lastThird
            case .lastThird:
                direction = .right
                landing = .firstThird
            case .firstTwoThirds:
                direction = .left
                landing = .lastTwoThirds
            case .lastTwoThirds:
                direction = .right
                landing = .firstTwoThirds
            case .topLeftQuarter:
                direction = .left
                landing = .topRightQuarter
            case .bottomLeftQuarter:
                direction = .left
                landing = .bottomRightQuarter
            case .topRightQuarter:
                direction = .right
                landing = .topLeftQuarter
            case .bottomRightQuarter:
                direction = .right
                landing = .bottomLeftQuarter
            default:
                return nil
            }

            let occupied = calculate(action: action, screen: screen, currentFrame: frame, options: options, cycleIndex: 0)
            let isAtEdge: Bool = {
                if wasJustApplied || frame.isApproximatelyEqual(to: occupied, tolerance: 36) {
                    return true
                }

                switch direction {
                case .left:
                    return abs(frame.minX - occupied.minX) <= 36
                        && frame.midX <= usable.midX + 24
                case .right:
                    return abs(frame.maxX - occupied.maxX) <= 36
                        && frame.midX >= usable.midX - 24
                case .up:
                    return abs(frame.minY - occupied.minY) <= 36
                        && frame.midY <= usable.midY + 24
                case .down:
                    return abs(frame.maxY - occupied.maxY) <= 36
                        && frame.midY >= usable.midY - 24
                }
            }()

            guard isAtEdge,
                  let neighbor = ScreenLayout.neighbor(of: screen, inDirection: direction, in: layouts) else {
                return nil
            }
            let target = calculate(action: landing, screen: neighbor, currentFrame: frame, options: options, cycleIndex: 0)
            return (target, neighbor)

        case .moveLeft, .moveRight, .moveUp, .moveDown:
            let direction: FocusDirection
            let isAtBoundary: Bool
            let nextStepFrame = calculate(action: action, screen: screen, currentFrame: frame, options: options, cycleIndex: 0)
            let cannotStepFurther = nextStepFrame.origin.distance(to: frame.origin) <= 2
            switch action {
            case .moveLeft:
                direction = .left
                isAtBoundary = frame.minX <= usable.minX + 24 || (wasJustApplied && cannotStepFurther)
            case .moveRight:
                direction = .right
                isAtBoundary = frame.maxX >= usable.maxX - 24 || (wasJustApplied && cannotStepFurther)
            case .moveUp:
                direction = .up
                isAtBoundary = frame.minY <= usable.minY + 24 || (wasJustApplied && cannotStepFurther)
            case .moveDown:
                direction = .down
                isAtBoundary = frame.maxY >= usable.maxY - 24 || (wasJustApplied && cannotStepFurther)
            default:
                return nil
            }

            guard isAtBoundary,
                  let neighbor = ScreenLayout.neighbor(of: screen, inDirection: direction, in: layouts) else {
                return nil
            }

            let dstBase = neighbor.visibleBounds
            let dstUsable = CGRect(
                x: dstBase.origin.x + margin,
                y: dstBase.origin.y + margin,
                width: max(100, dstBase.size.width - (margin * 2)),
                height: max(100, dstBase.size.height - (margin * 2))
            )
            let width = min(frame.width, dstUsable.width)
            let height = min(frame.height, dstUsable.height)
            let relY = ((frame.minY - usable.minY) / max(1, usable.height)).clamped(to: 0...1)
            let relX = ((frame.minX - usable.minX) / max(1, usable.width)).clamped(to: 0...1)

            let targetX: CGFloat
            let targetY: CGFloat
            switch direction {
            case .left:
                targetX = dstUsable.maxX - width
                targetY = min(max(dstUsable.minY, dstUsable.minY + relY * (dstUsable.height - height)), dstUsable.maxY - height)
            case .right:
                targetX = dstUsable.minX
                targetY = min(max(dstUsable.minY, dstUsable.minY + relY * (dstUsable.height - height)), dstUsable.maxY - height)
            case .up:
                targetX = min(max(dstUsable.minX, dstUsable.minX + relX * (dstUsable.width - width)), dstUsable.maxX - width)
                targetY = dstUsable.maxY - height
            case .down:
                targetX = min(max(dstUsable.minX, dstUsable.minX + relX * (dstUsable.width - width)), dstUsable.maxX - width)
                targetY = dstUsable.minY
            }
            return (CGRect(x: targetX, y: targetY, width: width, height: height), neighbor)

        default:
            return nil
        }
    }
}
