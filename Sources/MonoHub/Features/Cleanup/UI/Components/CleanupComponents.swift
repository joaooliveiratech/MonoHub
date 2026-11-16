import SwiftUI

enum CleanupPhase: Equatable {
    case idle
    case scanning
    case loaded
}

@Observable
@MainActor
final class CleanupListModel<Item: CleanupListItem> {
    typealias Remover = @Sendable ([Item], CleanupOptions) async -> RemovalReport

    private(set) var items: [Item] = []
    var selection: Set<UUID> = []
    private(set) var phase: CleanupPhase = .idle
    private(set) var progress = ScanProgress(message: "")
    private(set) var isRemoving = false
    private(set) var pendingRemoval: [Item] = []
    var isConfirming = false
    var lastResult: ExecutionResult?
    var showsResult = false

    @ObservationIgnored private let remover: Remover

    init(remover: @escaping Remover) {
        self.remover = remover
    }

    var selectedItems: [Item] {
        items.filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        items.reduce(0) { selection.contains($1.id) ? $0 + $1.itemSize : $0 }
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.itemSize }
    }

    func isSelected(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.selection.contains(id) },
            set: { isOn in
                if isOn {
                    self.selection.insert(id)
                } else {
                    self.selection.remove(id)
                }
            }
        )
    }

    func setSelection(_ isOn: Bool, for visible: [Item]) {
        let ids = visible.map(\.id)
        if isOn {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
    }

    func sort(using comparators: [KeyPathComparator<Item>]) {
        items.sort(using: comparators)
    }

    func scan(_ operation: @escaping @Sendable (ProgressReporter) async -> [Item]) async {
        phase = .scanning
        items = []
        selection = []
        progress = ScanProgress(message: localized("Preparing scan…"))
        let reporter = ProgressReporter { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.progress = update
            }
        }
        let found = await operation(reporter)
        guard !Task.isCancelled else {
            phase = .idle
            return
        }
        items = found
        phase = .loaded
    }

    func cancelScan() {
        if phase == .scanning {
            phase = .idle
        }
    }

    func reset() {
        items = []
        selection = []
        phase = .idle
    }

    var confirmationItems: [ConfirmationItem] {
        pendingRemoval.map {
            ConfirmationItem(name: $0.itemName, path: $0.itemURL.path, size: Formatting.bytes($0.itemSize))
        }
    }

    var pendingBytes: Int64 {
        pendingRemoval.reduce(0) { $0 + $1.itemSize }
    }

    func requestRemoval(_ requested: [Item]? = nil) {
        let targets = requested ?? selectedItems
        guard !targets.isEmpty, !isRemoving else { return }
        pendingRemoval = targets
        if CleanupOptions.requiresConfirmation {
            isConfirming = true
        } else {
            confirmRemoval()
        }
    }

    func cancelRemoval() {
        isConfirming = false
        pendingRemoval = []
    }

    func confirmRemoval() {
        isConfirming = false
        let targets = pendingRemoval
        pendingRemoval = []
        guard !targets.isEmpty else { return }
        let options = CleanupOptions.current
        let remover = self.remover
        isRemoving = true
        Task {
            let report = await remover(targets, options)
            self.apply(report)
        }
    }

    private func apply(_ report: RemovalReport) {
        let removed = Set(report.removedURLs.map(\.standardizedFileURL))
        items.removeAll { removed.contains($0.itemURL.standardizedFileURL) }
        let remainingIDs = Set(items.map(\.id))
        selection.formIntersection(remainingIDs)
        isRemoving = false
        lastResult = report.result
        showsResult = true
        if report.result.success {
            PreferencesManager.shared.playCompletionSound()
        }
    }
}

struct CleanupStartView: View {
    let title: String
    let systemImage: String
    let description: String
    var actionTitle: String = "Analisar"
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

struct CleanupProgressView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .frame(maxWidth: 320)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(progress.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            if let total = progress.total {
                Text("\(progress.completed) de \(total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Button("Cancelar", action: onCancel)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum CleanLayout {
    static let horizontalPadding: CGFloat = 16
    static let checkboxWidth: CGFloat = 20
    static let iconSize: CGFloat = 32
    static let rowSpacing: CGFloat = 12
    static let itemIndent: CGFloat = horizontalPadding + checkboxWidth + rowSpacing
    static let memberIndent: CGFloat = itemIndent + checkboxWidth + rowSpacing
}

struct CleanupItemLabel: View {
    let title: String
    let path: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .help(path)
    }
}

struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(Formatting.bytes(bytes))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

enum TriState {
    case off
    case mixed
    case on

    var symbol: String {
        switch self {
        case .off: return "square"
        case .mixed: return "minus.square.fill"
        case .on: return "checkmark.square.fill"
        }
    }
}

struct TriStateIndicator: View {
    let state: TriState
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .opacity(isEnabled ? 1 : 0.4)
            .frame(width: CleanLayout.checkboxWidth, height: CleanLayout.checkboxWidth)
            .accessibilityHidden(true)
    }
}

struct TriStateCheckbox: View {
    let state: TriState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TriStateIndicator(state: state)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(state == .on ? localized("Checked") : state == .mixed ? localized("Partial") : localized("Unchecked"))
    }
}

struct SelectionCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(localized("Select"), isOn: $isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
    }
}

struct RevealInFinderButton: View {
    let url: URL

    private var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(!exists)
        .opacity(exists ? 1.0 : 0.0)
        .help(exists ? localized("Reveal in Finder") : "")
        .accessibilityLabel(localized("Reveal in Finder"))
    }
}

extension View {
    func cleanupRemovalFlow<Item>(
        _ model: CleanupListModel<Item>,
        title: String,
        actionTitle: String
    ) -> some View {
        sheet(isPresented: Bindable(model).isConfirming) {
            ConfirmationModal(
                title: title,
                subtitle: "\(model.pendingRemoval.count) \(model.pendingRemoval.count == 1 ? localized("item") : localized("items")) · \(Formatting.bytes(model.pendingBytes))",
                confirmationItems: model.confirmationItems,
                confirmActionTitle: actionTitle,
                note: CleanupOptions.current.deletionMode.confirmationNote,
                onConfirm: { model.confirmRemoval() },
                onCancel: { model.cancelRemoval() }
            )
        }
        .alert(
            model.lastResult?.summaryTitle ?? localized("Done"),
            isPresented: Bindable(model).showsResult,
            presenting: model.lastResult
        ) { _ in
            Button(localized("OK")) {}
        } message: { result in
            Text(result.summaryMessage)
        }
    }
}
