import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ScreenshotShortcutRecordingSession {
    static let shared = ScreenshotShortcutRecordingSession()

    private(set) var activeRequest: CaptureRequest?
    private(set) var notice: String?

    @ObservationIgnored private var monitor: Any?

    private init() {}

    func toggle(_ request: CaptureRequest) {
        if activeRequest == request {
            cancel()
        } else {
            begin(request)
        }
    }

    func cancel() {
        guard activeRequest != nil else { return }
        activeRequest = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        ScreenshotHotkeyService.shared.resume()
    }

    func clearNotice() {
        notice = nil
    }

    private func begin(_ request: CaptureRequest) {
        cancel()
        notice = nil
        activeRequest = request
        ScreenshotHotkeyService.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.activeRequest != nil else { return event }
            self.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard let request = activeRequest else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])

        if flags.isEmpty && event.keyCode == ShotKeyCode.escape {
            cancel()
            return
        }

        let candidate = KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: KeyShortcut.carbonModifiers(from: flags))
        guard candidate.isValidGlobalShortcut else {
            notice = ShotText.shortcutNeedsModifier
            NSSound.beep()
            return
        }

        let preferences = ScreenshotPreferences.shared
        if let existing = preferences.request(using: candidate, excluding: request) {
            notice = "\(candidate.displayString) · \(existing.settingsTitle) — \(ShotText.shortcutInUse)"
            NSSound.beep()
            return
        }

        preferences.setShortcut(candidate, for: request)
        cancel()
    }
}

struct ScreenshotShortcutField: View {
    let request: CaptureRequest

    private var session: ScreenshotShortcutRecordingSession { .shared }
    private var preferences: ScreenshotPreferences { .shared }
    private var isRecording: Bool { session.activeRequest == request }
    private var isUnavailable: Bool { ScreenshotHotkeyService.shared.unavailableRequests.contains(request) && !isRecording }

    var body: some View {
        HStack(spacing: 6) {
            if isUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(ShotText.shortcutUnavailable)
            }
            Text(label)
                .font(.callout.monospaced().weight(isRecording ? .semibold : .regular))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: 112)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color(NSColor.controlBackgroundColor)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isRecording ? 1.5 : 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    session.toggle(request)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(request.settingsTitle)
        .accessibilityValue(preferences.shortcut(for: request).displayString)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            session.toggle(request)
        }
        .help(isRecording ? ShotText.recordingHelp : ShotText.recordHelp)
    }

    private var label: String {
        isRecording ? ShotText.pressKeysPrompt : preferences.shortcut(for: request).displayString
    }
}
