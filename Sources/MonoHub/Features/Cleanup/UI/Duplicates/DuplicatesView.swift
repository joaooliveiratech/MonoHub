import SwiftUI
import AppKit

struct DuplicatesView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var isScanning = false
    @State private var isRemoving = false
    @State private var scanProgress: Double = 0
    @State private var scanStatusMessage: String = ""
    @State private var mode: DuplicatesScanMode = .exactHash
    @State private var minSizeThreshold: Int64 = 102400
    @State private var showRemovalConfirmation = false
    @State private var lastResult: ExecutionResult?
    @State private var showsResult = false

    private let engine = DuplicatesEngine.shared

    private static let defaultFolders: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    ]

    private var allItems: [DuplicateItem] {
        groups.flatMap(\.items)
    }

    private var selectedItems: [DuplicateItem] {
        allItems.filter(\.isSelected)
    }

    private var totalRecoverableBytes: Int64 {
        groups.reduce(0) { $0 + $1.recoverableSize }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSummary
            Divider()

            if isScanning {
                scanningProgressView
            } else if groups.isEmpty {
                emptyStateView
            } else {
                resultsList
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker(localized("Mode"), selection: $mode) {
                    ForEach(DuplicatesScanMode.allCases) { m in
                        Label(m.title, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isScanning)
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(localized("Keep Oldest (Select Newer)")) {
                        engine.applySelectionStrategy(.keepOldest, to: &groups)
                    }
                    Button(localized("Keep Newest (Select Older)")) {
                        engine.applySelectionStrategy(.keepNewest, to: &groups)
                    }
                    Button(localized("Keep Shortest Path")) {
                        engine.applySelectionStrategy(.keepShortestPath, to: &groups)
                    }
                    Divider()
                    Button(localized("Deselect All")) {
                        for i in 0..<groups.count {
                            for j in 0..<groups[i].items.count {
                                groups[i].items[j].isSelected = false
                            }
                        }
                    }
                } label: {
                    Label(localized("Smart Select"), systemImage: "checklist")
                }
                .disabled(isScanning || groups.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await startScan() }
                } label: {
                    Label(localized("Scan"), systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
                .help(localized("Scan for duplicates"))
            }
        }
        .task {
            await startScan()
        }
        .onChange(of: mode) { _, _ in
            Task { await startScan() }
        }
        .sheet(isPresented: $showRemovalConfirmation) {
            let safeSelected = DuplicatesEngine.safeItemsToRemove(from: groups)
            let safeBytes = safeSelected.reduce(Int64(0)) { $0 + $1.size }
            ConfirmationModal(
                title: localized("Move %d duplicate files to Trash?", safeSelected.count),
                subtitle: localized("The selected duplicate copies will be moved to the Trash, freeing %@ of disk space. One original copy in each group is always kept.", Formatting.bytes(safeBytes)),
                items: safeSelected.map { (name: $0.name, path: $0.url.path, size: Formatting.bytes($0.size)) },
                confirmActionTitle: localized("Move to Trash"),
                onConfirm: {
                    showRemovalConfirmation = false
                    let currentGroups = groups
                    let options = CleanupOptions.current
                    isRemoving = true
                    Task {
                        let report = await engine.removeDuplicates(items: safeSelected, groups: currentGroups, options: options)
                        let removedURLs = Set(report.removedURLs.map(\.standardizedFileURL))
                        await MainActor.run {
                            groups = groups.compactMap { group in
                                var copy = group
                                copy.items.removeAll { removedURLs.contains($0.url.standardizedFileURL) }
                                return copy.items.count >= 2 ? copy : nil
                            }
                            isRemoving = false
                            lastResult = report.result
                            showsResult = true
                            if report.result.success {
                                PreferencesManager.shared.playCompletionSound()
                            }
                        }
                    }
                },
                onCancel: {
                    showRemovalConfirmation = false
                }
            )
        }
        .alert(
            lastResult?.summaryTitle ?? localized("Done"),
            isPresented: $showsResult,
            presenting: lastResult
        ) { _ in
            Button(localized("OK")) {}
        } message: { result in
            Text(result.summaryMessage)
        }
    }

    private var headerSummary: some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                HubIcon(systemName: mode == .exactHash ? "doc.on.doc.fill" : "photo.on.rectangle.angled", tint: .purple, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.headline)
                    Text(localized("%d duplicate groups found · %@ recoverable", groups.count, Formatting.bytes(totalRecoverableBytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selectedBytes > 0 {
                StatusBadge(localized("%@ selected to clean", Formatting.bytes(selectedBytes)), icon: "trash", color: .purple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach($groups) { $group in
                        duplicateGroupCard(group: $group)
                    }
                }
                .padding(HubMetrics.pagePadding)
            }

            Divider()

            SelectionControlBar(
                totalCount: allItems.count,
                selectedCount: selectedItems.count,
                selectedBytes: selectedBytes,
                actionTitle: localized("Move Duplicates to Trash…"),
                isBusy: isScanning || isRemoving,
                onToggleAll: { selectAll in
                    for i in 0..<groups.count {
                        for j in 0..<groups[i].items.count {

                            groups[i].items[j].isSelected = selectAll ? (j > 0) : false
                        }
                    }
                },
                onAction: {
                    DuplicatesEngine.sanitizeSelections(in: &groups)
                    showRemovalConfirmation = true
                }
            )
        }
    }

    private func duplicateGroupCard(group: Binding<DuplicateGroup>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: group.wrappedValue.isVisualSimilarity ? "photo.stack" : "doc.on.doc")
                        .foregroundStyle(.purple)
                    Text(localized("Group of %d copies", group.wrappedValue.items.count))
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Text(localized("%@ each · %@ recoverable", Formatting.bytes(group.wrappedValue.sizePerItem), Formatting.bytes(group.wrappedValue.recoverableSize)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(group.items) { $item in
                    duplicateItemRow(item: $item, in: group)
                }
            }
        }
        .hubCard()
    }

    private func duplicateItemRow(item: Binding<DuplicateItem>, in group: Binding<DuplicateGroup>) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.wrappedValue.isSelected },
                set: { newValue in
                    item.wrappedValue.isSelected = newValue
                    if newValue && group.wrappedValue.items.allSatisfy(\.isSelected) {
                        if let keepIdx = group.wrappedValue.items.firstIndex(where: { $0.id != item.wrappedValue.id }) {
                            group.wrappedValue.items[keepIdx].isSelected = false
                        }
                    }
                }
            ))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.wrappedValue.url.path))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.wrappedValue.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if !item.wrappedValue.isSelected {
                        StatusBadge(localized("Keep Original"), icon: "checkmark.shield", color: .green)
                    }
                }
                Text(item.wrappedValue.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(Formatting.date(item.wrappedValue.modifiedDate))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.wrappedValue.url])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(localized("Reveal in Finder"))
        }
        .padding(.vertical, 4)
    }

    private var scanningProgressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 280)
            Text(scanStatusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            localized("No Duplicate Files Found"),
            systemImage: "checkmark.circle.fill",
            description: Text(localized("No duplicated files or similar photos were detected in your standard folders."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startScan() async {
        isScanning = true
        scanProgress = 0
        scanStatusMessage = localized("Initializing scan…")

        let results = await engine.scanDuplicates(
            folders: Self.defaultFolders,
            minSizeBytes: minSizeThreshold,
            mode: mode
        ) { progress, message in
            Task { @MainActor in
                self.scanProgress = progress
                self.scanStatusMessage = message
            }
        }

        await MainActor.run {
            self.groups = results
            self.isScanning = false
        }
    }
}
