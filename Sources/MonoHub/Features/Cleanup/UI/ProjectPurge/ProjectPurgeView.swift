import AppKit
import SwiftUI

struct ProjectPurgeView: View {
    private let prefs = CleanupPreferences.shared
    @State private var model = CleanupListModel<ProjectArtifact> { items, options in
        let paths = await MainActor.run { CleanupPreferences.shared.devScanPaths }
        return await ProjectPurgeEngine.purge(artifacts: items, scanPaths: paths, options: options)
    }
    @State private var scanRequest: UUID?
    @State private var searchText = ""
    @State private var typeFilter: String?
    @State private var sortOrder = [KeyPathComparator(\ProjectArtifact.size, order: .reverse)]

    init() {}

    private var artifactTypes: [String] {
        Array(Set(model.items.map(\.artifactType))).sorted()
    }

    private var visibleItems: [ProjectArtifact] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return model.items.filter { artifact in
            (typeFilter == nil || artifact.artifactType == typeFilter)
                && (query.isEmpty
                    || artifact.projectName.localizedCaseInsensitiveContains(query)
                    || artifact.path.path.localizedCaseInsensitiveContains(query))
        }
    }

    private var scanPathsDescription: String {
        prefs.devScanPaths.isEmpty ? localized("no folders configured") : prefs.devScanPaths.joined(separator: ", ")
    }

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scanRequest = UUID()
                    } label: {
                        Label(localized("Scan"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.phase == .scanning || model.isRemoving || prefs.devScanPaths.isEmpty)
                    .help(localized("Scan for build artifacts in project folders"))
                }
                if model.phase == .loaded && !model.items.isEmpty {
                    ToolbarItem {
                        Picker(localized("Type"), selection: $typeFilter) {
                            Text(localized("All types")).tag(String?.none)
                            Divider()
                            ForEach(artifactTypes, id: \.self) { type in
                                Text(type).tag(Optional(type))
                            }
                        }
                        .pickerStyle(.menu)
                        .help(localized("Filter by artifact type"))
                    }
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button(localized("Select Inactive (> 48h)")) {
                                let inactiveIds = Set(visibleItems.filter { !$0.isRecent }.map(\.id))
                                model.selection = inactiveIds
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
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: localized("Filter projects"))
            .task(id: scanRequest) {
                guard scanRequest != nil else { return }
                let paths = prefs.devScanPaths
                let depth = prefs.projectScanMaxDepth
                let age = prefs.projectArtifactAgeDays
                typeFilter = nil
                await model.scan { reporter in
                    await ProjectPurgeEngine.scanProjects(at: paths, maxDepth: depth, minimumAgeDays: age, progress: reporter)
                }
            }
            .onChange(of: sortOrder) { _, newOrder in
                model.sort(using: newOrder)
            }
            .cleanupRemovalFlow(model, title: localized("Remove build artifacts?"), actionTitle: localized("Remove"))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label(localized("Build artifacts"), systemImage: "hammer")
            } description: {
                Text(localized("Finds node_modules, .build, target, .venv, Pods, and other generated folders in: %@. Only the artifact folder is removed, never the project, and it can be recreated by the package manager.", scanPathsDescription))
            } actions: {
                Button(localized("Scan")) {
                    scanRequest = UUID()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(prefs.devScanPaths.isEmpty)
                Button(localized("Configure Folders…")) {
                    HubNavigation.shared.select(.settings)
                }
            }
        case .scanning:
            CleanupProgressView(progress: model.progress) {
                model.cancelScan()
                scanRequest = nil
            }
        case .loaded where model.items.isEmpty:
            ContentUnavailableView(
                localized("No artifacts found"),
                systemImage: "checkmark.circle",
                description: Text(localized("Configured folders do not contain build artifacts up to %d levels deep.", prefs.projectScanMaxDepth))
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
            TableColumn(localized("Project"), value: \.projectName) { item in
                CleanupItemLabel(title: item.projectName, path: item.path.path, systemImage: icon(for: item.artifactType))
            }
            .width(min: 240, ideal: 380)
            TableColumn(localized("Artifact"), value: \.artifactType) { item in
                Text(item.artifactType)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn(localized("Modified"), value: \.lastModified) { item in
                Text(item.formattedDate)
                    .foregroundStyle(item.isRecent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .help(item.isRecent ? localized("Project used in the last 48 hours") : Formatting.date(item.lastModified))
            }
            .width(min: 100, ideal: 130)
            TableColumn(localized("Size"), value: \.size) { item in
                SizeText(bytes: item.size)
            }
            .width(min: 80, ideal: 90)
            TableColumn("") { item in
                RevealInFinderButton(url: item.path)
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

    private func icon(for type: String) -> String {
        switch type {
        case "node_modules": return "shippingbox"
        case ".build": return "swift"
        case "target": return "gearshape.2"
        case ".venv", "venv", ".pytest_cache": return "terminal"
        case "Pods": return "cube"
        case ".gradle": return "hammer"
        case ".next", ".nuxt", ".astro", ".svelte-kit": return "globe"
        case ".turbo": return "bolt"
        case ".dart_tool": return "target"
        default: return "folder"
        }
    }
}
