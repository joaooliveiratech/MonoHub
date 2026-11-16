import SwiftUI
import EventKit

struct RemindersView: View {
    private let remindersManager = RemindersManager.shared
    private let preferences = NotchPreferences.shared
    @State private var newReminderTitle: String = ""

    init() {}

    private var displayedTasks: [ReminderTask] {
        let filtered = remindersManager.tasks.filter { task in
            preferences.remindersShowCompleted || !task.isCompleted
        }
        if preferences.remindersSortByPriority {
            return filtered.sorted { a, b in
                if a.isCompleted != b.isCompleted {
                    return !a.isCompleted && b.isCompleted
                }
                let pa = a.priority == 0 ? 99 : a.priority
                let pb = b.priority == 0 ? 99 : b.priority
                if pa != pb { return pa < pb }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
        }
        return filtered
    }

    var body: some View {
        Group {
            if remindersManager.isAuthorized {
                authorizedView
            } else {
                permissionView
            }
        }
        .notchModule()
        .onAppear {
            remindersManager.checkAuthorization(forceFetch: true)
        }
    }

    private var authorizedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.blue)

                TextField(localized("New reminder"), text: $newReminderTitle)
                    .textFieldStyle(.plain)
                    .font(NotchTheme.body)
                    .foregroundStyle(NotchTheme.primaryText)
                    .onSubmit {
                        submitNewReminder()
                    }

                if !newReminderTitle.isEmpty {
                    Button {
                        submitNewReminder()
                    } label: {
                        Text(localized("Add"))
                    }
                    .buttonStyle(NotchPrimaryButtonStyle(tint: .blue, foreground: .white))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            if displayedTasks.isEmpty {
                NotchEmptyState(
                    systemImage: "checkmark.circle",
                    tint: .blue,
                    title: localized("No pending reminders"),
                    message: localized("All tasks are up to date.")
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayedTasks) { task in
                            HStack(spacing: 10) {
                                Button {
                                    NotchHaptics.tap()
                                    remindersManager.toggleCompletion(for: task.id)
                                } label: {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(task.isCompleted ? Color.blue : Color.white.opacity(0.45))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)

                                Text(task.title)
                                    .font(NotchTheme.body)
                                    .foregroundStyle(task.isCompleted ? NotchTheme.tertiaryText : NotchTheme.primaryText)
                                    .strikethrough(task.isCompleted, color: Color.white.opacity(0.35))
                                    .lineLimit(1)

                                Spacer()

                                if let due = task.dueDateString {
                                    Text(due)
                                        .font(NotchTheme.caption)
                                        .foregroundStyle(NotchTheme.tertiaryText)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func submitNewReminder() {
        guard !newReminderTitle.isEmpty else { return }
        NotchHaptics.tap()
        remindersManager.addReminder(title: newReminderTitle)
        newReminderTitle = ""
    }

    private var permissionView: some View {
        let isDenied = remindersManager.authorizationStatus == .denied || remindersManager.authorizationStatus == .restricted

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "checklist")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 2)

            Text(isDenied ? localized("Reminders access disabled") : localized("Allow Reminders access"))
                .font(NotchTheme.title)
                .foregroundStyle(NotchTheme.primaryText)

            Text(isDenied
                ? localized("Enable MonoHub in System Settings > Privacy & Security > Reminders to sync tasks in notch.")
                : localized("Allow MonoHub to view and complete tasks directly in the notch."))
                .font(NotchTheme.body)
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    remindersManager.requestAccess()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(isDenied ? localized("Open Settings") : localized("Allow access"))
                    }
                }
                .buttonStyle(NotchPrimaryButtonStyle(tint: .blue, foreground: .white))

                Button {
                    NotchHaptics.tap()
                    remindersManager.openSystemRemindersPrivacySettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                        Text(localized("Open System Settings"))
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
