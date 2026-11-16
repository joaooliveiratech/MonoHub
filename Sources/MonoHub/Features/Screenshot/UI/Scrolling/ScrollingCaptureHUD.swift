import AppKit
import SwiftUI

@MainActor
final class ScrollingCaptureHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct ScrollingCaptureHUDView: View {
    let height: Int
    let frames: Int
    let isAutoScrolling: Bool
    let onToggleAutoScroll: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.square.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ShotText.scrollingHUDTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(ShotText.scrollingHUDMetrics(height: height, frames: frames))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(height: 18)

            Button {
                onToggleAutoScroll()
            } label: {
                Label(
                    ShotText.scrollingHUDAutoScroll,
                    systemImage: isAutoScrolling ? "pause.circle.fill" : "arrow.down.circle"
                )
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(isAutoScrolling ? .orange : .secondary.opacity(0.2))
            .controlSize(.small)

            Button {
                onFinish()
            } label: {
                Label(ShotText.scrollingHUDFinish, systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(ShotText.scrollingHUDCancel)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}
