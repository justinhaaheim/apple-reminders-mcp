import Foundation

// MARK: - Reminder Store Protocol

/// Protocol abstracting reminder storage operations.
/// Allows swapping between real EventKit and mock implementations.
protocol ReminderStore {
    func requestAccess() async throws -> Bool
    func getAllCalendars() -> [ReminderCalendar]
    func getDefaultCalendar() -> ReminderCalendar?
    func createCalendar(name: String) throws -> ReminderCalendar
    func createReminder(in calendar: ReminderCalendar) -> Reminder
    func fetchReminders(in calendars: [ReminderCalendar], status: ReminderStatus) async -> [Reminder]
    func getReminder(withId id: String) -> Reminder?
    func saveReminder(_ reminder: Reminder) throws
    func deleteReminder(_ reminder: Reminder) throws
}

/// Status filter for fetching reminders
enum ReminderStatus {
    case incomplete
    case completed
    case all
}

/// Protocol-agnostic calendar representation
protocol ReminderCalendar {
    var id: String { get }
    var name: String { get }
}

/// Protocol-agnostic reminder representation
protocol Reminder {
    var id: String { get }
    var title: String { get set }
    var notes: String? { get set }
    var calendarId: String { get set }
    var isCompleted: Bool { get }
    var priority: Int { get set }
    var dueDateComponents: DateComponents? { get set }
    var completionDate: Date? { get set }
    var creationDate: Date? { get }
    var lastModifiedDate: Date? { get }
    var url: URL? { get set }
    var isAllDay: Bool { get set }
    var alarms: [ReminderAlarm] { get set }
    var recurrenceRules: [ReminderRecurrenceRule] { get set }

    func getCalendarName(from store: ReminderStore) -> String
}

/// Alarm representation (absolute date or relative offset)
struct ReminderAlarm {
    /// Specific date/time for the alarm
    let absoluteDate: Date?
    /// Offset in seconds relative to the due date. Always stored as a negative value
    /// (e.g., -3600 = 1 hour before). Matches EventKit's EKAlarm.relativeOffset convention.
    let relativeOffset: TimeInterval?
}

/// Recurrence rule representation
struct ReminderRecurrenceRule {
    let frequency: RecurrenceFrequency
    let interval: Int
    let daysOfWeek: [Int]?       // 1=Sunday ... 7=Saturday
    let daysOfMonth: [Int]?      // 1-31, or negative (-1=last day, -2=second-to-last, etc.)
    let monthsOfYear: [Int]?     // 1-12
    let weekPosition: Int?       // -1=last, 1=first, 2=second, etc.
    let endDate: Date?
    let endCount: Int?
}

enum RecurrenceFrequency: String, Codable {
    case daily
    case weekly
    case monthly
    case yearly
}
