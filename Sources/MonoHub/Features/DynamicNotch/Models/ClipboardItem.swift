import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Synchronization

enum ClipboardItemType: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case link
    case color
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return localized("Text")
        case .link: return localized("Link")
        case .color: return localized("Color")
        case .image: return localized("Image")
        }
    }

    var iconName: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .text: return .blue
        case .link: return .indigo
        case .color: return .orange
        case .image: return .purple
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case text = "text"
    case link = "link"
    case color = "color"
    case image = "image"
    case pinned = "pinned"
    case snippets = "snippets"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return localized("All")
        case .text: return localized("Text")
        case .link: return localized("Links")
        case .color: return localized("Colors")
        case .image: return localized("Images")
        case .pinned: return localized("Pinned")
        case .snippets: return localized("Snippets")
        }
    }

    var iconName: String {
        switch self {
        case .all: return "tray.full.fill"
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .pinned: return "pin.fill"
        case .snippets: return "character.cursor.ibeam"
        }
    }
}

enum ClipboardClickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case paste = "paste"
    case open = "open"
    case copyOnly = "copyOnly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return localized("Paste in current application")
        case .open: return localized("Open with default application")
        case .copyOnly: return localized("Copy only")
        }
    }
}

struct ClipboardColor: Codable, Equatable, Sendable {
    var hex: String
    var rgbString: String
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func parse(from string: String) -> ClipboardColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let rgbColor = parseRGB(trimmed) {
            return rgbColor
        }

        if let hexColor = parseHex(trimmed) {
            return hexColor
        }

