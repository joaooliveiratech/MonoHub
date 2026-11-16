import Foundation
import CoreGraphics

struct RGBAColor: Sendable, Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let red = RGBAColor(r: 0.95, g: 0.25, b: 0.25, a: 1.0)
    static let orange = RGBAColor(r: 1.0, g: 0.55, b: 0.1, a: 1.0)
    static let yellow = RGBAColor(r: 0.98, g: 0.82, b: 0.18, a: 1.0)
    static let green = RGBAColor(r: 0.22, g: 0.82, b: 0.44, a: 1.0)
    static let blue = RGBAColor(r: 0.18, g: 0.55, b: 1.0, a: 1.0)
    static let purple = RGBAColor(r: 0.65, g: 0.35, b: 0.95, a: 1.0)
    static let white = RGBAColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    static let black = RGBAColor(r: 0.08, g: 0.08, b: 0.1, a: 1.0)

    var cgColor: CGColor {
        CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var hexString: String {
        let redInt = Int((r * 255).rounded())
        let greenInt = Int((g * 255).rounded())
        let blueInt = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", redInt, greenInt, blueInt)
    }
}

enum AnnotationElement: Sendable, Identifiable, Equatable {
    case arrow(ArrowAnnotation)
    case rectangle(RectAnnotation)
    case counter(CounterAnnotation)
    case text(TextAnnotation)
    case censor(CensorAnnotation)

    var id: UUID {
        switch self {
        case .arrow(let a): return a.id
        case .rectangle(let r): return r.id
        case .counter(let c): return c.id
        case .text(let t): return t.id
        case .censor(let cs): return cs.id
        }
    }

    var supportsColor: Bool {
        switch self {
        case .arrow, .rectangle, .counter, .text:
            return true
        case .censor:
            return false
        }
    }

    var color: RGBAColor? {
        switch self {
        case .arrow(let a): return a.color
        case .rectangle(let r): return r.color
        case .counter(let c): return c.color
        case .text(let t): return t.color
        case .censor: return nil
        }
    }

    var boundingBox: CGRect {
        switch self {
        case .arrow(let a):
            let minX = min(a.start.x, a.end.x, a.controlPoint?.x ?? a.start.x)
            let maxX = max(a.start.x, a.end.x, a.controlPoint?.x ?? a.start.x)
            let minY = min(a.start.y, a.end.y, a.controlPoint?.y ?? a.start.y)
            let maxY = max(a.start.y, a.end.y, a.controlPoint?.y ?? a.start.y)
            return CGRect(x: minX, y: minY, width: max(16, maxX - minX), height: max(16, maxY - minY)).insetBy(dx: -8, dy: -8)

        case .rectangle(let r):
            return r.rect.insetBy(dx: -6, dy: -6)

        case .counter(let c):
            return CGRect(
                x: c.center.x - c.radius,
                y: c.center.y - c.radius,
                width: c.radius * 2,
                height: c.radius * 2
            ).insetBy(dx: -4, dy: -4)

        case .text(let t):
            let size = TextMetrics.size(of: t.text, fontSize: t.fontSize)
            return CGRect(origin: t.origin, size: size).insetBy(dx: -6, dy: -6)

        case .censor(let cs):
            return cs.rect.insetBy(dx: -4, dy: -4)
        }
    }

    func contains(point: CGPoint) -> Bool {
        switch self {
        case .arrow(let a):
            if let ctrl = a.controlPoint {
                let d1 = distanceToSegment(p: point, a: a.start, b: ctrl)
                let d2 = distanceToSegment(p: point, a: ctrl, b: a.end)
                return min(d1, d2) <= 16.0
            } else {
                return distanceToSegment(p: point, a: a.start, b: a.end) <= 16.0
            }

        case .rectangle(let r):
            if r.isFilled {
                return r.rect.contains(point)
            } else {
                let outer = r.rect.insetBy(dx: -12, dy: -12)
                let inner = r.rect.insetBy(dx: 12, dy: 12)
                return outer.contains(point) && !inner.contains(point)
            }

        case .counter(let c):
            return hypot(point.x - c.center.x, point.y - c.center.y) <= (c.radius + 8)

        case .text(let t):
            let size = TextMetrics.size(of: t.text, fontSize: t.fontSize)
            return CGRect(origin: t.origin, size: size).insetBy(dx: -8, dy: -8).contains(point)

        case .censor(let cs):
            return cs.rect.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    func moved(by delta: CGSize) -> AnnotationElement {
        switch self {
        case .arrow(var a):
            a.start.x += delta.width
            a.start.y += delta.height
            a.end.x += delta.width
            a.end.y += delta.height
            if var ctrl = a.controlPoint {
                ctrl.x += delta.width
                ctrl.y += delta.height
                a.controlPoint = ctrl
            }
            return .arrow(a)

        case .rectangle(var r):
            r.rect.origin.x += delta.width
            r.rect.origin.y += delta.height
            return .rectangle(r)

        case .counter(var c):
            c.center.x += delta.width
            c.center.y += delta.height
            return .counter(c)

        case .text(var t):
            t.origin.x += delta.width
            t.origin.y += delta.height
            return .text(t)

        case .censor(var cs):
            cs.rect.origin.x += delta.width
            cs.rect.origin.y += delta.height
            return .censor(cs)
        }
    }

    func withColor(_ color: RGBAColor) -> AnnotationElement {
        switch self {
        case .arrow(var a):
            a.color = color
            return .arrow(a)
        case .rectangle(var r):
            r.color = color
            return .rectangle(r)
        case .counter(var c):
            c.color = color
            return .counter(c)
        case .text(var t):
            t.color = color
            return .text(t)
        case .censor:
            return self
        }
    }
}

private func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSq = dx * dx + dy * dy
    if lengthSq == 0 {
        return hypot(p.x - a.x, p.y - a.y)
    }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq))
    let projX = a.x + t * dx
    let projY = a.y + t * dy
    return hypot(p.x - projX, p.y - projY)
}

struct ArrowAnnotation: Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var start: CGPoint
    var end: CGPoint
    var controlPoint: CGPoint?
    var strokeWidth: CGFloat = 4.0
    var color: RGBAColor = .red

    static func defaultControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let perpX = -(end.y - start.y) * 0.15
        let perpY = (end.x - start.x) * 0.15
        return CGPoint(x: midX + perpX, y: midY + perpY)
    }
}

struct RectAnnotation: Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var rect: CGRect
    var cornerRadius: CGFloat = 8.0
    var strokeWidth: CGFloat = 4.0
    var isFilled: Bool = false
    var color: RGBAColor = .red
}

struct CounterAnnotation: Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var center: CGPoint
    var number: Int
    var radius: CGFloat = 16.0
    var color: RGBAColor = .red
}

struct TextAnnotation: Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var origin: CGPoint
    var text: String
    var fontSize: CGFloat = 18.0
    var color: RGBAColor = .red
}

struct CensorAnnotation: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable, Codable, Equatable {
        case pixelate
        case blur
    }
    var id: UUID = UUID()
    var rect: CGRect
    var kind: Kind = .pixelate
    var scale: CGFloat = 20.0
}
