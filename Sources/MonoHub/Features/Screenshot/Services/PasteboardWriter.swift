import AppKit

enum PasteboardWriter {

    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @discardableResult
    static func write(pngData: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(pngData, forType: .png)
    }

    @discardableResult
    static func write(gifData: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(gifData, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
    }

    @discardableResult
    static func write(fileURL: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([fileURL as NSURL])
    }

    static func write(text: String, concealed: Bool, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if concealed {
            pasteboard.setData(Data(), forType: concealedType)
        }
        pasteboard.setString(text, forType: .string)
    }
}
