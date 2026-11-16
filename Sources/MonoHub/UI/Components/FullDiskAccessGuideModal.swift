import AppKit
import SwiftUI

struct FullDiskAccessGuideModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedPath = false
    private let permissions = PermissionsManager.shared

    var onPermissionGranted: (() -> Void)?

    private var steps: [(symbol: String, title: String, detail: String)] {
        [
            ("1.circle.fill", localized("Open System Settings"), localized("The button below opens Privacy & Security › Full Disk Access and reveals MonoHub in Finder.")),
            ("2.circle.fill", localized("Add MonoHub"), localized("Drag MonoHub from Finder into the list, or click + and choose the app.")),
            ("3.circle.fill", localized("Enable toggle"), localized("Turn on the toggle next to MonoHub. If prompted by macOS, choose Quit & Reopen."))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(localized("Full Disk Access")) {
                        if permissions.hasFullDiskAccess {
                            StatusBadge(localized("Granted"), icon: "checkmark.circle.fill", color: .green)
                        } else {
                            StatusBadge(localized("Not granted"), icon: "exclamationmark.triangle.fill", color: .orange)
                        }
                    }
                    Button(localized("Check Again")) {
                        permissions.refreshStatus()
                    }
                } header: {
                    Text(localized("Status"))
                } footer: {
                    Text(localized("Required to analyze and remove containers, Trash, and protected caches in ~/Library."))
                }

                Section(localized("How to grant")) {
                    ForEach(steps, id: \.symbol) { step in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                Text(step.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: step.symbol)
                                .foregroundStyle(.tint)
                        }
                    }
                }

                Section(localized("Application")) {
                    LabeledContent(localized("Path")) {
                        Text(permissions.appPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Button(copiedPath ? localized("Copied") : localized("Copy Path")) {
                        permissions.copyAppPathToClipboard()
                        copiedPath = true
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(localized("Close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(localized("Open System Settings")) {
                    permissions.openFullDiskAccessSettingsAndRevealApp()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 520)
        .task(id: copiedPath) {
            guard copiedPath else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedPath = false
        }
        .onChange(of: permissions.hasFullDiskAccess) { _, granted in
            if granted {
                onPermissionGranted?()
            }
        }
    }
}
