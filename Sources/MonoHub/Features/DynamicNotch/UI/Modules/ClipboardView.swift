import SwiftUI
import AppKit

struct ClipboardView: View {
    @Bindable private var clipboardManager = ClipboardManager.shared
    @State private var copiedItemId: UUID? = nil

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
            filterBar
            contentList
        }
        .notchModule()
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            NotchSectionLabel(localized("Clipboard"), systemImage: "doc.on.clipboard.fill", tint: .orange)

            if !clipboardManager.items.isEmpty {
                Text("\(clipboardManager.items.count)")
                    .font(NotchTheme.caption)
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.tertiaryText)

                TextField(localized("Search..."), text: $clipboardManager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(NotchTheme.body)
                    .foregroundStyle(NotchTheme.primaryText)
                    .frame(width: 110)

                if !clipboardManager.searchQuery.isEmpty {
                    Button {
                        NotchHaptics.tap()
                        clipboardManager.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )

            if clipboardManager.items.contains(where: { !$0.isPinned }) {
                Button {
                    NotchHaptics.tap()
                    clipboardManager.clearHistory()
                } label: {
                    Text(localized("Clear"))
                }
                .buttonStyle(NotchSecondaryButtonStyle())
                .help(localized("Clear unpinned history"))
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardFilter.allCases) { filter in
                let count = clipboardManager.itemCount(for: filter)
                let isSelected = clipboardManager.selectedFilter == filter

                Button {
                    NotchHaptics.tap()
                    withAnimation(NotchTheme.content) {
                        clipboardManager.selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.iconName)
                            .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))

                        Text(filter.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))

                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : NotchTheme.tertiaryText)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.orange.opacity(0.25) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? Color.orange.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.75)
                            )
                    )
                    .foregroundStyle(isSelected ? Color.orange : NotchTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var contentList: some View {
        Group {
            if clipboardManager.selectedFilter == .snippets {
                snippetsListView
            } else {
                let filtered = clipboardManager.filteredItems
                if filtered.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 7) {
                            ForEach(filtered) { item in
                                ClipboardItemCard(
                                    item: item,
                                    isCopied: copiedItemId == item.id,
                                    onOpen: {
                                        triggerOpen(for: item)
                                    },
                                    onCopy: {
                                        triggerCopy(for: item)
                                    },
                                    onPaste: {
                                        triggerPaste(for: item)
                                    },
                                    onTogglePin: {
                                        clipboardManager.togglePin(item: item)
                                    },
                                    onDelete: {
                                        clipboardManager.delete(item: item)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snippetsListView: some View {
        let snippets = SnippetManager.shared.snippets.filter { $0.isEnabled }
        return Group {
            if snippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 26))
                        .foregroundStyle(NotchTheme.tertiaryText)
                    Text(localized("No snippets registered."))
                        .font(NotchTheme.body)
                        .foregroundStyle(NotchTheme.secondaryText)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        ForEach(snippets) { snippet in
                            HStack(spacing: 10) {
                                Text(snippet.keyword)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.indigo))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(snippet.label)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(NotchTheme.primaryText)
                                    Text(snippet.evaluatedContent())
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(NotchTheme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    NotchHaptics.tap()
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(snippet.evaluatedContent(), forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(NotchTheme.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(NotchTheme.cardFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(NotchTheme.cardStroke, lineWidth: 0.75)
                                    )
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: clipboardManager.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(NotchTheme.tertiaryText)

            Text(clipboardManager.searchQuery.isEmpty ? localized("Clipboard is Empty") : localized("No results found"))
                .font(NotchTheme.title)
                .foregroundStyle(NotchTheme.primaryText)

            Text(clipboardManager.searchQuery.isEmpty
                 ? localized("Copied texts, links, colors, and images will appear here for quick access.")
                 : localized("No items matching “%@”.", clipboardManager.searchQuery))
                .font(NotchTheme.caption)
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func triggerOpen(for item: ClipboardItem) {
        clipboardManager.open(item: item)
    }

    private func triggerCopy(for item: ClipboardItem) {
        clipboardManager.copyToPasteboard(item: item)
        showCopiedFeedback(for: item.id)
    }

    private func triggerPaste(for item: ClipboardItem) {
        clipboardManager.paste(item: item)
        showCopiedFeedback(for: item.id)
    }

    private func showCopiedFeedback(for id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            copiedItemId = id
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedItemId == id {
                withAnimation(.easeIn(duration: 0.2)) {
                    copiedItemId = nil
                }
            }
        }
    }
}

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            leadingVisual

            contentInfo
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingActions
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.isPinned ? Color.orange.opacity(isHovered ? 0.12 : 0.08) : (isHovered ? NotchTheme.cardFillHover : NotchTheme.cardFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(item.isPinned ? Color.orange.opacity(0.35) : (isHovered ? Color.white.opacity(0.18) : NotchTheme.cardStroke), lineWidth: 0.75)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            switch NotchPreferences.shared.clipboardClickAction {
            case .open:
                onOpen()
            case .copyOnly:
                onCopy()
            case .paste:
                onPaste()
            }
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label(openMenuTitle(for: item), systemImage: "arrow.up.right.square")
            }

            Button {
                onCopy()
            } label: {
                Label(localized("Copy"), systemImage: "doc.on.clipboard")
            }

            Button {
                onPaste()
            } label: {
                Label(localized("Paste into active application"), systemImage: "arrow.right.doc.on.clipboard")
            }

            Divider()

            Button {
                onTogglePin()
            } label: {
                Label(item.isPinned ? localized("Unpin from top") : localized("Pin to top"), systemImage: item.isPinned ? "pin.slash" : "pin")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(localized("Remove from history"), systemImage: "trash")
            }
        }
        .onDrag {
            item.makeItemProvider()
        }
        .task(id: item.imageFileName) {
            if item.type == .image {
                thumbnail = ClipboardManager.shared.thumbnail(for: item)
            }
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        switch item.type {
        case .color:
            if let color = item.colorInfo {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.swiftUIColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: color.swiftUIColor.opacity(0.3), radius: 3, y: 1)
            } else {
                defaultTypeIcon
            }

        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            } else {
                defaultTypeIcon
            }

        case .link:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.indigo.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.indigo)
            }

        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
        }
    }

    private var defaultTypeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.type.tintColor.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: item.type.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.type.tintColor)
        }
    }

    private var contentInfo: some View {
        VStack(alignment: .leading, spacing: 2) {

            HStack(spacing: 6) {
                Text(item.previewText)
                    .font(NotchTheme.title)
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.orange)
                }
            }

            HStack(spacing: 6) {
                if item.type == .color, let info = item.colorInfo {
                    Text(info.rgbString)
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.secondaryText)
                } else if item.type == .image {
                    if let dims = item.dimensionString {
                        Text(dims)
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    if let size = item.fileSizeString {
                        Text("•")
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.tertiaryText)
                        Text(size)
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                } else if item.type == .link, let host = item.url?.host {
                    Text(host)
                        .font(NotchTheme.caption)
                        .foregroundStyle(Color.indigo.opacity(0.9))
                } else {
                    Text(String(format: localized("%d characters • %d lines"), item.characterCount, item.lineCount))
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)
                }

                if let appName = item.sourceAppName {
                    Text("•")
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)

                    Text(appName)
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)
                }

                Text("•")
                    .font(NotchTheme.caption)
                    .foregroundStyle(NotchTheme.tertiaryText)

                Text(item.relativeTimeString)
                    .font(NotchTheme.caption)
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 5) {
            if isCopied {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(localized("Copied"))
                        .font(NotchTheme.caption)
                }
                .foregroundStyle(Color.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.18))
                )
            } else {

                Button {
                    onOpen()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(openHelpText(for: item))

                if item.type == .color, let info = item.colorInfo {
                    Button {
                        NotchHaptics.tap()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.rgbString, forType: .string)
                    } label: {
                        Text("RGB")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .frame(width: 26, height: 24)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(localized("Copy RGB format"))
                }

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(localized("Copy to Clipboard"))

                Button {
                    onTogglePin()
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(item.isPinned ? Color.orange : NotchTheme.tertiaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(item.isPinned ? Color.orange.opacity(0.2) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? localized("Unpin item") : localized("Pin item to top"))

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(localized("Remove from history"))
            }
        }
    }

    private func openHelpText(for item: ClipboardItem) -> String {
        switch item.type {
        case .image:
            return localized("Open image in Preview")
        case .link:
            return localized("Open link in browser")
        case .color:
            return localized("Open in macOS Color Panel")
        case .text:
            let trimmed = (item.rawText ?? item.content).trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return localized("Reveal in Finder")
            }
            return localized("Open in Text Editor")
        }
    }

    private func openMenuTitle(for item: ClipboardItem) -> String {
        switch item.type {
        case .image:
            return localized("Open in Preview")
        case .link:
            return localized("Open in Browser")
        case .color:
            return localized("Open in Color Panel")
        case .text:
            let trimmed = (item.rawText ?? item.content).trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return localized("Reveal in Finder")
            }
            return localized("Open in Text Editor")
        }
    }
}
