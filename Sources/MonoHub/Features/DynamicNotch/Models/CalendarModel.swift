import Foundation
import Synchronization

nonisolated struct CalendarEventItem: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let meetingURL: URL?
    let calendarTitle: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        meetingURL: URL? = nil,
        calendarTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.meetingURL = meetingURL
        self.calendarTitle = calendarTitle
    }

    var isNow: Bool {
        guard !isAllDay else { return false }
        let now = Date()
        return now >= startDate && now <= endDate
    }

    func isActiveOrStartingSoon(withinMinutes minutes: Int) -> Bool {
        guard !isAllDay else { return false }
        let now = Date()
        guard endDate > now else { return false }
        if now >= startDate { return true }
        return startDate.timeIntervalSince(now) <= TimeInterval(max(0, minutes) * 60)
    }

    private static let timeFormatterMutex = Mutex(DateFormatter())

    private static func formatTimeRange(start: Date, end: Date, isAllDay: Bool) -> String {
        if isAllDay { return localized("All Day") }
        let cal = Calendar.current
        let prefix = cal.isDateInToday(start) ? "" : (cal.isDateInTomorrow(start) ? "\(localized("Tomorrow")) • " : "")
        let (s, e) = timeFormatterMutex.withLock { f in
            if f.locale != Localization.locale {
                f.locale = Localization.locale
                f.timeStyle = .short
            }
            return (f.string(from: start), f.string(from: end))
        }
        return "\(prefix)\(s) – \(e)"
    }

    var timeString: String {
        Self.formatTimeRange(start: startDate, end: endDate, isAllDay: isAllDay)
    }

    var localizedTimeString: String {
        timeString
    }

    var localizedRelativeString: String {
        if isAllDay { return localized("All Day") }
        let now = Date()
        let interval = startDate.timeIntervalSince(now)

        if interval <= 0 && now <= endDate {
            let remainingMin = max(1, Int(endDate.timeIntervalSince(now) / 60))
            return localized("Now • %d min left", remainingMin)
        }

        let minutes = max(1, Int(ceil(interval / 60)))
        if minutes < 60 {
            return localized("in %d min", minutes)
        } else {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return remMinutes > 0 ? localized("in %dh %dm", hours, remMinutes) : localized("in %dh", hours)
        }
    }

    var startRelativeString: String {
        localizedRelativeString
    }

    var shortIslandCountdown: String {
        if isNow { return localized("Now") }
        let minutes = max(1, Int(ceil(startDate.timeIntervalSinceNow / 60)))
        if minutes < 60 {
            return localized("in %dm", minutes)
        }
        return localized("in %dh", max(1, minutes / 60))
    }
}
