import SwiftUI

@Observable
@MainActor
final class SystemCleanModel {
    private(set) var groups: [CleanCategoryGroup] = []
    var selection: Set<UUID> = []
    var expanded: Set<CleanCategoryType> = []
    var expandedItems: Set<UUID> = []
    private(set) var phase: CleanupPhase = .idle
    private(set) var progress = ScanProgress(message: "")
    private(set) var isRemoving = false
    private(set) var pending: [(CleanCategoryType, [CleanSubItem])] = []
    private(set) var pendingEmptiesTrash = false
    var isConfirming = false
    var lastResult: ExecutionResult?
    var showsResult = false

    func scan() async {
        phase = .scanning
        groups = []
        selection = []
        expandedItems = []
        progress = ScanProgress(message: localized("Preparing scan…"))
        let reporter = ProgressReporter { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.progress = update
            }
        }
        let found = await SystemCleanEngine.scanCategories(progress: reporter)
        guard !Task.isCancelled else {
            phase = .idle
            return
        }
        groups = found
        phase = .loaded
    }

    func cancelScan() {
        if phase == .scanning {
            phase = .idle
        }
    }

    func visibleGroups(matching query: String) -> [CleanCategoryGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.type.rawValue.localizedCaseInsensitiveContains(trimmed) || group.type.title.localizedCaseInsensitiveContains(trimmed) {
                return group
            }
            let matching = group.items.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.friendlyName?.localizedCaseInsensitiveContains(trimmed) ?? false)
                    || $0.url.path.localizedCaseInsensitiveContains(trimmed)
            }
            guard !matching.isEmpty else { return nil }
            var copy = group
            copy.items = matching
            return copy
        }
    }

    func toggleExpansion(of type: CleanCategoryType) {
        if expanded.contains(type) {
            expanded.remove(type)
        } else {
            expanded.insert(type)
        }
    }

    func toggleExpansion(of itemID: UUID) {
        if expandedItems.contains(itemID) {
            expandedItems.remove(itemID)
        } else {
            expandedItems.insert(itemID)
        }
    }

    func toggleSelection(of itemID: UUID) {
        if selection.contains(itemID) {
            selection.remove(itemID)
        } else {
            selection.insert(itemID)
        }
    }

    func selectedItems(in group: CleanCategoryGroup) -> [CleanSubItem] {
        group.items.filter { selection.contains($0.id) }
    }

    func setSelection(_ isOn: Bool, for items: [CleanSubItem]) {
        let ids = items.map(\.id)
        if isOn {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
    }

    func selectSafeOnly(in visible: [CleanCategoryGroup]) {
        var safeIds = Set<UUID>()
        for group in visible where group.type.safetyLevel == .safe {
            for item in group.items where !item.isAppRunning {
                safeIds.insert(item.id)
            }
        }
        selection = safeIds
    }

    func requestClean(in visible: [CleanCategoryGroup]) {
        guard !isRemoving else { return }
        let selections = visible.compactMap { group -> (CleanCategoryType, [CleanSubItem])? in
            let items = selectedItems(in: group)
            return items.isEmpty ? nil : (group.type, items)
        }
        guard !selections.isEmpty else { return }
        pending = selections
        let trashGroup = groups.first { $0.type == .trash }
        pendingEmptiesTrash = trashGroup.map { group in
            !group.items.isEmpty && group.items.allSatisfy { selection.contains($0.id) }
        } ?? false
        let includesTrash = selections.contains { $0.0 == .trash }
        if CleanupOptions.requiresConfirmation || includesTrash {
            isConfirming = true
        } else {
            confirmClean()
        }
    }

    var pendingBytes: Int64 {
        pending.reduce(0) { total, entry in total + entry.1.reduce(0) { $0 + $1.size } }
    }

    var pendingIncludesTrash: Bool {
        pending.contains { $0.0 == .trash }
    }

    var pendingIncludesSnapshots: Bool {
        pending.contains { $0.0 == .timeMachineSnapshots }
    }

    var confirmationItems: [ConfirmationItem] {
        pending.flatMap { type, items in
            items.flatMap { item in
                item.members.map { member in
                    ConfirmationItem(
                        name: item.isCluster ? "\(item.name) · \(member.url.lastPathComponent)" : "\(type.rawValue) · \(item.name)",
                        path: item.customIcon != nil ? "\(localized("APFS Local Snapshot")) · \(item.name)" : member.url.path,
                        size: Formatting.bytes(member.size)
                    )
                }
            }
        }
    }

    func cancelClean() {
        isConfirming = false
        pending = []
    }

    func confirmClean() {
        isConfirming = false
        let selections = pending
        let emptiesTrash = pendingEmptiesTrash
        pending = []
        guard !selections.isEmpty else { return }
        let options = CleanupOptions.current
        isRemoving = true
        Task {
            let report = await SystemCleanEngine.clean(selections: selections, emptiesWholeTrash: emptiesTrash, options: options)
            self.apply(report)
        }
    }

    private func apply(_ report: RemovalReport) {
        let removed = Set(report.removedURLs.map(\.standardizedFileURL))
        groups = groups.map { group in
            var copy = group
            copy.items = group.items.compactMap { $0.removing(removed) }
            return copy
        }
        selection.formIntersection(Set(groups.flatMap { $0.items.map(\.id) }))
        isRemoving = false
        lastResult = report.result
        showsResult = true
        if report.result.success {
            PreferencesManager.shared.playCompletionSound()
        }
    }
}

