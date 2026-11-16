import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class ShortcutRecordingSession {
    static let shared = ShortcutRecordingSession()

    private(set) var activeAction: WindowAction?
    private(set) var notice: String?

    @ObservationIgnored private var monitor: Any?

    private init() {}

    func toggle(_ action: WindowAction) {
        if activeAction == action {
            cancel()
        } else {
            begin(action)
        }
    }

    func cancel() {
        guard activeAction != nil else { return }
        activeAction = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        HotkeyManager.shared.resume()
    }

    func clearNotice() {
        notice = nil
    }

    func assign(_ shortcut: ShortcutKey?, to action: WindowAction) {
        let displaced = TilePreferencesManager.shared.setShortcut(shortcut, for: action)
        notice = displaced.map { localized("%@ was removed from “%@”.", shortcut?.displayString ?? "", $0.displayName) }
    }

    private func begin(_ action: WindowAction) {
        cancel()
        notice = nil
        activeAction = action
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.activeAction != nil else { return event }
            self.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard let action = activeAction else { return }
        let modifiers = ShortcutModifiers(nsEventModifiers: event.modifierFlags)
        let keyCode = Int(event.keyCode)

        if modifiers.isEmpty && keyCode == kVK_Escape {
            cancel()
            return
        }
        if modifiers.isEmpty && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            cancel()
            assign(nil, to: action)
            return
        }

        let shortcut = ShortcutKey(keyCode: event.keyCode, modifiers: modifiers)
        guard shortcut.isValidGlobalShortcut else {
            notice = localized("Shortcuts require ⌘, ⌥, or ⌃.")
            NSSound.beep()
            return
        }
        cancel()
        assign(shortcut, to: action)
    }
}

struct ShortcutRecorderView: View {
    let action: WindowAction
    let shortcut: ShortcutKey?

    private var session: ShortcutRecordingSession { .shared }
    private var isRecording: Bool { session.activeAction == action }

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.callout.monospaced().weight(isRecording ? .semibold : .regular))
                .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if shortcut != nil && !isRecording && isHovered {
                Button {
                    session.assign(nil, to: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(localized("Clear Shortcut"))
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 136, height: 26)
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
            session.toggle(action)
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Shortcut for %@", action.displayName))
        .accessibilityValue(shortcut?.displayString ?? localized("None"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            session.toggle(action)
        }
        .help(isRecording ? localized("Press key combination. Press Esc to cancel or Delete to clear.") : localized("Click to record a new shortcut"))
    }

    private var label: String {
        if isRecording { return localized("Press Keys") }
        return shortcut?.displayString ?? localized("Record Shortcut")
    }
}
