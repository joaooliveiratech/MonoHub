import SwiftUI

struct SwitcherKeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .switcherSurfaceTile(cornerRadius: 5)
    }
}

struct SwitcherShortcutHint: View {
    let key: String
    let description: String

    init(key: String, description: String) {
        self.key = key
        self.description = description
    }

    init(_ item: ShortcutItem) {
        self.init(key: item.key, description: item.description)
    }

    var body: some View {
        HStack(spacing: 5) {
            SwitcherKeyCap(key)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(description)")
    }
}

struct SwitcherCloseButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SwitcherSheetHeader<Leading: View>: View {
    let title: String
    let subtitle: String?
    let closeHelp: String
    let onClose: () -> Void
    @ViewBuilder let leading: () -> Leading

    init(
        title: String,
        subtitle: String? = nil,
        closeHelp: String,
        onClose: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.closeHelp = closeHelp
        self.onClose = onClose
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 12) {
            leading()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            SwitcherCloseButton(help: closeHelp, action: onClose)
        }
    }
}