        return nil
    }

    private static func parseRGB(_ string: String) -> ClipboardColor? {
        let lower = string.lowercased()
        guard lower.hasPrefix("rgb") else { return nil }

        guard let openParen = lower.firstIndex(of: "("),
              let closeParen = lower.lastIndex(of: ")"),
              openParen < closeParen else { return nil }

        let inside = lower[lower.index(after: openParen)..<closeParen]
        let parts = inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }

        guard let rVal = Double(parts[0]),
              let gVal = Double(parts[1]),
              let bVal = Double(parts[2]) else { return nil }

        let aVal = parts.count >= 4 ? (Double(parts[3]) ?? 1.0) : 1.0

        let r = max(0, min(255, rVal)) / 255.0
        let g = max(0, min(255, gVal)) / 255.0
        let b = max(0, min(255, bVal)) / 255.0
        let a = max(0, min(1.0, aVal))

        let rInt = Int(round(r * 255))
        let gInt = Int(round(g * 255))
        let bInt = Int(round(b * 255))
        let hex = String(format: "#%02X%02X%02X", rInt, gInt, bInt)
        let rgbString = a < 0.999 ? String(format: "rgba(%d, %d, %d, %.2f)", rInt, gInt, bInt, a) : "rgb(\(rInt), \(gInt), \(bInt))"

        return ClipboardColor(hex: hex, rgbString: rgbString, r: r, g: g, b: b, a: a)
    }

    private static func parseHex(_ string: String) -> ClipboardColor? {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        } else if clean.hasPrefix("0x") || clean.hasPrefix("0X") {
            clean.removeFirst(2)
        } else {

            guard (clean.count == 6 || clean.count == 8) && clean.contains(where: { $0.isNumber }) else {
                return nil
            }
        }

        guard clean.allSatisfy({ $0.isHexDigit }) else { return nil }

        var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1.0
        guard let hexInt = UInt64(clean, radix: 16) else { return nil }

        if clean.count == 3 {
            let r4 = (hexInt >> 8) & 0xF
            let g4 = (hexInt >> 4) & 0xF
            let b4 = hexInt & 0xF
            r = Double((r4 << 4) | r4) / 255.0
            g = Double((g4 << 4) | g4) / 255.0
            b = Double((b4 << 4) | b4) / 255.0
        } else if clean.count == 6 {
            r = Double((hexInt >> 16) & 0xFF) / 255.0
            g = Double((hexInt >> 8) & 0xFF) / 255.0
            b = Double(hexInt & 0xFF) / 255.0
        } else if clean.count == 8 {
            r = Double((hexInt >> 24) & 0xFF) / 255.0
            g = Double((hexInt >> 16) & 0xFF) / 255.0
            b = Double((hexInt >> 8) & 0xFF) / 255.0
            a = Double(hexInt & 0xFF) / 255.0
        } else {
            return nil
        }

        let rInt = Int(round(r * 255))
        let gInt = Int(round(g * 255))
        let bInt = Int(round(b * 255))
        let standardHex = String(format: "#%02X%02X%02X", rInt, gInt, bInt)
        let rgbString = a < 0.999 ? String(format: "rgba(%d, %d, %d, %.2f)", rInt, gInt, bInt, a) : "rgb(\(rInt), \(gInt), \(bInt))"

        return ClipboardColor(hex: standardHex, rgbString: rgbString, r: r, g: g, b: b, a: a)
    }

    static func from(nsColor: NSColor) -> ClipboardColor {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            return ClipboardColor(hex: "#000000", rgbString: "rgb(0, 0, 0)", r: 0, g: 0, b: 0, a: 1)
        }
        let r = Double(srgb.redComponent)
        let g = Double(srgb.greenComponent)
        let b = Double(srgb.blueComponent)
        let a = Double(srgb.alphaComponent)
        let rInt = Int(round(r * 255))
        let gInt = Int(round(g * 255))
        let bInt = Int(round(b * 255))
        let hex = String(format: "#%02X%02X%02X", rInt, gInt, bInt)
        let rgbString = a < 0.999 ? String(format: "rgba(%d, %d, %d, %.2f)", rInt, gInt, bInt, a) : "rgb(\(rInt), \(gInt), \(bInt))"
        return ClipboardColor(hex: hex, rgbString: rgbString, r: r, g: g, b: b, a: a)
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let type: ClipboardItemType
    let content: String
    let previewText: String
    let rawText: String?
    let urlString: String?
    let colorInfo: ClipboardColor?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let byteSize: Int?
    var copiedAt: Date
    var isPinned: Bool
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let characterCount: Int
    let lineCount: Int

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        content: String,
        previewText: String? = nil,
        rawText: String? = nil,
        urlString: String? = nil,
        colorInfo: ClipboardColor? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int? = nil,
        copiedAt: Date = Date(),
        isPinned: Bool = false,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.previewText = previewText ?? content
        self.rawText = rawText
        self.urlString = urlString
        self.colorInfo = colorInfo
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID

        let base = rawText ?? content
        self.characterCount = base.count
        self.lineCount = max(1, base.components(separatedBy: .newlines).count)
    }

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var dimensionString: String? {
        guard let w = imageWidth, let h = imageHeight else { return nil }
        return "\(w)×\(h)"
    }

    var fileSizeString: String? {
        guard let byteSize else { return nil }
        return Formatting.bytes(Int64(byteSize))
    }

    private static let clipboardDateFormatter = Mutex(DateFormatter())

    var relativeTimeString: String {
        let diff = max(0, Date().timeIntervalSince(copiedAt))
        if diff < 10 { return localized("just now") }
        if diff < 60 { return localized("%ds ago", Int(diff)) }
        if diff < 3600 { return localized("%dm ago", Int(diff / 60)) }
        if diff < 86400 { return localized("%dh ago", Int(diff / 3600)) }
        return Self.clipboardDateFormatter.withLock { f in
            if f.locale != Localization.locale {
                f.locale = Localization.locale
                f.dateFormat = "dd/MM HH:mm"
            }
            return f.string(from: copiedAt)
        }
    }

    @MainActor
    func makeItemProvider() -> NSItemProvider {
        switch type {
        case .text:
            return NSItemProvider(object: (rawText ?? content) as NSString)
        case .link:
            if let url {
                let provider = NSItemProvider(object: url as NSURL)
                provider.registerObject((rawText ?? url.absoluteString) as NSString, visibility: .all)
                return provider
            }
            return NSItemProvider(object: content as NSString)
        case .color:
            let hex = colorInfo?.hex ?? content
            let provider = NSItemProvider(object: hex as NSString)
            if let nsColor = colorInfo?.nsColor,
               let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
                provider.registerDataRepresentation(forTypeIdentifier: NSPasteboard.PasteboardType.color.rawValue, visibility: .all) { completion in
                    completion(colorData, nil)
                    return nil
                }
            }
            return provider
        case .image:
            if let img = ClipboardManager.shared.fullImage(for: self) {
                let provider = NSItemProvider(object: img)
                if let data = ClipboardManager.shared.imageData(for: self) {
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                        completion(data, nil)
                        return nil
                    }
                }
                return provider
            }
            return NSItemProvider(object: content as NSString)
        }
    }
}
