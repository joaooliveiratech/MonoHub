import AppKit
import SwiftUI

@Observable
@MainActor
final class UninstallerModel {
    private(set) var apps: [AppItem] = []
    private(set) var bundleSizes: [UUID: Int64] = [:]
    private(set) var isLoadingApps = false
    var selectedAppID: UUID?
    private(set) var remnants: [RemnantItem] = []
    private(set) var remnantsAppID: UUID?
    private(set) var isLoadingRemnants = false
    var remnantSelection: Set<UUID> = []
    private(set) var isUninstalling = false
    var isConfirming = false
    var lastResult: ExecutionResult?
    var showsResult = false

    var selectedApp: AppItem? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID }
    }

    var selectedRemnants: [RemnantItem] {
        remnants.filter { remnantSelection.contains($0.id) }
    }

    func filteredApps(searchText: String, runningOnly: Bool) -> [AppItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return apps.filter { app in
            (!runningOnly || app.isRunning)
                && (query.isEmpty
                    || app.name.localizedCaseInsensitiveContains(query)
                    || app.bundleIdentifier.localizedCaseInsensitiveContains(query))
        }
    }

    func loadApps() async {
        isLoadingApps = true
        let running = AppScanner.runningApplications()
        let scanned = await AppScanner.scanInstalledApps(running: running)
        guard !Task.isCancelled else {
            isLoadingApps = false
            return
        }
        apps = scanned
        isLoadingApps = false
        if let selectedAppID, !scanned.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }
        let missing = scanned.filter { bundleSizes[$0.id] == nil }
        await AppScanner.computeBundleSizes(for: missing) { [weak self] batch in
            await MainActor.run { [weak self] in
                self?.bundleSizes.merge(batch) { _, new in new }
            }
        }
    }

    func reload() async {
        let selectedURL = selectedApp?.bundleURL
        bundleSizes = [:]
        await loadApps()
        if let selectedURL {
            selectedAppID = apps.first { $0.bundleURL == selectedURL }?.id
        }
    }

    func loadRemnants(for app: AppItem?) async {
        guard let app else {
            remnants = []
            remnantsAppID = nil
            remnantSelection = []
            isLoadingRemnants = false
            return
        }
        guard remnantsAppID != app.id else { return }
        isLoadingRemnants = true
        remnants = []
        remnantSelection = []
        let found = await RemnantFinder.shared.findRemnants(
            for: app.bundleURL,
            bundleIdentifier: app.bundleIdentifier,
            appName: app.name
        )
        guard !Task.isCancelled, selectedAppID == app.id else { return }
        remnants = found
        remnantsAppID = app.id
        remnantSelection = Set(found.filter(\.isSelected).map(\.id))
        isLoadingRemnants = false
    }

    func isSelected(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.remnantSelection.contains(id) },
            set: { isOn in
                if isOn {
                    self.remnantSelection.insert(id)
                } else {
                    self.remnantSelection.remove(id)
                }
            }
        )
    }

    func setSelection(_ isOn: Bool) {
        remnantSelection = isOn ? Set(remnants.map(\.id)) : []
    }

    func requestUninstall() {
        guard let app = selectedApp, !app.isProtected, !selectedRemnants.isEmpty, !isUninstalling else { return }
        if CleanupOptions.requiresConfirmation || app.isRunning {
            isConfirming = true
        } else {
            confirmUninstall()
        }
    }

    func confirmUninstall() {
        isConfirming = false
        guard let app = selectedApp else { return }
        let targets = selectedRemnants
        guard !targets.isEmpty else { return }
        let options = CleanupOptions.current
        isUninstalling = true
        Task {
            let report = await AppUninstallEngine.uninstall(app: app, remnants: targets, options: options)
            self.apply(report, app: app)
        }
    }

    private func apply(_ report: RemovalReport, app: AppItem) {
        isUninstalling = false
        let removed = Set(report.removedURLs.map(\.standardizedFileURL))
        if removed.contains(app.bundleURL.standardizedFileURL) {
            apps.removeAll { $0.id == app.id }
            bundleSizes[app.id] = nil
            if selectedAppID == app.id {
                selectedAppID = nil
            }
            remnants = []
            remnantsAppID = nil
            remnantSelection = []
        } else if remnantsAppID == app.id {
            remnants.removeAll { removed.contains($0.url.standardizedFileURL) }
            remnantSelection.formIntersection(Set(remnants.map(\.id)))
        }
        lastResult = report.result
        showsResult = true
        if report.result.success {
            PreferencesManager.shared.playCompletionSound()
        }
    }

    var confirmationItems: [ConfirmationItem] {
        selectedRemnants.map {
            ConfirmationItem(name: "\($0.category.title) · \($0.displayName)", path: $0.path, size: $0.formattedSize)
        }
    }
}

