import CoreGraphics
import Foundation

enum RepeatBehavior: String, CaseIterable, Sendable {
    case cycleSizes
    case moveAcrossDisplays
    case none

    var title: String {
        Localization.language == .english ? englishTitle : portugueseTitle
    }

    var portugueseTitle: String {
        switch self {
        case .cycleSizes: return "Alterna entre ½, ⅔ e ⅓"
        case .moveAcrossDisplays: return "Move para a tela adjacente"
        case .none: return "Não faz nada"
        }
    }

    var englishTitle: String {
        switch self {
        case .cycleSizes: return "Cycles ½, ⅔ and ⅓"
        case .moveAcrossDisplays: return "Moves to the adjacent display"
        case .none: return "Does nothing"
        }
    }
}

enum BottomEdgeBehavior: String, CaseIterable, Sendable {
    case bottomHalf
    case thirds

    var title: String {
        Localization.language == .english ? englishTitle : portugueseTitle
    }

    var portugueseTitle: String {
        switch self {
        case .bottomHalf: return "Metade Inferior"
        case .thirds: return "Terços (Esq, Centro, Dir)"
        }
    }

    var englishTitle: String {
        switch self {
        case .bottomHalf: return "Bottom Half"
        case .thirds: return "Thirds"
        }
    }
}

enum DragModifier: String, CaseIterable, Sendable {
    case controlOption
    case controlCommand
    case optionCommand

    var modifiers: ShortcutModifiers {
        switch self {
        case .controlOption: return [.control, .option]
        case .controlCommand: return [.control, .command]
        case .optionCommand: return [.option, .command]
        }
    }

    var title: String {
        modifiers.displayString
    }
}

struct TileOptions: Sendable, Equatable {
    var margin: CGFloat = 0
    var gap: CGFloat = 0
    var step: CGFloat = 50
    var almostMaximizeRatio: CGFloat = 0.9
    var marginOnMaximize = true
}
