import Foundation
import AppKit
@preconcurrency import EventKit
import Observation

@Observable
@MainActor
final class RemindersManager {
    static let shared = RemindersManager()

    private(set) var tasks: [ReminderTask] = []
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var observerTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var fetchGeneration = 0
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var isRunning = false

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observerTokens.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RemindersManager.shared.scheduleFetch(debounce: .milliseconds(300))
            }
        })
        observerTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RemindersManager.shared.checkAuthorization()
            }
        })
        checkAuthorization(forceFetch: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        fetchTask?.cancel()
        fetchTask = nil
        fetchGeneration += 1
        eventStore = nil
        tasks = []
    }

    private var store: EKEventStore {
        if let eventStore {
            return eventStore
        }
        let created = EKEventStore()
        eventStore = created
        return created
    }

    func checkAuthorization(forceFetch: Bool = false) {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let changed = status != authorizationStatus
        if changed {
            authorizationStatus = status
        }
        guard isRunning else { return }
        if isAuthorized {
            if changed {
                eventStore = nil
            }
            if changed || forceFetch {
                scheduleFetch(debounce: .zero)
            }
        } else if !tasks.isEmpty {
            tasks = []
        }
    }

    func requestAccess() {
        let currentStatus = EKEventStore.authorizationStatus(for: .reminder)
        if currentStatus == .denied || currentStatus == .restricted {
            openSystemRemindersPrivacySettings()
            return
        }

        NSApp.activate()
        let wrapped = UncheckedEventStore(store: store)
        Task {
            let granted = (try? await wrapped.store.requestFullAccessToReminders()) ?? false
            self.eventStore = nil
            self.checkAuthorization(forceFetch: true)
            if !granted && !self.isAuthorized {
                self.openSystemRemindersPrivacySettings()
            }
        }
    }

    func openSystemRemindersPrivacySettings() {
        guard !AppInfo.isRunningTests else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func fetchReminders() {
        scheduleFetch(debounce: .zero)
    }

    private func scheduleFetch(debounce: Duration) {
        guard isRunning, isAuthorized else { return }
        fetchTask?.cancel()
        fetchGeneration += 1
        let generation = fetchGeneration
        let wrapped = UncheckedEventStore(store: store)
        fetchTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            let items = await Self.loadReminders(from: wrapped)
            guard let self, !Task.isCancelled, generation == self.fetchGeneration, self.isRunning else { return }
            if items != self.tasks {
                self.tasks = items
            }
        }
    }

    nonisolated private static func loadReminders(from wrapped: UncheckedEventStore) async -> [ReminderTask] {
        let predicate = wrapped.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            wrapped.store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).prefix(25).map { reminder in
                    ReminderTask(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? localized("Untitled Reminder"),
                        isCompleted: reminder.isCompleted,
                        dueDate: reminder.dueDateComponents?.date,
                        priority: reminder.priority
                    )
                }
                continuation.resume(returning: Array(items))
            }
        }
    }

    func toggleCompletion(for id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted.toggle()
        let completed = tasks[index].isCompleted

        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            tasks[index].isCompleted = !completed
        }
    }

    func addReminder(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isAuthorized else { return }

        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first
        guard reminder.calendar != nil else { return }

        do {
            try store.save(reminder, commit: true)
            scheduleFetch(debounce: .zero)
        } catch {
            return
        }
    }
}
