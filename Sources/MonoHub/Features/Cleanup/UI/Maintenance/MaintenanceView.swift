import SwiftUI

struct MaintenanceView: View {
    @State private var tasks: [MaintenanceTask] = MaintenanceEngine.defaultTasks
    @State private var isRunningAll = false
    @State private var showsRunAllConfirmation = false
    @State private var filterText = ""

    private var categoryOrder: [String] {
        [localized("Network"), localized("Memory"), localized("Storage"), localized("Interface"), localized("System")]
    }

    init() {}

    private var visibleTasks: [MaintenanceTask] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    private var categories: [String] {
        let present = Set(visibleTasks.map(\.category))
        return categoryOrder.filter(present.contains) + present.subtracting(categoryOrder).sorted()
    }

    private var isAnyTaskRunning: Bool {
        isRunningAll || tasks.contains { $0.status == .running }
    }

    var body: some View {
        Form {
            ForEach(categories, id: \.self) { category in
                Section {
                    ForEach(visibleTasks.filter { $0.category == category }) { task in
                        MaintenanceTaskRow(task: task, isDisabled: isAnyTaskRunning) {
                            Task { await run(taskID: task.id) }
                        }
                    }
                } header: {
                    Text(category)
                } footer: {
                    if category == categories.last {
                        Text(localized("Tasks with a lock ask for the macOS administrator password. No routine deletes documents."))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsRunAllConfirmation = true
                } label: {
                    Label(localized("Run All"), systemImage: "play.fill")
                }
                .disabled(isAnyTaskRunning)
                .help(localized("Run all routines in sequence"))
            }
        }
        .searchable(text: $filterText, placement: .toolbar, prompt: localized("Filter options…"))
        .confirmationDialog(
            localized("Run all maintenance routines?"),
            isPresented: $showsRunAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Run All")) {
                Task { await runAll() }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("The %d routines will be executed in sequence. The Finder and Dock will restart, and macOS may prompt for your administrator password.", tasks.count))
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            tasks = MaintenanceEngine.defaultTasks
        }
    }

    private func run(taskID: String) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .running
        tasks[index].outputMessage = ""
        let outcome = await MaintenanceEngine.shared.executeTask(tasks[index], options: CleanupOptions.current)
        guard let current = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[current].status = outcome.success ? .completed : .failed
        tasks[current].outputMessage = outcome.message
    }

    private func runAll() async {
        isRunningAll = true
        defer { isRunningAll = false }
        for task in tasks {
            await run(taskID: task.id)
        }
        if tasks.allSatisfy({ $0.status == .completed }) {
            PreferencesManager.shared.playCompletionSound()
        }
    }
}

private struct MaintenanceTaskRow: View {
    let task: MaintenanceTask
    let isDisabled: Bool
    let onRun: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HubIcon(systemName: task.systemIcon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                    if task.requiresAdministrator {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(localized("Requires administrator password"))
                            .accessibilityLabel(localized("Requires administrator password"))
                    }
                }
                Text(task.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.outputMessage.isEmpty {
                    Text(task.outputMessage)
                        .font(.caption)
                        .foregroundStyle(task.status == .completed ? .green : .orange)
                }
            }
            .help(localized("When to use: %@", task.whenToUse))
            Spacer(minLength: 12)
            if task.status == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(localized("Run"), action: onRun)
                    .disabled(isDisabled)
            }
        }
    }

    private var tint: Color {
        switch task.category {
        case localized("Network"): return .blue
        case localized("Memory"): return .green
        case localized("Storage"): return .orange
        case localized("Interface"): return .purple
        case localized("System"): return .indigo
        default: return .gray
        }
    }
}
