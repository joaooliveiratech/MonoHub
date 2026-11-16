import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @Bindable private var prefs = CleanupPreferences.shared
    @State private var model = CleanupListModel<LargeFileItem> { items, options in
        await DiskAnalyzerEngine.shared.remove(files: items, options: options)
    }
    @State private var volumeStats: VolumeStats?
    @State private var scanRequest: UUID?
    @State private var searchText = ""
    @State private var typeFilter: LargeFileType?
    @State private var sortOrder = [KeyPathComparator(\LargeFileItem.size, order: .reverse)]
    @State private var highlightedRows = Set<UUID>()

    private static let thresholds: [(String, Double)] = [
        ("50 MB", 52_428_800),
        ("100 MB", 104_857_600),
        ("250 MB", 262_144_000),
        ("500 MB", 524_288_000),
        ("1 GB", 1_073_741_824)
    ]

    init() {}

    private var visibleItems: [LargeFileItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return model.items.filter { file in
            (typeFilter == nil || file.fileType == typeFilter)
                && (query.isEmpty
                    || file.name.localizedCaseInsensitiveContains(query)
                    || file.url.path.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let volumeStats {
                VolumeUsageCard(stats: volumeStats)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
            }
            content
        }
        .toolbar {
            ToolbarItem {
                Picker(localized("Minimum size"), selection: $prefs.largeFileThresholdBytes) {
                    ForEach(Self.thresholds, id: \.1) { title, value in
                        Text(localized("Above %@", title)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .help(localized("Minimum size of listed files"))
                .disabled(model.phase == .scanning)
            }
            if model.phase == .loaded && !model.items.isEmpty {
                ToolbarItem {
                    Picker(localized("Type"), selection: $typeFilter) {
                        Text(localized("All types")).tag(LargeFileType?.none)
                        Divider()
                        ForEach(LargeFileType.allCases, id: \.self) { type in
                            Label(type.title, systemImage: type.systemIcon).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.menu)
                    .help(localized("Filter by file type"))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    scanRequest = UUID()
                } label: {
                    Label(localized("Scan"), systemImage: "arrow.clockwise")
                }
                .disabled(model.phase == .scanning || model.isRemoving)
                .help(localized("Scan for large files"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Filter files"))
        .task {
            volumeStats = await Self.loadVolumeStats()
        }
        .task(id: scanRequest) {
            guard scanRequest != nil else { return }
            let threshold = Int64(prefs.largeFileThresholdBytes)
            typeFilter = nil
            await model.scan { reporter in
                await DiskAnalyzerEngine.shared.scanLargeFiles(thresholdBytes: threshold, progress: reporter)
            }
        }
        .onChange(of: prefs.largeFileThresholdBytes) { _, _ in
            if model.phase == .loaded {
                scanRequest = UUID()
            }
        }
        .onChange(of: model.isRemoving) { _, isRemoving in
            guard !isRemoving else { return }
            Task { volumeStats = await Self.loadVolumeStats() }
        }
        .onChange(of: sortOrder) { _, newOrder in
            model.sort(using: newOrder)
        }
        .cleanupRemovalFlow(model, title: localized("Remove large files?"), actionTitle: localized("Remove"))
    }

    @concurrent
    nonisolated private static func loadVolumeStats() async -> VolumeStats {
        DiskAnalyzerEngine.shared.getVolumeStats()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            CleanupStartView(
                title: localized("Large files"),
                systemImage: "internaldrive",
                description: localized("Scans for files larger than %@ in Downloads, Documents, Desktop, Movies, and Music. Nothing is selected by default.", Formatting.bytes(Int64(prefs.largeFileThresholdBytes)))
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
                localized("No large files"),
                systemImage: "checkmark.circle",
                description: Text(localized("No files larger than %@ in the analyzed folders.", Formatting.bytes(Int64(prefs.largeFileThresholdBytes))))
            )
        case .loaded:
            resultsTable
        }
    }

    private var resultsTable: some View {
        let visible = visibleItems
        let selectedVisible = visible.filter { model.selection.contains($0.id) }
        return Table(visible, selection: $highlightedRows, sortOrder: $sortOrder) {
            TableColumn("") { item in
                SelectionCheckbox(isOn: model.isSelected(item.id))
            }
            .width(22)
            TableColumn(localized("File"), value: \.name) { item in
                CleanupItemLabel(title: item.name, path: item.url.path, systemImage: item.fileType.systemIcon)
            }
            .width(min: 240, ideal: 400)
            TableColumn(localized("Type"), value: \.typeName) { item in
                Text(item.typeName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150)
            TableColumn(localized("Modified"), value: \.lastModified) { item in
                Text(item.formattedDate)
                    .foregroundStyle(.secondary)
                    .help(Formatting.date(item.lastModified))
            }
            .width(min: 100, ideal: 130)
            TableColumn(localized("Size"), value: \.size) { item in
                SizeText(bytes: item.size)
            }
            .width(min: 80, ideal: 90)
            TableColumn("") { item in
                RevealInFinderButton(url: item.url)
            }
            .width(24)
        }
        .contextMenu(forSelectionType: LargeFileItem.ID.self) { ids in
            let targets = visible.filter { ids.contains($0.id) }
            if !targets.isEmpty {
                Button(localized("Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
                }
                Button(localized("Remove…"), role: .destructive) {
                    model.requestRemoval(targets)
                }
            }
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

private struct VolumeUsageCard: View {
    let stats: VolumeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text(String(format: localized("%@ available of %@"), stats.formattedFree, stats.formattedTotal))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Gauge(value: stats.usedPercentage) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(stats.usedPercentage > 0.9 ? .red : .accentColor)
            .accessibilityLabel(String(format: localized("Disk usage: %@"), stats.formattedPercentage))
        }
        .hubCard()
    }
}
