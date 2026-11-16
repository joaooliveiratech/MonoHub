import AppKit

enum ScreenshotMenu {
    static func makeMenuItem(captureTarget: AnyObject, captureActions: [CaptureRequest: Selector]) -> NSMenuItem {
        let menu = NSMenu(title: ShotText.menuCapture)
        menu.autoenablesItems = true

        for request in CaptureRequest.allCases {
            guard let action = captureActions[request] else { continue }
            let item = item(request.menuTitle, action, symbol: request.iconName)
            item.target = captureTarget
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(item(ShotText.menuSave, #selector(EditorWindowController.saveDocument(_:)), "s", symbol: "square.and.arrow.down"))
        menu.addItem(item(ShotText.menuPin, #selector(EditorWindowController.pinToScreen(_:)), "p", symbol: "pin"))
        menu.addItem(item(ShotText.menuOCR, #selector(EditorWindowController.recognizeText(_:)), "r", modifiers: [.command, .shift], symbol: "text.viewfinder"))

        menu.addItem(.separator())
        menu.addItem(item(ShotText.menuActualSize, #selector(EditorWindowController.zoomImageToActualSize(_:)), "0"))
        menu.addItem(item(ShotText.menuZoomToFit, #selector(EditorWindowController.zoomImageToFit(_:)), "9"))
        menu.addItem(item(ShotText.menuZoomIn, #selector(EditorWindowController.zoomIn(_:)), "+"))
        let hiddenZoomIn = item("", #selector(EditorWindowController.zoomIn(_:)), "=")
        hiddenZoomIn.isHidden = true
        hiddenZoomIn.allowsKeyEquivalentWhenHidden = true
        menu.addItem(hiddenZoomIn)
        menu.addItem(item(ShotText.menuZoomOut, #selector(EditorWindowController.zoomOut(_:)), "-"))

        menu.addItem(.separator())
        let tools = NSMenu(title: ShotText.menuTools)
        for (index, tool) in ToolMode.allCases.enumerated() {
            tools.addItem(item(tool.displayName, #selector(EditorWindowController.selectToolFromMenu(_:)), modifiers: [], symbol: tool.iconName, tag: index))
        }
        let toolsItem = NSMenuItem(title: ShotText.menuTools, action: nil, keyEquivalent: "")
        toolsItem.submenu = tools
        menu.addItem(toolsItem)

        let root = NSMenuItem(title: ShotText.menuCapture, action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        symbol: String? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.image = symbol.flatMap { MonoStyle.symbol($0) }
        item.tag = tag
        return item
    }
}
