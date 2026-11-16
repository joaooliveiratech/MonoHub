import SwiftUI

struct OrphanedRemnantsView: View {
    @State private var model = CleanupListModel<OrphanItem> { items, options in
        await AppUninstallEngine.removeOrphans(items, options: options)
    }
    @State private var scanRequest: UUID?
    @State private var searchText = ""
    @State private var selectedCategory: RemnantCategory?
    @State private var sortOrder = [KeyPathComparator(\OrphanItem.size, order: .reverse)]

    init() {}

    private var availableCategories: [RemnantCategory] {
        let present = Set(model.items.map(\.category))
        return RemnantCategory.allCases.filter { present.contains($0) }
    }

    private var visibleItems: [OrphanItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return model.items.filter { item in
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            guard matchesCategory else { return false }
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query)
                || (item.parentAppHint?.localizedCaseInsensitiveContains(query) ?? false)
                || item.url.path.localizedCaseInsensitiveContains(query)
                || item.categoryName.localizedCaseInsensitiveContains(query)
                || item.matchType.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        content
            .toolbar {
                if !model.items.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Picker(localized("Type"), selection: $selectedCategory) {
                            Text(localized("All Types")).tag(Optional<RemnantCategory>.none)
                            Divider()
                            ForEach(availableCategories, id: \.self) { category in
                                Text(category.title).tag(Optional(category))
                            }
                        }
                        .frame(width: 170)
                    }
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button(localized("Select Safe Only")) {
                                let safeIds = Set(visibleItems.filter { $0.safetyLevel == .safe }.map(\.id))
                                model.selection = safeIds
                            }
                            Button(localized("Select All")) {
                                model.setSelection(true, for: visibleItems)
                            }
                            Divider()
                            Button(localized("Deselect All")) {
                                model.setSelection(false, for: visibleItems)
                            }
                        } label: {
                            Label(localized("Quick Select"), systemImage: "checklist")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scanRequest = UUID()
                    } label: {
                        Label(localized("Scan"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.phase == .scanning || model.isRemoving)
                    .help(localized("Scan for remnants of uninstalled apps"))
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: localized("Filter remnants"))
            .task(id: scanRequest) {
                guard scanRequest != nil else { return }
                let snapshots = OrphanScanner.runningSnapshots()
                await model.scan { reporter in
                    await OrphanScanner.scan(
                        runningIdentifiers: snapshots.identifiers,
                        runningNames: snapshots.names,
                        progress: reporter
                    )
                }
            }
            .onChange(of: sortOrder) { _, newOrder in
                model.sort(using: newOrder)
            }
            .cleanupRemovalFlow(model, title: localized("Remove orphaned remnants?"), actionTitle: localized("Remove"))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            CleanupStartView(
                title: localized("Remnants of uninstalled apps"),
                systemImage: "trash.circle",
                description: localized("Scans for data left in ~/Library by apps that are no longer installed. Matches orphaned files by bundle identifier, app name, and broken background agents. Nothing is selected by default.")
            ) {
                scanRequest = UUID()
            }
        case .scanning:
            CleanupProgressView(progress: model.progress) {
                model.cancelScan()
                scanRequest = nil
            }
        case .loaded where model.items.isEmpty:
            ContentUnavailableView(
                localized("No remnants found"),
                systemImage: "checkmark.circle",
                description: Text(localized("There are no uninstalled app folders in ~/Library."))
            )
        case .loaded:
            resultsTable
        }
    }

    private var resultsTable: some View {
        let visible = visibleItems
        let selectedVisible = visible.filter { model.selection.contains($0.id) }
        return Table(visible, sortOrder: $sortOrder) {
            TableColumn("") { item in
                SelectionCheckbox(isOn: model.isSelected(item.id))
            }
            .width(22)
            TableColumn(localized("Remnant"), value: \.name) { item in
                let title = (item.parentAppHint != nil && item.parentAppHint != item.name)
                    ? "\(item.parentAppHint!) · \(item.name)"
                    : item.name
                CleanupItemLabel(title: title, path: item.url.path, systemImage: item.category.systemIcon)
                    .help(item.explanation)
            }
            .width(min: 240, ideal: 340)
            TableColumn(localized("Detection"), value: \.matchType.title) { item in
                StatusBadge(
                    item.matchType.title,
                    color: item.matchType == .bundleIdentifier ? .blue : item.matchType == .launchAgent ? .purple : .teal
                )
            }
            .width(min: 90, ideal: 110)
            TableColumn(localized("Safety"), value: \.safetyLevel.title) { item in
                StatusBadge(
                    item.safetyLevel.title,
                    icon: item.safetyLevel.icon,
                    color: item.safetyLevel.color
                )
            }
            .width(min: 110, ideal: 130)
            TableColumn(localized("Type"), value: \.categoryName) { item in
                Text(item.categoryName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn(localized("Size"), value: \.size) { item in
                SizeText(bytes: item.size)
            }
            .width(min: 80, ideal: 90)
            TableColumn("") { item in
                RevealInFinderButton(url: item.url)
            }
            .width(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionControlBar(
                totalCount: visible.count,
                selectedCount: selectedVisible.count,
                selectedBytes: selectedVisible.reduce(0) { $0 + $1.size },
                actionTitle: localized("Remove…"),
                isBusy: model.isRemoving,
                onToggleAll: { model.setSelection($0, for: visible) },
                onAction: { model.requestRemoval(selectedVisible) }
            )
        }
    }
}
