import SwiftUI

nonisolated struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var earRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            AnimatablePair(AnimatablePair(topCornerRadius, bottomCornerRadius), earRadius)
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            earRadius = newValue.second
        }
    }

    init(topCornerRadius: CGFloat = 8, bottomCornerRadius: CGFloat = 14, earRadius: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.earRadius = earRadius
    }

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, hasTopEars: Bool) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.earRadius = hasTopEars ? topCornerRadius : 0
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let earR = max(0, min(earRadius, h / 2, w / 4))
        let botR = max(0, min(bottomCornerRadius, (h - earR), (w - earR * 2) / 2))

        path.move(to: CGPoint(x: 0, y: 0))

        if earR > 0.1 {

            path.addCurve(
                to: CGPoint(x: earR, y: earR),
                control1: CGPoint(x: earR * 0.55, y: 0),
                control2: CGPoint(x: earR, y: earR * 0.45)
            )
        }

        let leftCornerStart = max(earR, h - botR)
        path.addLine(to: CGPoint(x: earR, y: leftCornerStart))

        path.addCurve(
            to: CGPoint(x: earR + botR, y: h),
            control1: CGPoint(x: earR, y: h - botR * 0.36),
            control2: CGPoint(x: earR + botR * 0.36, y: h)
        )

        path.addLine(to: CGPoint(x: max(earR + botR, w - earR - botR), y: h))

        path.addCurve(
            to: CGPoint(x: w - earR, y: leftCornerStart),
            control1: CGPoint(x: w - earR - botR * 0.36, y: h),
            control2: CGPoint(x: w - earR, y: h - botR * 0.36)
        )

        path.addLine(to: CGPoint(x: w - earR, y: earR))

        if earR > 0.1 {

            path.addCurve(
                to: CGPoint(x: w, y: 0),
                control1: CGPoint(x: w - earR, y: earR * 0.45),
                control2: CGPoint(x: w - earR * 0.55, y: 0)
            )
        }

        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()

        return path
    }
}
