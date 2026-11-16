import SwiftUI

nonisolated struct ShortcutItem: Identifiable, Sendable {
    let key: String
    let description: String

    var id: String { key }
}

nonisolated struct ShortcutGroup: Identifiable, Sendable {
    let title: String
    let items: [ShortcutItem]

    var id: String { title }
}

nonisolated enum ShortcutCatalog {
    static var groups: [ShortcutGroup] {
        [
            ShortcutGroup(
                title: localized("Navigation"),
                items: [
                    ShortcutItem(key: "⌥ ⇥", description: localized("Open switcher and cycle forward")),
                    ShortcutItem(key: "⌥ ⇧ ⇥", description: localized("Cycle backward")),
                    ShortcutItem(key: "⌥ `", description: localized("Show windows of current app only")),
                    ShortcutItem(key: "← → ↑ ↓", description: localized("Move across grid")),
                    ShortcutItem(key: "H J K L", description: localized("Move across grid (Vim)")),
                    ShortcutItem(key: "1 – 9", description: localized("Direct switch to numbered window"))
                ]
            ),
            ShortcutGroup(
                title: localized("Window Actions"),
                items: [
                    ShortcutItem(key: "↩", description: localized("Activate and focus selected window")),
                    ShortcutItem(key: "Space", description: localized("Enlarged preview (Quick Look)")),
                    ShortcutItem(key: "W", description: localized("Close window")),
                    ShortcutItem(key: "⇧ W", description: localized("Hide application")),
                    ShortcutItem(key: "M", description: localized("Minimize or restore from Dock")),
                    ShortcutItem(key: "Z", description: localized("Zoom / Maximize")),
                    ShortcutItem(key: "⌘ Q", description: localized("Quit application"))
                ]
            ),
            ShortcutGroup(
                title: localized("Tiling & Displays"),
                items: [
                    ShortcutItem(key: "[", description: localized("Snap to left half")),
                    ShortcutItem(key: "]", description: localized("Snap to right half")),
                    ShortcutItem(key: "N", description: localized("Move to next display"))
                ]
            ),
            ShortcutGroup(
                title: localized("Switcher & Search"),
                items: [
                    ShortcutItem(key: "/", description: localized("Open instant search")),
                    ShortcutItem(key: "F", description: localized("Search windows and apps")),
                    ShortcutItem(key: "?", description: localized("View keyboard shortcuts")),
                    ShortcutItem(key: "esc", description: localized("Back or close switcher"))
                ]
            )
        ]
    }

    static var legend: [ShortcutItem] {
        [
            ShortcutItem(key: "↩", description: localized("Activate")),
            ShortcutItem(key: "Space", description: localized("Quick Look")),
            ShortcutItem(key: "W", description: localized("Close")),
            ShortcutItem(key: "/", description: localized("Search")),
            ShortcutItem(key: "?", description: localized("Shortcuts"))
        ]
    }
}

struct ShortcutSections: View {
    var body: some View {
        ForEach(ShortcutCatalog.groups) { group in
            Section(group.title) {
                ForEach(group.items) { item in
                    LabeledContent(item.description) {
                        SwitcherKeyCap(item.key)
                    }
                }
            }
        }
    }
}
