import Testing
import Foundation
import AppKit
import SwiftUI
@testable import MonoHub

@Suite("Clipboard Manager Tests")
@MainActor
struct ClipboardManagerTests {

    @Test("ClipboardColor parses 3, 6, and 8 hex digits correctly")
    func parseHexColors() {
        // 3-digit HEX
        let white3 = ClipboardColor.parse(from: "#FFF")
        #expect(white3 != nil)
        #expect(white3?.hex == "#FFFFFF")
        #expect(white3?.r == 1.0)
        #expect(white3?.g == 1.0)
        #expect(white3?.b == 1.0)
        #expect(white3?.a == 1.0)

        // 6-digit HEX
        let blue6 = ClipboardColor.parse(from: "#007AFF")
        #expect(blue6 != nil)
        #expect(blue6?.hex == "#007AFF")
        #expect(blue6?.rgbString == "rgb(0, 122, 255)")

        // 0x prefix
        let green0x = ClipboardColor.parse(from: "0x00FF00")
        #expect(green0x != nil)
        #expect(green0x?.hex == "#00FF00")

        // 8-digit HEX with alpha
        let semiRed = ClipboardColor.parse(from: "#FF000080")
        #expect(semiRed != nil)
        #expect(semiRed?.hex == "#FF0000")
        #expect(semiRed?.a ?? 0 > 0.49 && semiRed?.a ?? 0 < 0.51)

        // Normal words without # should not be recognized as colors
        #expect(ClipboardColor.parse(from: "hello") == nil)
        #expect(ClipboardColor.parse(from: "notacolor") == nil)
        #expect(ClipboardColor.parse(from: "decade") == nil)
        #expect(ClipboardColor.parse(from: "coffee") == nil)
    }

    @Test("ClipboardColor parses RGB and RGBA strings correctly")
    func parseRGBColors() {
        let orange = ClipboardColor.parse(from: "rgb(255, 128, 0)")
        #expect(orange != nil)
        #expect(orange?.hex == "#FF8000")
        #expect(orange?.rgbString == "rgb(255, 128, 0)")

        let alphaPurple = ClipboardColor.parse(from: "rgba(128, 0, 128, 0.75)")
        #expect(alphaPurple != nil)
        #expect(alphaPurple?.hex == "#800080")
        #expect(alphaPurple?.a == 0.75)
    }

    @Test("ClipboardItem initializes with correct type, counts, and metadata")
    func clipboardItemModel() {
        // Plain text
        let textItem = ClipboardItem(
            type: .text,
            content: "Linha 1\nLinha 2\nLinha 3",
            sourceAppName: "Xcode"
        )
        #expect(textItem.type == .text)
        #expect(textItem.lineCount == 3)
        #expect(textItem.characterCount > 10)
        #expect(textItem.sourceAppName == "Xcode")
        #expect(!textItem.isPinned)

        // Web Link
        let linkItem = ClipboardItem(
            type: .link,
            content: "https://apple.com/macos",
            urlString: "https://apple.com/macos"
        )
        #expect(linkItem.type == .link)
        #expect(linkItem.url?.host == "apple.com")

        // Color
        let colorInfo = ClipboardColor.parse(from: "#FF5733")!
        let colorItem = ClipboardItem(
            type: .color,
            content: colorInfo.hex,
            colorInfo: colorInfo
        )
        #expect(colorItem.type == .color)
        #expect(colorItem.colorInfo?.hex == "#FF5733")

        // Image
        let imageItem = ClipboardItem(
            type: .image,
            content: "Imagem 1920×1080",
            imageWidth: 1920,
            imageHeight: 1080,
            byteSize: 1048576
        )
        #expect(imageItem.type == .image)
        #expect(imageItem.dimensionString == "1920×1080")
        #expect(imageItem.fileSizeString != nil)
    }

    @Test("ClipboardItem creates valid NSItemProvider for drag and drop")
    func itemProviderGeneration() {
        let textItem = ClipboardItem(type: .text, content: "Teste de Arrastar")
        let provider = textItem.makeItemProvider()
        #expect(provider.canLoadObject(ofClass: NSString.self))

        let linkItem = ClipboardItem(type: .link, content: "https://github.com", urlString: "https://github.com")
        let linkProvider = linkItem.makeItemProvider()
        #expect(linkProvider.canLoadObject(ofClass: NSURL.self) || linkProvider.canLoadObject(ofClass: NSString.self))
    }