private enum CleanRow: Identifiable {
    case header(CleanCategoryGroup)
    case empty(CleanCategoryType)
    case item(CleanSubItem)
    case member(CleanMember, parent: UUID)

    var id: String {
        switch self {
        case .header(let group): return "header-\(group.type.rawValue)"
        case .empty(let type): return "empty-\(type.rawValue)"
        case .item(let item): return "item-\(item.id)"
        case .member(let member, let parent): return "member-\(parent)-\(member.url.path)"
        }
    }
}

struct SystemCleanView: View {
    @State private var model = SystemCleanModel()
    @State private var scanRequest: UUID?
    @State private var searchText = ""

    init() {}

    var body: some View {
        content
            .toolbar {
                if !model.groups.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button(localized("Select Safe Only")) {
                                model.selectSafeOnly(in: model.visibleGroups(matching: searchText))
                            }
                            Button(localized("Select All")) {
                                let allItems = model.visibleGroups(matching: searchText).flatMap(\.items)
                                model.setSelection(true, for: allItems)
                            }
                            Divider()
                            Button(localized("Deselect All")) {
                                let allItems = model.visibleGroups(matching: searchText).flatMap(\.items)
                                model.setSelection(false, for: allItems)
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
                    .help(localized("Scan for caches, logs, and temporary files"))
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: localized("Filter caches and folders"))
            .task(id: scanRequest) {
                guard scanRequest != nil else { return }
                await model.scan()
            }
            .onChange(of: searchText) { _, query in
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                model.expanded.formUnion(model.visibleGroups(matching: query).map(\.type))
            }
            .sheet(isPresented: $model.isConfirming) {
                ConfirmationModal(
                    title: localized("Clean selected items?"),
                    subtitle: "\(model.confirmationItems.count) \(model.confirmationItems.count == 1 ? localized("item") : localized("items")) · \(Formatting.bytes(model.pendingBytes))",
                    confirmationItems: model.confirmationItems,
                    confirmActionTitle: localized("Clean"),
                    note: {
                        if model.pendingIncludesTrash && model.pendingIncludesSnapshots {
                            return localized("Trash items and Time Machine snapshots are permanently deleted. %@", CleanupOptions.current.deletionMode.confirmationNote)
                        } else if model.pendingIncludesSnapshots {
                            return localized("Time Machine snapshots are permanently deleted. %@", CleanupOptions.current.deletionMode.confirmationNote)
                        } else if model.pendingIncludesTrash {
                            return localized("Trash items are permanently deleted. %@", CleanupOptions.current.deletionMode.confirmationNote)
                        } else {
                            return CleanupOptions.current.deletionMode.confirmationNote
                        }
                    }(),
                    onConfirm: { model.confirmClean() },
                    onCancel: { model.cancelClean() }
                )
            }
            .alert(
                model.lastResult?.summaryTitle ?? localized("Done"),
                isPresented: $model.showsResult,
                presenting: model.lastResult
            ) { _ in
                Button(localized("OK")) {}
            } message: { result in
                Text(result.summaryMessage)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            CleanupStartView(
                title: localized("System clean"),
                systemImage: "sparkles",
                description: localized("Scans for app and browser caches, logs, crash reports, developer caches, forgotten installers, temporary files, and Trash. Nothing is selected by default.")
            ) {
                scanRequest = UUID()
            }
        case .scanning:
            CleanupProgressView(progress: model.progress) {
                model.cancelScan()
                scanRequest = nil
            }
        case .loaded:
            categoryList
        }
    }

    private func rows(for visible: [CleanCategoryGroup]) -> [CleanRow] {
        var rows: [CleanRow] = []
        for group in visible {
            rows.append(.header(group))
            guard model.expanded.contains(group.type) else { continue }
            if group.items.isEmpty {
                rows.append(.empty(group.type))
                continue
            }
            for item in group.items {
                rows.append(.item(item))
                guard item.isCluster, model.expandedItems.contains(item.id) else { continue }
                rows.append(contentsOf: item.members.map { .member($0, parent: item.id) })
            }
        }
        return rows
    }

    private var categoryList: some View {
        let visible = model.visibleGroups(matching: searchText)
        let visibleItems = visible.flatMap(\.items)
        let selectedVisible = visibleItems.filter { model.selection.contains($0.id) }
        let selection = model.selection
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows(for: visible)) { row in
                    rowView(row, selection: selection)
                }
            }
            .padding(.vertical, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionControlBar(
                totalCount: visibleItems.count,
                selectedCount: selectedVisible.count,
                selectedBytes: selectedVisible.reduce(0) { $0 + $1.size },
                actionTitle: localized("Clean…"),
                isBusy: model.isRemoving,
                busyMessage: localized("Cleaning…"),
                onToggleAll: { model.setSelection($0, for: visibleItems) },
                onAction: { model.requestClean(in: visible) }
            )
        }
        .background(.background)
    }

    @ViewBuilder
    private func rowView(_ row: CleanRow, selection: Set<UUID>) -> some View {
        switch row {
        case .header(let group):
            let selected = group.items.filter { selection.contains($0.id) }
            CleanCategoryRow(
                group: group,
                selectedCount: selected.count,
                selectedBytes: selected.reduce(0) { $0 + $1.size },
                isExpanded: model.expanded.contains(group.type),
                onToggleSelection: { model.setSelection($0, for: group.items) },
                onToggleExpansion: { toggle { model.toggleExpansion(of: group.type) } }
            )
        case .empty:
            Text(localized("Nothing to clean in this category."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CleanLayout.itemIndent)
                .padding(.trailing, CleanLayout.horizontalPadding)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.35))
        case .item(let item):
            CleanSubItemRow(
                item: item,
                isSelected: selection.contains(item.id),
                isExpanded: model.expandedItems.contains(item.id),
                onToggleSelection: { model.toggleSelection(of: item.id) },
                onToggleExpansion: { toggle { model.toggleExpansion(of: item.id) } }
            )
        case .member(let member, _):
            CleanMemberRow(member: member)
        }
    }

    private func toggle(_ change: () -> Void) {
        withAnimation(.snappy(duration: 0.22), change)
    }
}

