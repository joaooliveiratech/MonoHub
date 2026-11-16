import SwiftUI

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let pid: pid_t
    let perform: @MainActor () -> Void
}

struct ConfirmationOverlayView: View {
    let confirmation: PendingConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            RunningAppIconView(pid: confirmation.pid, size: 56)

            VStack(spacing: 6) {
                Text(confirmation.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(confirmation.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text(localized("Cancel")).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)

                Button(role: .destructive, action: onConfirm) {
                    Text(confirmation.confirmTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 300)
        .switcherGlassPanel(cornerRadius: 24)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(confirmation.title). \(confirmation.message)")
    }
}
