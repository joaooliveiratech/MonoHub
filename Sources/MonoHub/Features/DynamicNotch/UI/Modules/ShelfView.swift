import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    private let shelfManager = ShelfManager.shared
    @State private var isTargeted: Bool = false

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NotchSectionLabel(localized("Shelf & AirDrop"), systemImage: "tray.and.arrow.down.fill", tint: .teal)

                Spacer()

                if !shelfManager.items.isEmpty {
                    AirDropButtonView()

                    Button {
                        NotchHaptics.tap()
                        shelfManager.clearAll()
                    } label: {
                        Text(localized("Clear"))
                    }
                    .buttonStyle(NotchSecondaryButtonStyle())
                }
            }

            if shelfManager.items.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.blue : Color.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                                .fill(isTargeted ? Color.blue.opacity(0.15) : Color.white.opacity(0.04))
                        )

                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26))
                            .foregroundStyle(isTargeted ? Color.blue : NotchTheme.tertiaryText)

                        Text(isTargeted ? localized("Drop to stash") : localized("Drag files here"))
                            .font(NotchTheme.title)
                            .foregroundStyle(NotchTheme.primaryText)

                        Text(localized("Files stay handy to drag out or share via AirDrop"))
                            .font(NotchTheme.caption)
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    shelfManager.handleDrop(providers: providers)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelfManager.items) { item in
                            ShelfItemCardView(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    shelfManager.handleDrop(providers: providers)
                }
            }
        }
        .notchModule()
    }
}

struct ShelfItemCardView: View {
    let item: ShelfItem
    private let shelfManager = ShelfManager.shared
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
            .frame(width: 32, height: 32)
            .task(id: item.url) {
                icon = NSWorkspace.shared.icon(forFile: item.url.path)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(NotchTheme.title)
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                Text(item.fileSizeString)
                    .font(NotchTheme.caption)
                    .foregroundStyle(NotchTheme.tertiaryText)
            }

            VStack(spacing: 4) {
                Button {
                    NotchHaptics.tap()
                    shelfManager.removeItem(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    NotchHaptics.tap()
                    shelfManager.revealInFinder(item: item)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localized("Reveal in Finder"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .notchCardSurface(radius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            NotchHaptics.tap()
            shelfManager.openItem(item)
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }
}

struct AirDropButtonView: View {
    private let shelfManager = ShelfManager.shared

    var body: some View {
        Button {
            NotchHaptics.tap()
            let urls = shelfManager.items.map { $0.url }
            if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "airdrop")
                    .font(.system(size: 11))
                Text("AirDrop")
            }
        }
        .buttonStyle(NotchPrimaryButtonStyle(tint: .blue, foreground: .white))
    }
}