struct UninstallerView: View {
    @State private var model = UninstallerModel()
    @State private var searchText = ""
    @State private var runningOnly = false
    @State private var reloadToken = 0

    init() {}

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 380)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $runningOnly) {
                    Label(localized("Running only"), systemImage: "bolt.circle")
                }
                .help(localized("Show running applications only"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    reloadToken += 1
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingApps || model.isUninstalling)
                .help(localized("Refresh applications list"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Search applications"))
        .task(id: reloadToken) {
            if reloadToken == 0 {
                await model.loadApps()
            } else {
                await model.reload()
            }
        }
        .task(id: model.selectedAppID) {
            await model.loadRemnants(for: model.selectedApp)
        }
        .sheet(isPresented: $model.isConfirming) {
            if let app = model.selectedApp {
                ConfirmationModal(
                    title: localized("Uninstall “%@”?", app.name),
                    subtitle: app.isRunning
                        ? localized("%@ is running and will be quit before removal. Save your documents.", app.name)
                        : "\(model.selectedRemnants.count) \(model.selectedRemnants.count == 1 ? localized("item") : localized("items")) · \(Formatting.bytes(model.selectedRemnants.reduce(0) { $0 + $1.size }))",
                    confirmationItems: model.confirmationItems,
                    confirmActionTitle: localized("Uninstall"),
                    note: CleanupOptions.current.deletionMode.confirmationNote,
                    onConfirm: { model.confirmUninstall() },
                    onCancel: { model.isConfirming = false }
                )
            }
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

    private var appList: some View {
        let visible = model.filteredApps(searchText: searchText, runningOnly: runningOnly)
        return List(visible, selection: $model.selectedAppID) { app in
            AppRow(app: app, size: model.bundleSizes[app.id])
                .tag(app.id)
        }
        .listStyle(.inset)
        .overlay {
            if model.isLoadingApps && model.apps.isEmpty {
                ProgressView()
            } else if visible.isEmpty && !model.isLoadingApps {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(localized("%d of %d applications", visible.count, model.apps.count))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .hubFloatingBar(cornerRadius: nil)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                AppHeader(app: app, totalBytes: model.remnants.reduce(0) { $0 + $1.size })
                    .padding(16)
                Divider()
                remnantsTable(for: app)
            }
        } else {
            ContentUnavailableView(
                localized("Select an application"),
                systemImage: "app.badge.checkmark",
                description: Text(localized("Review the app and files it left in ~/Library before uninstalling. Items matched by name only are unchecked by default."))
            )
        }
    }

    @ViewBuilder
    private func remnantsTable(for app: AppItem) -> some View {
        if model.isLoadingRemnants {
            VStack(spacing: 10) {
                ProgressView()
                Text(localized("Searching files for %@…", app.name))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.remnants) {
                TableColumn("") { item in
                    SelectionCheckbox(isOn: model.isSelected(item.id))
                        .disabled(app.isProtected)
                }
                .width(22)
                TableColumn(localized("Item")) { item in
                    CleanupItemLabel(title: item.displayName, path: item.path, systemImage: item.category.systemIcon)
                }
                .width(min: 220, ideal: 360)
                TableColumn(localized("Type")) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.category.title)
                        if item.match == .appName {
                            Text(localized("Matched by name"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .help(item.category.detail)
                }
                .width(min: 110, ideal: 150)
                TableColumn(localized("Size")) { item in
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
                    totalCount: model.remnants.count,
                    selectedCount: model.remnantSelection.count,
                    selectedBytes: model.selectedRemnants.reduce(0) { $0 + $1.size },
                    actionTitle: localized("Uninstall…"),
                    isBusy: model.isUninstalling,
                    busyMessage: localized("Uninstalling…"),
                    isActionEnabled: !app.isProtected,
                    onToggleAll: { model.setSelection($0) },
                    onAction: { model.requestUninstall() }
                )
            }
        }
    }
}

private struct AppRow: View {
    let app: AppItem
    let size: Int64?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.shared.icon(for: app.bundleURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .lineLimit(1)
                    if app.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(localized("Running"))
                    }
                }
                Text(app.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let size {
                Text(Formatting.bytes(size))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AppHeader: View {
    let app: AppItem
    let totalBytes: Int64

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppIconCache.shared.icon(for: app.bundleURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.title3.weight(.semibold))
                    if app.isRunning {
                        StatusBadge(localized("Running"), icon: "bolt.fill", color: .green)
                    }
                    if app.isProtected {
                        StatusBadge(localized("Protected"), icon: "lock.fill", color: .secondary)
                    }
                }
                Text(app.bundleIdentifier.isEmpty ? app.bundleURL.path : "\(app.bundleIdentifier) · \(app.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.bytes(totalBytes))
                    .font(.title3)
                    .monospacedDigit()
                Text(localized("in total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
