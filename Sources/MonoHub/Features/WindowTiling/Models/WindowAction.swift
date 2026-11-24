import Carbon.HIToolbox
import Foundation

enum ActionCategory: String, CaseIterable, Sendable {
    case halves = "Halves"
    case quarters = "Quarters"
    case thirds = "Thirds"
    case sizeAndPosition = "Size & Position"
    case displays = "Displays"
    case nudgeAndResize = "Move & Resize"
    case focus = "Focus"

    var title: String {
        Localization.language == .english ? englishTitle : portugueseTitle
    }

    var portugueseTitle: String {
        switch self {
        case .halves: return "Metades"
        case .quarters: return "Quadrantes"
        case .thirds: return "Terços"
        case .sizeAndPosition: return "Tamanho & Posição"
        case .displays: return "Monitores & Telas"
        case .nudgeAndResize: return "Ajustar & Redimensionar"
        case .focus: return "Foco & Alternância"
        }
    }

    var englishTitle: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .halves: return "rectangle.split.2x1"
        case .quarters: return "square.grid.2x2"
        case .thirds: return "rectangle.split.3x1"
        case .sizeAndPosition: return "macwindow"
        case .displays: return "display.2"
        case .nudgeAndResize: return "arrow.up.and.down.and.arrow.left.and.right"
        case .focus: return "scope"
        }
    }

    var showsAsSubmenu: Bool {
        self == .nudgeAndResize || self == .focus
    }

    var actions: [WindowAction] {
        WindowAction.allCases.filter { $0.category == self }
    }
}

