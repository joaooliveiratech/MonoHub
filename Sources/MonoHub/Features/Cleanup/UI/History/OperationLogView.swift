import AppKit
import SwiftUI

struct OperationLogView: View {
    @State private var records: [OperationRecord] = []
    @State private var isLoading = true
    @State private var reloadToken = UUID()
    @State private var showsClearConfirmation = false
    @State private var sortOrder = [KeyPathComparator(\OperationRecord.date, order: .reverse)]

    init() {}

    var body: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([OperationLogger.shared.logFileURL])
                    } label: {
                        Label(localized("Reveal in Finder"), systemImage: "folder")
                    }
                    .help(localized("Reveal history file in Finder"))
                    .disabled(records.isEmpty)

                    Button {
                        reloadToken = UUID()
                    } label: {
                        Label(localized("Refresh"), systemImage: "arrow.clockwise")
                    }
                    .help(localized("Reload history"))

                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label(localized("Clear History"), systemImage: "trash")
                    }
                    .help(localized("Delete all local records"))
                    .disabled(records.isEmpty)
                }
            }
            .task(id: reloadToken) {
                isLoading = true
                var loaded = await Self.loadRecords()
                loaded.sort(using: sortOrder)
                records = loaded
                isLoading = false
            }
            .onChange(of: sortOrder) { _, newOrder in
                records.sort(using: newOrder)
            }
            .confirmationDialog(
                localized("Delete all local history?"),
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(localized("Delete History"), role: .destructive) {
                    Task {
                        await Self.clearRecords()
                        reloadToken = UUID()
                    }
                }
                Button(localized("Cancel"), role: .cancel) {}
            } message: {
                Text(localized("Records in ~/Library/Logs/MonoHub/operations.log will be deleted. Previously removed files are not affected."))
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && records.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty {
            ContentUnavailableView(
                localized("No operations recorded"),
                systemImage: "clock.arrow.circlepath",
                description: Text(localized("Cleanups, uninstalls, and maintenance routines appear here. History is kept only on this Mac."))
            )
        } else {
            Table(records, sortOrder: $sortOrder) {
                TableColumn(localized("Date"), value: \.date) { record in
                    Text(Formatting.date(record.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 130, ideal: 150)
                TableColumn(localized("Operation"), value: \.action) { record in
                    let localizedAction = Self.localizeAction(record.action)
                    let localizedDetails = Self.localizeDetails(record.details)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(localizedAction)
                            .lineLimit(1)
                        Text(localizedDetails)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .help(localizedDetails)
                }
                .width(min: 240, ideal: 420)
                TableColumn(localized("Items"), value: \.itemsCleaned) { record in
                    Text(record.itemsCleaned, format: .number)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 60)
                TableColumn(localized("Freed"), value: \.bytesFreed) { record in
                    SizeText(bytes: record.bytesFreed)
                }
                .width(min: 80, ideal: 90)
            }
        }
    }

    static func localizeAction(_ action: String) -> String {
        if action.hasPrefix("Desinstalação de App: ") {
            let app = String(action.dropFirst("Desinstalação de App: ".count))
            return localized("App Uninstallation: %@", app)
        }
        if action.hasPrefix("App Uninstallation: ") {
            let app = String(action.dropFirst("App Uninstallation: ".count))
            return localized("App Uninstallation: %@", app)
        }
        if action == "Limpeza de Resíduos Órfãos" || action == "Orphaned Remnants Clean" {
            return localized("Orphaned Remnants Clean")
        }
        if action == "Purga de Projetos de Desenvolvimento" || action == "Project Build Purge" {
            return localized("Project Build Purge")
        }
        if action == "Exclusão de Arquivos Grandes" || action == "Large File Deletion" {
            return localized("Large File Deletion")
        }
        if action == "Limpeza do Sistema" || action == "System Clean" {
            return localized("System Clean")
        }
        if action.hasPrefix("Otimização: ") {
            let task = String(action.dropFirst("Otimização: ".count))
            return localized("Optimization: %@", localized(task))
        }
        if action.hasPrefix("Optimization: ") {
            let task = String(action.dropFirst("Optimization: ".count))
            return localized("Optimization: %@", localized(task))
        }
        return localized(action)
    }

    static func localizeDetails(_ details: String) -> String {
        if details.hasPrefix("Rotina ") || details.hasPrefix("Routine ") {
            return details
                .replacingOccurrences(of: "Rotina ", with: "\(localized("Routine")) ")
                .replacingOccurrences(of: ": Concluído", with: ": \(localized("Done"))")
                .replacingOccurrences(of: ": Cancelado", with: ": \(localized("Cancelled"))")
                .replacingOccurrences(of: ": Caminho inválido", with: ": \(localized("Invalid path"))")
                .replacingOccurrences(of: ": Cache removido", with: ": \(localized("Cache removed"))")
                .replacingOccurrences(of: ": Nada para limpar", with: ": \(localized("Nothing to clean"))")
                .replacingOccurrences(of: ": Tarefa desconhecida", with: ": \(localized("Unknown task"))")
        }
        if let match = try? #/Removidos (\d+) itens de (.+)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            let target = String(match.2)
            return localized("Removed %d items from %@", count, target)
        }
        if let match = try? #/Removed (\d+) items from (.+)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            let target = String(match.2)
            return localized("Removed %d items from %@", count, target)
        }
        if let match = try? #/(?:Removidos|Removed) (\d+) (?:resíduos de apps inexistentes|remnants of uninstalled apps)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            return localized("Removed %d remnants of uninstalled apps", count)
        }
        if let match = try? #/(?:Removidos|Removed) (\d+) (?:diretórios de build|build directories)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            return localized("Removed %d build directories", count)
        }
        if let match = try? #/(?:Removidos|Removed) (\d+) (?:arquivos grandes|large files)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            return localized("Removed %d large files", count)
        }
        if let match = try? #/(?:Removidos|Removed) (\d+) (?:itens|items) \((.+)\)/#.wholeMatch(in: details) {
            let count = Int(match.1) ?? 0
            let cats = String(match.2)
            return localized("Removed %d items (%@)", count, cats)
        }
        return localized(details)
    }

    @concurrent
    nonisolated private static func loadRecords() async -> [OperationRecord] {
        OperationLogger.shared.fetchRecords()
    }

    @concurrent
    nonisolated private static func clearRecords() async {
        OperationLogger.shared.clearLogs()
    }
}
