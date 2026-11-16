import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    let isSearchMode: Bool
    let onEnter: () -> Void
    let onExit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if isSearchMode {
                TextField(localized("Search windows and applications"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onAppear { isFocused = true }

                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(localized("Clear search"))
                    .accessibilityLabel(localized("Clear search"))
                }

                Button(action: onExit) { SwitcherKeyCap("esc") }
                    .buttonStyle(.plain)
                    .help(localized("Exit search (Esc)"))
                    .accessibilityLabel(localized("Exit search"))
            } else {
                Text(localized("Search"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                SwitcherKeyCap("/")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: SwitcherMetrics.headerControlHeight)
        .frame(maxWidth: 340)
        .switcherFieldBackground(isFocused: isSearchMode)
        .contentShape(Capsule())
        .onTapGesture { if !isSearchMode { onEnter() } }
        .accessibilityElement(children: isSearchMode ? .contain : .combine)
        .accessibilityAddTraits(isSearchMode ? [] : [.isButton])
        .accessibilityLabel(isSearchMode ? localized("Search") : localized("Search windows"))
    }
}
