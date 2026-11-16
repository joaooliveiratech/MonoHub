import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingHUDPanel: NSPanel {
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

struct ScreenRecordingHUDView: View {
    let elapsedSeconds: Int
    let dimensions: CGSize
    @Binding var selectedFormat: ScreenRecordingFormat
    let isProcessing: Bool
    let onStop: () -> Void
    let onCancel: () -> Void

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text(ShotText.recordingProcessing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else {

                HStack(spacing: 7) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.red.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.4)
                        )

                    Text(formattedTime)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                Text("\(Int(dimensions.width)) × \(Int(dimensions.height))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 18)

                Picker("", selection: $selectedFormat) {
                    ForEach(ScreenRecordingFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)

                Divider()
                    .frame(height: 18)

                Button {
                    onStop()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(ShotText.recordingHUDStop)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
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
                .help(ShotText.recordingHUDCancel)
                .keyboardShortcut(.cancelAction)
            }
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
