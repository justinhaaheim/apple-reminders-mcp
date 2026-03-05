import Foundation

// MARK: - Mock Implementations

/// Mock calendar for testing
public class MockCalendar: ReminderCalendar {
    public let id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

/// Mock reminder for testing
public class MockReminder: Reminder {
    public let id: String
    public var title: String
    public var notes: String?
    public var calendarId: String
    public var priority: Int = 0
    public var dueDateComponents: DateComponents?
    public var completionDate: Date?
    public let creationDate: Date?
    public var lastModifiedDate: Date?
    public var url: URL?
    public var alarms: [ReminderAlarm] = []
    public var recurrenceRules: [ReminderRecurrenceRule] = []

    // Mirror EKReminderWrapper.isAllDay: infer from dueDateComponents and
    // strip/retain time components on set, so mock behavior matches real EventKit.
    // Heuristic limitations:
    // - A reminder at exactly midnight (hour=0) reports isAllDay=false (has time)
    // - A reminder with no due date returns false rather than nil
    public var isAllDay: Bool {
        get {
            guard let components = dueDateComponents else { return false }
            return components.hour == nil
        }
        set {
            guard var components = dueDateComponents else { return }
            if newValue {
                components.hour = nil
                components.minute = nil
                components.second = nil
            }
            dueDateComponents = components
        }
    }

    private weak var store: MockReminderStore?

    public var isCompleted: Bool {
        return completionDate != nil
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "",
        calendarId: String,
        store: MockReminderStore? = nil
    ) {
        self.id = id
        self.title = title
        self.calendarId = calendarId
        self.creationDate = Date()
        self.lastModifiedDate = Date()
        self.store = store
    }

    public func getCalendarName(from store: ReminderStore) -> String {
        guard let mockStore = store as? MockReminderStore else { return "" }
        return mockStore.calendars.first { $0.id == calendarId }?.name ?? ""
    }

    public func updateModificationDate() {
        lastModifiedDate = Date()
    }
}

/// In-memory mock reminder store for testing
public class MockReminderStore: ReminderStore {
    public var calendars: [MockCalendar] = []
    public var reminders: [MockReminder] = []
    public var defaultCalendarId: String?

    public init() {
        // Create a default list
        let defaultCalendar = MockCalendar(name: "Reminders")
        calendars.append(defaultCalendar)
        defaultCalendarId = defaultCalendar.id
    }

    public func requestAccess() async throws -> Bool {
        return true
    }

    public func getAllCalendars() -> [ReminderCalendar] {
        return calendars
    }

    public func getDefaultCalendar() -> ReminderCalendar? {
        return calendars.first { $0.id == defaultCalendarId }
    }

    public func createCalendar(name: String) throws -> ReminderCalendar {
        let calendar = MockCalendar(name: name)
        calendars.append(calendar)
        return calendar
    }

    public func fetchReminders(in calendars: [ReminderCalendar], status: ReminderStatus) async -> [Reminder] {
        let calendarIds = Set(calendars.map { $0.id })

        return reminders.filter { reminder in
            guard calendarIds.contains(reminder.calendarId) else { return false }

            switch status {
            case .completed:
                return reminder.isCompleted
            case .incomplete:
                return !reminder.isCompleted
            case .all:
                return true
            }
        }
    }

    public func getReminder(withId id: String) -> Reminder? {
        return reminders.first { $0.id == id }
    }

    public func saveReminder(_ reminder: Reminder) throws {
        guard let mockReminder = reminder as? MockReminder else {
            throw RemindersError("Invalid reminder type")
        }

        mockReminder.updateModificationDate()

        // Check if it's an update or new reminder
        if let index = reminders.firstIndex(where: { $0.id == mockReminder.id }) {
            reminders[index] = mockReminder
        } else {
            reminders.append(mockReminder)
        }
    }

    public func deleteReminder(_ reminder: Reminder) throws {
        guard let mockReminder = reminder as? MockReminder else {
            throw RemindersError("Invalid reminder type")
        }

        guard let index = reminders.firstIndex(where: { $0.id == mockReminder.id }) else {
            throw RemindersError("Reminder not found")
        }

        reminders.remove(at: index)
    }

    /// Create a new reminder in the specified calendar
    public func createReminder(in calendar: ReminderCalendar) -> Reminder {
        let reminder = MockReminder(calendarId: calendar.id, store: self)
        return reminder
    }
}
