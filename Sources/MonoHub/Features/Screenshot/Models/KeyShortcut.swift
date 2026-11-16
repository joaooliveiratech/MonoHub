import AppKit
import Carbon

struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultArea = KeyShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultFullscreen = KeyShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultWindow = KeyShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultOCR = KeyShortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultScrolling = KeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultRecord = KeyShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey))

    private static let commandLikeModifiers = UInt32(cmdKey | optionKey | controlKey)

    var isValidGlobalShortcut: Bool {
        modifiers & Self.commandLikeModifiers != 0
    }

    var displayString: String {
        modifierSymbols + Self.keyName(for: keyCode)
    }

    var modifierSymbols: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var menuKeyEquivalent: String {
        if let function = Self.functionKeys[Int(keyCode)] {
            return String(Character(UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(function - 1))!))
        }
        if let special = Self.menuSpecialKeys[Int(keyCode)] {
            return special
        }
        return Self.translatedCharacter(for: keyCode)?.lowercased() ?? ""
    }

    static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6,
        kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12
    ]

    private static let symbolKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]

    private static let menuSpecialKeys: [Int: String] = [
        kVK_Space: " ", kVK_Return: "\r", kVK_Tab: "\t", kVK_Escape: "\u{1b}",
        kVK_Delete: "\u{8}", kVK_ForwardDelete: "\u{7f}"
    ]

    static func keyName(for code: UInt32) -> String {
        let key = Int(code)
        if key == kVK_Space { return ShotText.keySpace }
        if let function = functionKeys[key] { return "F\(function)" }
        if let symbol = symbolKeys[key] { return symbol }
        return translatedCharacter(for: code)?.uppercased() ?? "Key \(code)"
    }

    private static func translatedCharacter(for code: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let layoutSource = layoutData(of: source) != nil
            ? source
            : TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = layoutData(of: layoutSource) else { return nil }

        let layoutBytes = CFDataGetBytePtr(layoutData)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutBytes?.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                UInt16(code),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }

        let text = String(utf16CodeUnits: characters, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func layoutData(of source: TISInputSource) -> CFData? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    }
}
