import SwiftUI

struct ConfirmationItem: Identifiable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let size: String

    init(id: UUID = UUID(), name: String, path: String, size: String) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
    }
}

struct ConfirmationModal: View {
    let title: String
    let subtitle: String
    let items: [ConfirmationItem]
    let confirmActionTitle: String
    let note: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        title: String,
        subtitle: String,
        confirmationItems: [ConfirmationItem],
        confirmActionTitle: String = localized("Remove"),
        note: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = confirmationItems
        self.confirmActionTitle = confirmActionTitle
        self.note = note
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    init(
        title: String,
        subtitle: String,
        items: [(name: String, path: String, size: String)],
        confirmActionTitle: String = localized("Remove"),
        note: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            confirmationItems: items.map { ConfirmationItem(name: $0.name, path: $0.path, size: $0.size) },
            confirmActionTitle: confirmActionTitle,
            note: note,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(items.count == 1 ? localized("1 item will be affected:") : localized("%d items will be affected:", items.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            itemsView

            if let note {
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(localized("Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmActionTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var itemsView: some View {
        if items.count == 1, let item = items.first {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red.opacity(0.85))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !item.size.isEmpty && item.size != "0 bytes" && item.size != "0 B" && item.size != "—" {
                            Text(item.size)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(item.size)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