    @Test("ClipboardManager filter, search, and pin logic works accurately")
    func clipboardFilteringAndSearch() {
        let manager = ClipboardManager.shared
        manager.clearAll()

        let item1 = ClipboardItem(type: .text, content: "Configuração do sistema", previewText: "Configuração do sistema")
        let item2 = ClipboardItem(type: .link, content: "https://github.com/swift", urlString: "https://github.com/swift")
        let item3 = ClipboardItem(type: .color, content: "#007AFF", colorInfo: ClipboardColor.parse(from: "#007AFF")!)
        let item4 = ClipboardItem(type: .text, content: "Senha temporária", isPinned: false)

        manager.insertItem(item1)
        manager.insertItem(item2)
        manager.insertItem(item3)
        manager.insertItem(item4)
        manager.togglePin(item: item4)

        #expect(manager.items.count == 4)

        // Test filter by type
        manager.selectedFilter = .text
        #expect(manager.filteredItems.allSatisfy { $0.type == .text })

        manager.selectedFilter = .link
        #expect(manager.filteredItems.allSatisfy { $0.type == .link })

        manager.selectedFilter = .color
        #expect(manager.filteredItems.allSatisfy { $0.type == .color })

        manager.selectedFilter = .pinned
        #expect(manager.filteredItems.allSatisfy { $0.isPinned })

        // Test search query
        manager.selectedFilter = .all
        manager.searchQuery = "github"
        #expect(manager.filteredItems.count == 1)
        #expect(manager.filteredItems.first?.type == .link)

        manager.searchQuery = ""
        #expect(manager.filteredItems.count == 4)

        // Test clear history preserves pinned items
        manager.clearHistory()
        #expect(manager.items.count == 1)
        #expect(manager.items.first?.isPinned == true)

        // Clean up
        manager.clearAll()
        #expect(manager.items.isEmpty)
    }

    @Test("NotchTab and NotchPreferences include clipboard module")
    func preferencesIntegration() {
        let prefs = NotchPreferences.shared
        #expect(NotchTab.clipboard.title == "Clipboard" || NotchTab.clipboard.title == "Transferência")
        #expect(NotchTab.clipboard.iconName == "doc.on.clipboard.fill")
        #expect(prefs.isTabEnabled(.clipboard) == prefs.enableClipboardModule)

        let initial = prefs.enableClipboardModule
        prefs.setTab(.clipboard, enabled: !initial)
        #expect(prefs.enableClipboardModule == !initial)
        prefs.setTab(.clipboard, enabled: initial)

        #expect(prefs.effectiveExpandedHeight(for: .clipboard) >= 340)
    }

    @Test("ClipboardClickAction cases and preference round-trip")
    func clickActionPreferences() {
        let prefs = NotchPreferences.shared
        #expect(ClipboardClickAction.allCases.count == 3)

        let original = Localization.language
        defer { Localization.language = original }
        Localization.language = .portuguese
        #expect(ClipboardClickAction.paste.title == "Colar no aplicativo atual")
        #expect(ClipboardClickAction.open.title == "Abrir com o aplicativo padrão")
        #expect(ClipboardClickAction.copyOnly.title == "Apenas copiar")

        Localization.language = .english
        #expect(ClipboardClickAction.paste.title == "Paste in current application")
        #expect(ClipboardClickAction.open.title == "Open with default application")
        #expect(ClipboardClickAction.copyOnly.title == "Copy only")

        let initial = prefs.clipboardClickAction
        prefs.clipboardClickAction = .open
        #expect(prefs.clipboardClickAction == .open)
        prefs.clipboardClickAction = initial
    }

    @Test("ClipboardManager open method safely handles various item types without opening external apps")
    func openItemHandler() {
        let manager = ClipboardManager.shared

        var openedURLs: [URL] = []
        var activatedURLs: [[URL]] = []
        var presentedColors: [NSColor] = []

        manager.workspaceOpener = { url in
            openedURLs.append(url)
            return true
        }
        manager.fileViewerActivator = { urls in
            activatedURLs.append(urls)
        }
        manager.colorPresenter = { color in
            presentedColors.append(color)
        }
        defer {
            manager.resetOpenHandlers()
        }

        // Link item
        let linkItem = ClipboardItem(type: .link, content: "https://apple.com", urlString: "https://apple.com")
        manager.open(item: linkItem)
        #expect(openedURLs.first?.absoluteString == "https://apple.com")

        // Color item
        let colorItem = ClipboardItem(type: .color, content: "#FF0000", colorInfo: ClipboardColor.parse(from: "#FF0000")!)
        manager.open(item: colorItem)
        #expect(!presentedColors.isEmpty)

        // Text item with valid local directory
        let textFolder = ClipboardItem(type: .text, content: "/tmp")
        manager.open(item: textFolder)
        #expect(activatedURLs.first?.first?.path == "/tmp" || activatedURLs.first?.first?.path == "/private/tmp")
    }
}
