import SwiftUI

struct SelectionControlBar: View {
    let totalCount: Int
    let selectedCount: Int
    let selectedBytes: Int64
    let actionTitle: String
    var actionSystemImage: String = "trash"
    var isBusy: Bool = false
    var busyMessage: String = localized("Removing…")
    var isActionEnabled: Bool = true
    let onToggleAll: (Bool) -> Void
    let onAction: () -> Void

    private var state: TriState {
        if selectedCount == 0 || totalCount == 0 { return .off }
        return selectedCount == totalCount ? .on : .mixed
    }

    private var summary: String {
        guard selectedCount > 0 else {
            return totalCount == 1 ? localized("1 item") : localized("%d items", totalCount)
        }
        let count = selectedCount == 1 ? localized("1 selected") : localized("%d selected", selectedCount)
        return selectedBytes > 0 ? "\(count) · \(Formatting.bytes(selectedBytes))" : count
    }

    var body: some View {
        HStack(spacing: CleanLayout.rowSpacing) {
            Button {
                onToggleAll(state != .on)
            } label: {
                HStack(spacing: CleanLayout.rowSpacing) {
                    TriStateIndicator(state: state)
                    Text(state == .on ? localized("Deselect all") : localized("Select all"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(totalCount == 0 || isBusy)

            Divider()
                .frame(height: 18)

            Text(summary)
                .monospacedDigit()
                .foregroundStyle(selectedCount > 0 ? .primary : .secondary)
                .contentTransition(.numericText())
                .lineLimit(1)

            Spacer(minLength: 12)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(busyMessage)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: onAction) {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0 || isBusy || !isActionEnabled)
        }
        .font(.callout)
        .padding(.horizontal, CleanLayout.horizontalPadding)
        .frame(height: 52)
        .hubFloatingBar()
        .animation(.snappy(duration: 0.2), value: selectedCount)
    }
}
