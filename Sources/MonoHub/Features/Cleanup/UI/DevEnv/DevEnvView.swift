import SwiftUI
import AppKit

struct DevEnvView: View {
    @State private var items: [DevEnvItem] = []
    @State private var isScanning = false
    @State private var isRemoving = false
    @State private var scanProgress: Double = 0
    @State private var scanStatusMessage: String = ""
    @State private var selectedCategory: DevEnvCategory?
    @State private var searchText = ""
    @State private var showCleanConfirmation = false
    @State private var lastResult: ExecutionResult?
    @State private var showsResult = false

    private let engine = DevEnvEngine.shared

    private var filteredItems: [DevEnvItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if let cat = selectedCategory, item.category != cat {
                return false
            }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || item.url.path.lowercased().contains(query)
                || item.detail.lowercased().contains(query)
        }
    }

    private var selectedItems: [DevEnvItem] {
        items.filter(\.isSelected)
    }

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSummary
            Divider()

            if isScanning && items.isEmpty {
                scanningProgressView
            } else if items.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    categoryCardsRow
                    Divider()
                    envTable
                    Divider()
                    selectionBar
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker(localized("Category"), selection: $selectedCategory) {
                    Text(localized("All Categories")).tag(DevEnvCategory?.none)
                    Divider()
                    ForEach(DevEnvCategory.allCases) { cat in
                        Label(cat.title, systemImage: cat.icon).tag(Optional(cat))
                    }
                }
                .pickerStyle(.menu)
                .disabled(isScanning)
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(localized("Select All Safe Caches")) {
                        for i in 0..<items.count {
                            items[i].isSelected = items[i].isSafeCache
                        }
                    }
                    Button(localized("Select DerivedData Only")) {
                        for i in 0..<items.count {
                            items[i].isSelected = items[i].name.contains("DerivedData")
                        }
                    }
                    Divider()
                    Button(localized("Deselect All")) {
                        for i in 0..<items.count {
                            items[i].isSelected = false
                        }
                    }
                } label: {
                    Label(localized("Quick Select"), systemImage: "checklist")
                }
                .disabled(isScanning || items.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await startScan() }
                } label: {
                    Label(localized("Scan"), systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
                .help(localized("Scan developer environments"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Search environments, projects, caches"))
        .task {
            await startScan()
        }
        .sheet(isPresented: $showCleanConfirmation) {
            ConfirmationModal(
                title: localized("Clean %d developer environment items?", selectedItems.count),
                subtitle: localized("The selected items will be moved to the Trash, freeing %@ of disk space. Safe caches can be re-downloaded or recompiled automatically.", Formatting.bytes(selectedBytes)),
                items: selectedItems.map { (name: $0.name, path: $0.url.path, size: Formatting.bytes($0.sizeBytes)) },
                confirmActionTitle: localized("Move to Trash"),
                onConfirm: {
                    showCleanConfirmation = false
                    let toRemove = selectedItems
                    let options = CleanupOptions.current
                    isRemoving = true
                    Task {
                        let report = await engine.removeItems(toRemove, options: options)
                        let removedURLs = Set(report.removedURLs.map(\.standardizedFileURL))
                        await MainActor.run {
                            items.removeAll { removedURLs.contains($0.url.standardizedFileURL) }
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
                    showCleanConfirmation = false
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
                HubIcon(systemName: "hammer.fill", tint: .blue, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Developer Environments & Toolchains"))
                        .font(.headline)
                    Text(localized("%d items across Xcode, Node, Python, Homebrew · %@ total", items.count, Formatting.bytes(totalBytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selectedBytes > 0 {
                StatusBadge(localized("%@ selected to clean", Formatting.bytes(selectedBytes)), icon: "trash", color: .blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var categoryCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DevEnvCategory.allCases) { cat in
                    let catItems = items.filter { $0.category == cat }
                    let catBytes = catItems.reduce(0) { $0 + $1.sizeBytes }

                    Button {
                        if selectedCategory == cat {
                            selectedCategory = nil
                        } else {
                            selectedCategory = cat
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(cat.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cat.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(Formatting.bytes(catBytes))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedCategory == cat ? cat.color.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedCategory == cat ? cat.color : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var envTable: some View {
        Table(filteredItems) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { newVal in
                        if let idx = items.firstIndex(where: { $0.id == item.id }) {
                            items[idx].isSelected = newVal
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            .width(22)

            TableColumn(localized("Toolchain / Environment")) { item in
                HStack(spacing: 10) {
                    HubIcon(systemName: item.category.icon, tint: item.category.color, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Text(item.url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 240, ideal: 360)

            TableColumn(localized("Category")) { item in
                StatusBadge(item.category.title, color: item.category.color)
            }
            .width(min: 100, ideal: 120)

            TableColumn(localized("Safety")) { item in
                if item.isSafeCache {
                    StatusBadge(localized("Safe Cache"), icon: "checkmark.shield", color: .green)
                } else {
                    StatusBadge(localized("Runtime / Image"), icon: "shippingbox", color: .secondary)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn(localized("Size")) { item in
                Text(Formatting.bytes(item.sizeBytes))
                    .font(.caption.weight(.semibold))
            }
            .width(min: 80, ideal: 100)

            TableColumn(localized("Actions")) { item in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(localized("Reveal in Finder"))
            }
            .width(36)
        }
    }

    private var selectionBar: some View {
        let visible = filteredItems
        let visibleIds = Set(visible.map(\.id))
        let selectedVisible = visible.filter(\.isSelected)
        return SelectionControlBar(
            totalCount: visible.count,
            selectedCount: selectedVisible.count,
            selectedBytes: selectedVisible.reduce(0) { $0 + $1.sizeBytes },
            actionTitle: localized("Clean Selected Environments…"),
            isBusy: isScanning || isRemoving,
            onToggleAll: { selectAll in
                for i in 0..<items.count where visibleIds.contains(items[i].id) {
                    items[i].isSelected = selectAll ? items[i].isSafeCache : false
                }
            },
            onAction: {
                showCleanConfirmation = true
            }
        )
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
            localized("No Developer Environments Found"),
            systemImage: "hammer",
            description: Text(localized("No developer toolchains, build caches, or runtimes were discovered in standard locations."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startScan() async {
        isScanning = true
        scanProgress = 0
        scanStatusMessage = localized("Initializing scan…")

        let scanned = await engine.scanItems { progress, message in
            Task { @MainActor in
                self.scanProgress = progress
                self.scanStatusMessage = message
            }
        }

        await MainActor.run {
            self.items = scanned
            self.isScanning = false
        }
    }
}