private struct CleanCategoryRow: View {
    let group: CleanCategoryGroup
    let selectedCount: Int
    let selectedBytes: Int64
    let isExpanded: Bool
    let onToggleSelection: (Bool) -> Void
    let onToggleExpansion: () -> Void
    @State private var isHovered = false

    private var state: TriState {
        if group.items.isEmpty || selectedCount == 0 { return .off }
        return selectedCount == group.items.count ? .on : .mixed
    }

    private var tint: Color {
        group.type.safetyLevel.color
    }

    var body: some View {
        HStack(spacing: CleanLayout.rowSpacing) {
            TriStateCheckbox(state: state) {
                onToggleSelection(state != .on)
            }
            .disabled(group.items.isEmpty)
            .accessibilityLabel(state == .on ? localized("Deselect %@", group.type.title) : localized("Select %@", group.type.title))

            Button(action: onToggleExpansion) {
                HStack(spacing: CleanLayout.rowSpacing) {
                    HubIcon(systemName: group.type.systemIcon, tint: tint, size: CleanLayout.iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.type.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            StatusBadge(group.type.safetyLevel.title, icon: group.type.safetyLevel.icon, color: tint)
                        }
                        Text(group.type.categoryDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatting.bytes(selectedCount == 0 ? group.totalSize : selectedBytes))
                            .monospacedDigit()
                            .foregroundStyle(selectedCount == 0 ? .secondary : .primary)
                        Text(group.items.isEmpty ? localized("Cleaned") : localized("%d of %d", selectedCount, group.items.count))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.type.safetyTip)
            .accessibilityValue(isExpanded ? localized("Expanded") : localized("Collapsed"))
        }
        .padding(.horizontal, CleanLayout.horizontalPadding)
        .padding(.vertical, 9)
        .background(isHovered ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, CleanLayout.itemIndent)
        }
        .onHover { isHovered = $0 }
    }
}

