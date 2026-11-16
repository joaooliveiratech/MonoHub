import Carbon

enum ShotKeyCode {
    static let escape = UInt16(kVK_Escape)
    static let delete = UInt16(kVK_Delete)
    static let forwardDelete = UInt16(kVK_ForwardDelete)
    static let space = UInt16(kVK_Space)
    static let returnKey = UInt16(kVK_Return)
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)

    static let toolKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3, UInt16(kVK_ANSI_4): 4,
        UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6, UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8
    ]
}
