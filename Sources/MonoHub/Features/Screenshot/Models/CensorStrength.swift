import Foundation

enum CensorStrength: CGFloat, CaseIterable, Sendable {
    case soft = 32
    case medium = 56
    case strong = 90

    var displayName: String {
        switch self {
        case .soft: return ShotText.censorSoft
        case .medium: return ShotText.censorMedium
        case .strong: return ShotText.censorStrong
        }
    }

    var scale: CGFloat { rawValue }

    static let `default`: CensorStrength = .medium

    static func nearest(to scale: CGFloat) -> CensorStrength {
        allCases.min(by: { abs($0.rawValue - scale) < abs($1.rawValue - scale) }) ?? .default
    }
}
