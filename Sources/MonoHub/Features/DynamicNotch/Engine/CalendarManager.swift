import Foundation
import AppKit
@preconcurrency import EventKit
import Observation
import Synchronization

nonisolated struct UncheckedEventStore: @unchecked Sendable {
    let store: EKEventStore
}

@Observable
@MainActor
final class CalendarManager {
    static let shared = CalendarManager()

    private(set) var upcomingEvents: [CalendarEventItem] = []
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncedAt: Date?

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var observerTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var fetchGeneration = 0
    @ObservationIgnored private(set) var isRunning = false

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                CalendarManager.shared.scheduleFetch(debounce: .milliseconds(300))
            }
        })
        observerTokens.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                CalendarManager.shared.scheduleFetch(debounce: .zero)
            }
        })
        observerTokens.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                CalendarManager.shared.checkAuthorization()
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
        upcomingEvents = []
        isSyncing = false
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
        let status = EKEventStore.authorizationStatus(for: .event)
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
        } else if !upcomingEvents.isEmpty {
            upcomingEvents = []
        }
    }

    func requestAccess() {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        if currentStatus == .denied || currentStatus == .restricted {
            openSystemCalendarPrivacySettings()
            return
        }

        NSApp.activate()
        let wrapped = UncheckedEventStore(store: store)
        Task {
            let granted = (try? await wrapped.store.requestFullAccessToEvents()) ?? false
            self.eventStore = nil
            self.checkAuthorization(forceFetch: true)
            if !granted && !self.isAuthorized {
                self.openSystemCalendarPrivacySettings()
            }
        }
    }

    func openSystemCalendarPrivacySettings() {
        guard !AppInfo.isRunningTests else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func syncNow() {
        guard isRunning else { return }
        checkAuthorization()
        guard isAuthorized else {
            if authorizationStatus == .notDetermined {
                requestAccess()
            }
            return
        }
        isSyncing = true
        store.refreshSourcesIfNecessary()
        scheduleFetch(debounce: .milliseconds(350))
    }

    private func scheduleFetch(debounce: Duration) {
        guard isRunning, isAuthorized else {
            isSyncing = false
            return
        }
        fetchTask?.cancel()
        fetchGeneration += 1
        let generation = fetchGeneration
        let wrapped = UncheckedEventStore(store: store)
        fetchTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            let items = await Self.loadEvents(from: wrapped, now: Date())
            guard let self, !Task.isCancelled, generation == self.fetchGeneration, self.isRunning else { return }
            if items != self.upcomingEvents {
                self.upcomingEvents = items
            }
            self.lastSyncedAt = Date()
            self.isSyncing = false
        }
    }

    @concurrent
    nonisolated private static func loadEvents(from wrapped: UncheckedEventStore, now: Date) async -> [CalendarEventItem] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfLookahead = calendar.date(byAdding: .hour, value: 36, to: startOfToday) else { return [] }

        let predicate = wrapped.store.predicateForEvents(withStart: startOfToday, end: endOfLookahead, calendars: nil)
        let ekEvents = wrapped.store.events(matching: predicate).filter { $0.status != .canceled }

        let activeToday = ekEvents.filter { $0.startDate < endOfToday && $0.endDate > now }
        let targetEvents = activeToday.isEmpty ? ekEvents.filter { $0.endDate > now } : activeToday

        var seenIDs = Set<String>()
        return targetEvents
            .sorted { a, b in
                if a.isAllDay != b.isAllDay {
                    return !a.isAllDay && b.isAllDay
                }
                if a.startDate != b.startDate {
                    return a.startDate < b.startDate
                }
                return a.endDate < b.endDate
            }
            .compactMap { event in
                let uniqueKey = "\(event.eventIdentifier ?? event.calendarItemIdentifier)_\(Int(event.startDate.timeIntervalSince1970))"
                guard seenIDs.insert(uniqueKey).inserted else { return nil }
                let cleanTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarEventItem(
                    id: uniqueKey,
                    title: cleanTitle.isEmpty ? "Compromisso" : cleanTitle,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                    meetingURL: extractMeetingURL(url: event.url, location: event.location, notes: event.notes),
                    calendarTitle: event.calendar?.title
                )
            }
    }

    var nextUpcomingEvent: CalendarEventItem? {
        let now = Date()
        let activeItems = upcomingEvents.filter { $0.endDate > now }
        if let happeningNow = activeItems.first(where: { !$0.isAllDay && $0.isNow }) {
            return happeningNow
        }
        if let nextTimed = activeItems.first(where: { !$0.isAllDay }) {
            return nextTimed
        }
        return activeItems.first
    }

    var remainingEvents: [CalendarEventItem] {
        let now = Date()
        return upcomingEvents.filter { $0.endDate > now }
    }

    nonisolated static func extractMeetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeetingURL(url.absoluteString) || url.scheme?.lowercased().hasPrefix("http") == true {
            return url
        }
        for text in [location, notes].compactMap({ $0 }) {
            for detected in findAllURLs(in: text) where isMeetingURL(detected.absoluteString) {
                return detected
            }
        }
        return nil
    }

    nonisolated static func isMeetingURL(_ str: String) -> Bool {
        let lower = str.lowercased()
        return lower.contains("zoom.us/") ||
               lower.contains("meet.google.com/") ||
               lower.contains("teams.microsoft.com/") ||
               lower.contains("teams.live.com/") ||
               lower.contains("webex.com/") ||
               lower.contains("facetime.apple.com/") ||
               lower.contains("app.slack.com/huddle") ||
               lower.contains("meet.jit.si/") ||
               lower.contains("whereby.com/") ||
               lower.contains("around.co/")
    }

    nonisolated private static let linkDetector = Mutex<NSDataDetector?>(
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    )

    nonisolated private static func findAllURLs(in string: String) -> [URL] {
        guard !string.isEmpty else { return [] }
        return linkDetector.withLock { detector in
            guard let detector else { return [] }
            let matches = detector.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))
            return matches.compactMap { $0.url }
        }
    }
}
