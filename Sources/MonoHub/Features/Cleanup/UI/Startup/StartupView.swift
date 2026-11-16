import SwiftUI
import AppKit

enum StartupFilterType: String, CaseIterable, Identifiable {
    case all = "Todos"
    case loginItem = "Itens de Início"
    case userAgent = "Usuário"
    case systemAgent = "Sistema"
    case systemDaemon = "Daemons"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return localized("All")
        case .loginItem: return localized("Login Items")
        case .userAgent: return localized("User Agents")
        case .systemAgent: return localized("System Agents")
        case .systemDaemon: return localized("Daemons")
        }
    }
}

struct StartupView: View {
    @State private var items: [StartupItem] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var filterType: StartupFilterType = .all
    @State private var itemToRemove: StartupItem?

    private let engine = StartupEngine.shared

    private var filteredItems: [StartupItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            switch filterType {
            case .all: break
            case .loginItem: guard item.type == .loginItem else { return false }
            case .userAgent: guard item.type == .userAgent else { return false }
            case .systemAgent: guard item.type == .systemAgent else { return false }
            case .systemDaemon: guard item.type == .systemDaemon else { return false }
            }

            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || item.label.lowercased().contains(query)
                || (item.executablePath?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSummary
            Divider()

            if isLoading && items.isEmpty {
                ProgressView(localized("Scanning startup items…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                emptyStateView
            } else {
                startupTable
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker(localized("Filter"), selection: $filterType) {
                    ForEach(StartupFilterType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help(localized("Refresh startup items"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Search startup item or service"))
        .task {
            await reload()
        }
        .sheet(item: $itemToRemove) { target in
            ConfirmationModal(
                title: localized("Remove startup item “%@”?", target.name),
                subtitle: target.type == .loginItem
                    ? localized("The login item “%@” will be removed from your startup applications.", target.name)
                    : localized("The service “%@” will be unloaded and its property list file moved to the Trash.", target.label),
                items: [
                    (
                        name: target.name,
                        path: target.executablePath ?? target.plistURL?.path ?? (target.isOrphaned ? localized("Application no longer exists on disk") : target.label),
                        size: target.sizeBytes > 0 ? Formatting.bytes(target.sizeBytes) : "—"
                    )
                ],
                confirmActionTitle: target.type == .loginItem ? localized("Remove") : localized("Move to Trash")
            ) {
                let toRemove = target
                itemToRemove = nil
                Task {
                    _ = await engine.removeItem(toRemove)
                    await reload()
                }
            } onCancel: {
                itemToRemove = nil
            }
        }
    }

    private var headerSummary: some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                HubIcon(systemName: "bolt.shield.fill", tint: .indigo, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Startup Items & Background Services"))
                        .font(.headline)
                    Text(localized("%d items total (%d login items, %d user, %d system, %d daemons)",
                                   items.count,
                                   items.filter { $0.type == .loginItem }.count,
                                   items.filter { $0.type == .userAgent }.count,
                                   items.filter { $0.type == .systemAgent }.count,
                                   items.filter { $0.type == .systemDaemon }.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            let orphanedCount = items.filter(\.isOrphaned).count
            if orphanedCount > 0 {
                StatusBadge(localized("%d orphaned items", orphanedCount), icon: "exclamationmark.triangle.fill", color: .orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var startupTable: some View {
        Table(filteredItems) {
            TableColumn(localized("Status")) { item in
                HStack(spacing: 4) {
                    if item.type == .loginItem && item.isOrphaned {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .help(localized("Application no longer exists on disk"))
                    } else {
                        Toggle("", isOn: Binding(
                            get: { item.isEnabled },
                            set: { newValue in
                                Task {
                                    _ = await engine.toggleItem(item, enable: newValue)
                                    await reload()
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(item.isApple)
                        .help(item.isApple ? localized("System service protected by macOS") : (item.isEnabled ? localized("Click to disable") : localized("Click to enable")))
                    }

                    if item.requiresAdministrator && !item.isApple {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .help(localized("Requires administrator password"))
                    }
                }
            }
            .width(55)

            TableColumn(localized("Service")) { item in
                HStack(spacing: 10) {
                    Image(nsImage: item.icon())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            if item.isApple {
                                StatusBadge("Apple", color: .secondary)
                            } else if item.isOrphaned {
                                StatusBadge(localized("Missing Executable"), icon: "exclamationmark.triangle.fill", color: .orange)
                            }
                        }

                        if item.isOrphaned && item.type == .loginItem {
                            Text(localized("Application no longer exists on disk"))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Text(item.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contextMenu {
                    let targetURL: URL? = {
                        if let exe = item.executablePath, FileManager.default.fileExists(atPath: exe) {
                            return URL(fileURLWithPath: exe)
                        }
                        if let plist = item.plistURL, FileManager.default.fileExists(atPath: plist.path) {
                            return plist
                        }
                        return nil
                    }()

                    if let url = targetURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label(localized("Reveal in Finder"), systemImage: "folder")
                        }
                    }

                    if !item.isApple {
                        Button(role: .destructive) {
                            itemToRemove = item
                        } label: {
                            Label(localized("Remove startup item…"), systemImage: "trash")
                        }
                    }
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn(localized("Type")) { item in
                typeBadge(item.type)
            }
            .width(min: 105, ideal: 130)

            TableColumn(localized("Executable / Script")) { item in
                Text(item.executablePath ?? item.plistURL?.path ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 240)

            TableColumn(localized("Size")) { item in
                Text(item.sizeBytes > 0 ? Formatting.bytes(item.sizeBytes) : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 85)

            TableColumn(localized("Actions")) { item in
                HStack(spacing: 8) {
                    let targetURL: URL? = {
                        if let exe = item.executablePath, FileManager.default.fileExists(atPath: exe) {
                            return URL(fileURLWithPath: exe)
                        }
                        if let plist = item.plistURL, FileManager.default.fileExists(atPath: plist.path) {
                            return plist
                        }
                        return nil
                    }()

                    if let url = targetURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(localized("Reveal in Finder"))
                    }

                    if !item.isApple {
                        Button {
                            itemToRemove = item
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.85))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(localized("Remove startup item…"))
                    }
                }
            }
            .width(min: 65, ideal: 75)
        }
    }

    private func typeBadge(_ type: StartupItemType) -> some View {
        let (color, text): (Color, String) = {
            switch type {
            case .userAgent: return (.blue, localized("User Agent"))
            case .systemAgent: return (.indigo, localized("System Agent"))
            case .systemDaemon: return (.purple, localized("Daemon"))
            case .loginItem: return (.teal, localized("Login Item"))
            }
        }()

        return StatusBadge(text, color: color)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            localized("No Startup Items Found"),
            systemImage: "bolt.shield",
            description: Text(localized("No startup agents or daemons match the current filter or search criteria."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        isLoading = true
        let scanned = await engine.scanItems()
        await MainActor.run {
            self.items = scanned
            self.isLoading = false
        }
    }
}
