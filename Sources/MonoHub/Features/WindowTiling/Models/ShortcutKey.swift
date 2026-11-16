import AppKit
import Carbon.HIToolbox
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option  = ShortcutModifiers(rawValue: 1 << 1)
    static let command = ShortcutModifiers(rawValue: 1 << 2)
    static let shift   = ShortcutModifiers(rawValue: 1 << 3)

    static let optionShift: ShortcutModifiers = [.option, .shift]
    static let optionShiftCommand: ShortcutModifiers = [.option, .shift, .command]
    static let controlOptionCommand: ShortcutModifiers = [.control, .option, .command]

    private struct Mapping {
        let modifier: ShortcutModifiers
        let symbol: String
        let carbon: Int
        let eventFlag: NSEvent.ModifierFlags
        let cgFlag: CGEventFlags
    }

    private static let mappings: [Mapping] = [
        Mapping(modifier: .control, symbol: "⌃", carbon: controlKey, eventFlag: .control, cgFlag: .maskControl),
        Mapping(modifier: .option, symbol: "⌥", carbon: optionKey, eventFlag: .option, cgFlag: .maskAlternate),
        Mapping(modifier: .shift, symbol: "⇧", carbon: shiftKey, eventFlag: .shift, cgFlag: .maskShift),
        Mapping(modifier: .command, symbol: "⌘", carbon: cmdKey, eventFlag: .command, cgFlag: .maskCommand)
    ]

    var carbonModifiers: UInt32 {
        Self.mappings.reduce(0) { contains($1.modifier) ? $0 | UInt32($1.carbon) : $0 }
    }

    var nsEventModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(Self.mappings.filter { contains($0.modifier) }.map(\.eventFlag))
    }

    var displayString: String {
        Self.mappings.filter { contains($0.modifier) }.map(\.symbol).joined()
    }

    var hasNonShiftModifier: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }

    init(cgEventFlags flags: CGEventFlags) {
        self = ShortcutModifiers(Self.mappings.filter { flags.contains($0.cgFlag) }.map(\.modifier))
    }

    init(nsEventModifiers flags: NSEvent.ModifierFlags) {
        self = ShortcutModifiers(Self.mappings.filter { flags.contains($0.eventFlag) }.map(\.modifier))
    }
}

struct ShortcutKey: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: ShortcutModifiers

    init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(_ keyCode: Int, _ modifiers: ShortcutModifiers) {
        self.init(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    var displayString: String {
        modifiers.displayString + keyString
    }

    var keyString: String {
        Self.keyString(for: keyCode)
    }

    var isFunctionKey: Bool {
        Self.functionKeyCodes.contains(Int(keyCode))
    }

    var isValidGlobalShortcut: Bool {
        modifiers.hasNonShiftModifier || isFunctionKey
    }

    var menuKeyEquivalent: String {
        if let scalar = Self.menuFunctionKeys[Int(keyCode)] {
            return String(Character(scalar))
        }
        return keyString.lowercased()
    }

    static func keyString(for keyCode: UInt16) -> String {
        keyNames[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    private static let menuFunctionKeys: [Int: Unicode.Scalar] = [
        kVK_Return: "\r",
        kVK_Tab: "\t",
        kVK_Space: " ",
        kVK_Delete: "\u{8}",
        kVK_Escape: "\u{1b}",
        kVK_LeftArrow: Unicode.Scalar(NSLeftArrowFunctionKey)!,
        kVK_RightArrow: Unicode.Scalar(NSRightArrowFunctionKey)!,
        kVK_UpArrow: Unicode.Scalar(NSUpArrowFunctionKey)!,
        kVK_DownArrow: Unicode.Scalar(NSDownArrowFunctionKey)!,
        kVK_ForwardDelete: Unicode.Scalar(NSDeleteFunctionKey)!,
        kVK_Home: Unicode.Scalar(NSHomeFunctionKey)!,
        kVK_End: Unicode.Scalar(NSEndFunctionKey)!,
        kVK_PageUp: Unicode.Scalar(NSPageUpFunctionKey)!,
        kVK_PageDown: Unicode.Scalar(NSPageDownFunctionKey)!,
        kVK_F1: Unicode.Scalar(NSF1FunctionKey)!,
        kVK_F2: Unicode.Scalar(NSF2FunctionKey)!,
        kVK_F3: Unicode.Scalar(NSF3FunctionKey)!,
        kVK_F4: Unicode.Scalar(NSF4FunctionKey)!,
        kVK_F5: Unicode.Scalar(NSF5FunctionKey)!,
        kVK_F6: Unicode.Scalar(NSF6FunctionKey)!,
        kVK_F7: Unicode.Scalar(NSF7FunctionKey)!,
        kVK_F8: Unicode.Scalar(NSF8FunctionKey)!,
        kVK_F9: Unicode.Scalar(NSF9FunctionKey)!,
        kVK_F10: Unicode.Scalar(NSF10FunctionKey)!,
        kVK_F11: Unicode.Scalar(NSF11FunctionKey)!,
        kVK_F12: Unicode.Scalar(NSF12FunctionKey)!
    ]

    private static let keyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}
