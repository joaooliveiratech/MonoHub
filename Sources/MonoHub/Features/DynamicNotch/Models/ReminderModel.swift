import Foundation
import Synchronization

nonisolated struct ReminderTask: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: Int

    init(
        id: String = UUID().uuidString,
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
    }

    private static let dueFormatter = Mutex(DateFormatter())

    var dueDateString: String? {
        guard let due = dueDate else { return nil }
        return Self.dueFormatter.withLock { formatter in
            if formatter.locale != Localization.locale {
                formatter.locale = Localization.locale
                formatter.dateStyle = .short
                formatter.timeStyle = .short
            }
            return formatter.string(from: due)
        }
    }
}