private struct CleanSubItemRow: View {
    let item: CleanSubItem
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleSelection: () -> Void
    let onToggleExpansion: () -> Void
    @State private var isHovered = false

    private var subtitle: String {
        if item.customIcon != nil || item.url.path.contains(".timemachine") {
            return localized("APFS Local Snapshot")
        }
        guard item.isCluster else { return item.url.path }
        return "\(item.members.count) itens em \(item.url.deletingLastPathComponent().path)"
    }

    var body: some View {
        HStack(spacing: CleanLayout.rowSpacing) {
            TriStateCheckbox(state: isSelected ? .on : .off, action: onToggleSelection)
                .accessibilityLabel("Selecionar \(item.name)")

            Button(action: item.isCluster ? onToggleExpansion : onToggleSelection) {
                HStack(spacing: CleanLayout.rowSpacing) {
                    CleanupItemLabel(title: item.displayName, path: subtitle, systemImage: item.customIcon ?? (item.isCluster ? "square.stack" : "folder"))
                    if item.isAppRunning {
                        StatusBadge(localized("Running"), icon: "exclamationmark.circle", color: .orange)
                            .help(localized("Application is actively running. Quit the app before cleaning for best results."))
                    }
                    Spacer(minLength: 8)
                    Text(item.formattedSize)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if item.isCluster {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 14)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RevealInFinderButton(url: item.url)
        }
        .padding(.leading, CleanLayout.itemIndent)
        .padding(.trailing, CleanLayout.horizontalPadding)
        .padding(.vertical, 6)
        .background(isHovered ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.quaternary.opacity(0.25)))
        .onHover { isHovered = $0 }
    }
}

private struct CleanMemberRow: View {
    let member: CleanMember

    var body: some View {
        HStack(spacing: CleanLayout.rowSpacing) {
            Image(systemName: "doc")
                .foregroundStyle(.tertiary)
                .frame(width: CleanLayout.checkboxWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(member.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Formatting.bytes(member.size))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            RevealInFinderButton(url: member.url)
        }
        .padding(.leading, CleanLayout.memberIndent)
        .padding(.trailing, CleanLayout.horizontalPadding)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.25))
        .help(member.url.path)
    }
}