enum WindowAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf

    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter

    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds

    case maximize
    case almostMaximize
    case maximizeHeight
    case maximizeWidth
    case center
    case restore

    case nextDisplay
    case previousDisplay

    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case makeLarger
    case makeSmaller

    case focusLeft
    case focusRight
    case focusUp
    case focusDown
    case focusLastWindow
    case focusQueueNext
    case focusQueuePrevious
    case swapWithLastWindow

    var id: String { rawValue }

    var commandName: String {
        rawValue.reduce(into: "") { name, character in
            if character.isUppercase {
                name += "-" + character.lowercased()
            } else {
                name.append(character)
            }
        }
    }

    init?(commandName: String) {
        let normalized = commandName.lowercased()
        guard let match = Self.allCases.first(where: { $0.commandName == normalized || $0.rawValue.lowercased() == normalized }) else {
            return nil
        }
        self = match
    }

    var focusDirection: FocusDirection? {
        switch self {
        case .focusLeft: return .left
        case .focusRight: return .right
        case .focusUp: return .up
        case .focusDown: return .down
        default: return nil
        }
    }

    var isFocusOrSwitchAction: Bool {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown,
             .focusLastWindow, .focusQueueNext, .focusQueuePrevious, .swapWithLastWindow:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        Localization.language == .english ? englishDisplayName : portugueseDisplayName
    }

    var portugueseDisplayName: String {
        switch self {
        case .leftHalf: return "Metade Esquerda"
        case .rightHalf: return "Metade Direita"
        case .topHalf: return "Metade Superior"
        case .bottomHalf: return "Metade Inferior"

        case .topLeftQuarter: return "Superior Esquerdo"
        case .topRightQuarter: return "Superior Direito"
        case .bottomLeftQuarter: return "Inferior Esquerdo"
        case .bottomRightQuarter: return "Inferior Direito"

        case .firstThird: return "Primeiro Terço"
        case .centerThird: return "Terço Central"
        case .lastThird: return "Último Terço"
        case .firstTwoThirds: return "Primeiros Dois Terços"
        case .lastTwoThirds: return "Últimos Dois Terços"

        case .maximize: return "Maximizar"
        case .almostMaximize: return "Quase Maximizar"
        case .maximizeHeight: return "Maximizar Altura"
        case .maximizeWidth: return "Maximizar Largura"
        case .center: return "Centralizar"
        case .restore: return "Restaurar (Desfazer)"

        case .nextDisplay: return "Próximo Monitor"
        case .previousDisplay: return "Monitor Anterior"

        case .moveLeft: return "Mover para Esquerda"
        case .moveRight: return "Mover para Direita"
        case .moveUp: return "Mover para Cima"
        case .moveDown: return "Mover para Baixo"
        case .makeLarger: return "Aumentar Janela"
        case .makeSmaller: return "Diminuir Janela"

        case .focusLeft: return "Focar Janela à Esquerda"
        case .focusRight: return "Focar Janela à Direita"
        case .focusUp: return "Focar Janela Acima"
        case .focusDown: return "Focar Janela Abaixo"
        case .focusLastWindow: return "Alternar Última Janela"
        case .focusQueueNext: return "Próxima na Fila de Foco"
        case .focusQueuePrevious: return "Anterior na Fila de Foco"
        case .swapWithLastWindow: return "Trocar Posição com Última Janela"
        }
    }

    var englishDisplayName: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"

        case .topLeftQuarter: return "Top Left"
        case .topRightQuarter: return "Top Right"
        case .bottomLeftQuarter: return "Bottom Left"
        case .bottomRightQuarter: return "Bottom Right"

        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"

        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .maximizeHeight: return "Maximize Height"
        case .maximizeWidth: return "Maximize Width"
        case .center: return "Center"
        case .restore: return "Restore"

        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"

        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        case .makeLarger: return "Make Larger"
        case .makeSmaller: return "Make Smaller"

        case .focusLeft: return "Focus Left"
        case .focusRight: return "Focus Right"
        case .focusUp: return "Focus Up"
        case .focusDown: return "Focus Down"
        case .focusLastWindow: return "Switch to Last Window"
        case .focusQueueNext: return "Next in Focus Queue"
        case .focusQueuePrevious: return "Previous in Focus Queue"
        case .swapWithLastWindow: return "Swap with Last Window"
        }
    }

    var category: ActionCategory {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return .quarters
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            return .thirds
        case .maximize, .almostMaximize, .maximizeHeight, .maximizeWidth, .center, .restore:
            return .sizeAndPosition
        case .nextDisplay, .previousDisplay:
            return .displays
        case .moveLeft, .moveRight, .moveUp, .moveDown, .makeLarger, .makeSmaller:
            return .nudgeAndResize
        case .focusLeft, .focusRight, .focusUp, .focusDown,
             .focusLastWindow, .focusQueueNext, .focusQueuePrevious, .swapWithLastWindow:
            return .focus
        }
    }

    var sfSymbol: String {
        switch self {
        case .leftHalf: return "rectangle.leadinghalf.inset.filled"
        case .rightHalf: return "rectangle.trailinghalf.inset.filled"
        case .topHalf: return "rectangle.tophalf.inset.filled"
        case .bottomHalf: return "rectangle.bottomhalf.inset.filled"

        case .topLeftQuarter: return "rectangle.inset.topleft.filled"
        case .topRightQuarter: return "rectangle.inset.topright.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleft.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomright.filled"

        case .firstThird: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.split.3x1"
        case .lastThird: return "rectangle.trailingthird.inset.filled"
        case .firstTwoThirds: return "rectangle.lefthalf.filled"
        case .lastTwoThirds: return "rectangle.righthalf.filled"

        case .maximize: return "rectangle.fill"
        case .almostMaximize: return "rectangle.inset.filled"
        case .maximizeHeight: return "arrow.up.and.down"
        case .maximizeWidth: return "arrow.left.and.right"
        case .center: return "rectangle.center.inset.filled"
        case .restore: return "arrow.uturn.backward"

        case .nextDisplay: return "arrow.forward.to.line.square"
        case .previousDisplay: return "arrow.backward.to.line.square"

        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        case .makeLarger: return "arrow.up.left.and.arrow.down.right"
        case .makeSmaller: return "arrow.down.right.and.arrow.up.left"

        case .focusLeft: return "arrow.left.circle"
        case .focusRight: return "arrow.right.circle"
        case .focusUp: return "arrow.up.circle"
        case .focusDown: return "arrow.down.circle"
        case .focusLastWindow: return "arrow.left.arrow.right.circle"
        case .focusQueueNext: return "rectangle.stack.badge.play"
        case .focusQueuePrevious: return "arrow.uturn.left.circle"
        case .swapWithLastWindow: return "rectangle.2.swap"
        }
    }

    var defaultShortcut: ShortcutKey? {
        switch self {
        case .leftHalf: return ShortcutKey(kVK_LeftArrow, .optionShift)
        case .rightHalf: return ShortcutKey(kVK_RightArrow, .optionShift)
        case .topHalf: return ShortcutKey(kVK_UpArrow, .optionShift)
        case .bottomHalf: return ShortcutKey(kVK_DownArrow, .optionShift)

        case .topLeftQuarter: return ShortcutKey(kVK_ANSI_U, .optionShift)
        case .topRightQuarter: return ShortcutKey(kVK_ANSI_I, .optionShift)
        case .bottomLeftQuarter: return ShortcutKey(kVK_ANSI_J, .optionShift)
        case .bottomRightQuarter: return ShortcutKey(kVK_ANSI_K, .optionShift)

        case .firstThird: return ShortcutKey(kVK_ANSI_D, .optionShift)
        case .centerThird: return ShortcutKey(kVK_ANSI_F, .optionShift)
        case .lastThird: return ShortcutKey(kVK_ANSI_G, .optionShift)
        case .firstTwoThirds: return ShortcutKey(kVK_ANSI_E, .optionShift)
        case .lastTwoThirds: return ShortcutKey(kVK_ANSI_T, .optionShift)

        case .maximize: return ShortcutKey(kVK_Return, .optionShift)
        case .almostMaximize: return ShortcutKey(kVK_Space, .optionShift)
        case .maximizeHeight: return ShortcutKey(kVK_UpArrow, .optionShiftCommand)
        case .maximizeWidth: return ShortcutKey(kVK_DownArrow, .optionShiftCommand)
        case .center: return ShortcutKey(kVK_ANSI_C, .optionShift)
        case .restore: return ShortcutKey(kVK_Delete, .optionShift)

        case .nextDisplay: return ShortcutKey(kVK_RightArrow, .optionShiftCommand)
        case .previousDisplay: return ShortcutKey(kVK_LeftArrow, .optionShiftCommand)

        case .moveLeft, .moveRight, .moveUp, .moveDown: return nil
        case .makeLarger: return ShortcutKey(kVK_ANSI_Equal, .optionShift)
        case .makeSmaller: return ShortcutKey(kVK_ANSI_Minus, .optionShift)

        case .focusLeft: return ShortcutKey(kVK_LeftArrow, .controlOptionCommand)
        case .focusRight: return ShortcutKey(kVK_RightArrow, .controlOptionCommand)
        case .focusUp: return ShortcutKey(kVK_UpArrow, .controlOptionCommand)
        case .focusDown: return ShortcutKey(kVK_DownArrow, .controlOptionCommand)
        case .focusLastWindow: return ShortcutKey(kVK_Tab, .controlOptionCommand)
        case .focusQueueNext: return ShortcutKey(kVK_ANSI_RightBracket, .controlOptionCommand)
        case .focusQueuePrevious: return ShortcutKey(kVK_ANSI_LeftBracket, .controlOptionCommand)
        case .swapWithLastWindow: return ShortcutKey(kVK_Return, .controlOptionCommand)
        }
    }
}
