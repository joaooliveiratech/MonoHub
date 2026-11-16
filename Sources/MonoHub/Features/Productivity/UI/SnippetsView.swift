import SwiftUI
import AppKit

struct SnippetsView: View {
    @Bindable private var snippetManager = SnippetManager.shared
    @State private var searchQuery: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var editingSnippet: SnippetItem?
    private let permissions = PermissionsManager.shared

    init() {}

    private var filteredSnippets: [SnippetItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return snippetManager.snippets
        }
        return snippetManager.snippets.filter { snippet in
            snippet.keyword.lowercased().contains(query) ||
            snippet.label.lowercased().contains(query) ||
            snippet.content.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !permissions.hasAccessibility {
                    accessibilityWarningBanner
                }

                headerControlBar
                tokensGuideCard
                snippetsListCard
            }
            .padding(20)
        }
        .sheet(isPresented: $showingAddSheet) {
            SnippetEditSheet(snippet: nil) { newSnippet in
                snippetManager.addSnippet(newSnippet)
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditSheet(snippet: snippet) { updated in
                snippetManager.updateSnippet(updated)
            }
        }
    }

    private var accessibilityWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Accessibility Permission Required"))
                    .font(.headline)
                Text(localized("To replace inline abbreviations as you type in macOS, MonoHub needs Accessibility access."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(localized("Grant Access")) {
                permissions.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
        )
    }

    private var headerControlBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "character.cursor.ibeam")
                        .foregroundStyle(Color.indigo)
                    Text(localized("Fast Text Expansion (Snippets)"))
                        .font(.headline)
                }

                Text(localized("Type an abbreviation (e.g. !email, !pix, !shrug) and MonoHub replaces it inline instantly."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $snippetManager.isEnabled)
                .toggleStyle(.switch)

            Button {
                showingAddSheet = true
            } label: {
                Label(localized("New Snippet"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var tokensGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("Available Dynamic Variables"), systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                tokenChip(token: "{date}", description: "Data de hoje (ex: 23/10/2026)")
                tokenChip(token: "{time}", description: "Hora atual (ex: 09:30)")
                tokenChip(token: "{clipboard}", description: "Conteúdo copiado")
                tokenChip(token: "{uuid}", description: "UUID aleatório")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func tokenChip(token: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(token)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.indigo)
            Text(description)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.indigo.opacity(0.08)))
    }

    private var snippetsListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(localized("Search by shortcut or content…"), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Button(localized("Reset to Defaults")) {
                    snippetManager.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            if filteredSnippets.isEmpty {
                Text(localized("No snippets found."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredSnippets) { snippet in
                        snippetRow(snippet)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func snippetRow(_ snippet: SnippetItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { snippet.isEnabled },
                set: { _ in snippetManager.toggleSnippet(id: snippet.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text(snippet.keyword)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(Color.indigo))

            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.label)
                    .font(.system(size: 13, weight: .medium))

                Text(snippet.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                editingSnippet = snippet
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                snippetManager.removeSnippet(id: snippet.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .alternatingContentBackgroundColors[1]))
        )
    }
}

private struct SnippetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snippet: SnippetItem?
    let onSave: (SnippetItem) -> Void

    @State private var keyword: String = ""
    @State private var label: String = ""
    @State private var content: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snippet == nil ? localized("New Text Snippet") : localized("Edit Snippet"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 5) {
                Text(localized("Abbreviation / Keyword:"))
                    .font(.caption.weight(.medium))
                TextField("Ex: !email, !pix, !cnpj, !shrug", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(localized("Label / Description:"))
                    .font(.caption.weight(.medium))
                TextField("Ex: Meu E-mail Principal", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(localized("Expanded Content:"))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("Suporta {date}, {time}, {clipboard}, {uuid}")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $content)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }

            Spacer()

            HStack {
                Button(localized("Cancel")) {
                    dismiss()
                }
                Spacer()
                Button(localized("Save")) {
                    var cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanKeyword.hasPrefix("!") && !cleanKeyword.hasPrefix(":") && !cleanKeyword.hasPrefix("/") && !cleanKeyword.isEmpty {
                        cleanKeyword = "!" + cleanKeyword
                    }
                    let item = SnippetItem(
                        id: snippet?.id ?? UUID(),
                        keyword: cleanKeyword.isEmpty ? "!novo" : cleanKeyword,
                        content: content,
                        label: label.isEmpty ? cleanKeyword : label,
                        isEnabled: snippet?.isEnabled ?? true
                    )
                    onSave(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 380)
        .onAppear {
            if let s = snippet {
                keyword = s.keyword
                label = s.label
                content = s.content
            }
        }
    }
}
