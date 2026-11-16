import Foundation

enum ToolMode: String, CaseIterable, Sendable {
    case select
    case arrow
    case curvedArrow
    case rectangle
    case counter
    case text
    case blur
    case pixelate

    var displayName: String {
        switch self {
        case .select: return ShotText.toolSelect
        case .arrow: return ShotText.toolArrow
        case .curvedArrow: return ShotText.toolCurvedArrow
        case .rectangle: return ShotText.toolRectangle
        case .counter: return ShotText.toolCounter
        case .text: return ShotText.toolText
        case .blur: return ShotText.toolBlur
        case .pixelate: return ShotText.toolPixelate
        }
    }

    var shortcutNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func forShortcutNumber(_ number: Int) -> ToolMode? {
        allCases.indices.contains(number - 1) ? allCases[number - 1] : nil
    }

    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .curvedArrow: return "arrow.turn.up.right"
        case .rectangle: return "rectangle"
        case .counter: return "1.circle"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .pixelate: return "checkerboard.rectangle"
        }
    }

    var supportsColor: Bool {
        switch self {
        case .arrow, .curvedArrow, .rectangle, .counter, .text:
            return true
        case .select, .blur, .pixelate:
            return false
        }
    }

    var isCensor: Bool {
        self == .blur || self == .pixelate
    }

    var censorKind: CensorAnnotation.Kind? {
        switch self {
        case .blur: return .blur
        case .pixelate: return .pixelate
        default: return nil
        }
    }
}
