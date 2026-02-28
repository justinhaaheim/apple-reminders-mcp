import Foundation

// MARK: - Mock Implementations

/// Mock calendar for testing
class MockCalendar: ReminderCalendar {
    let id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

/// Mock reminder for testing
class MockReminder: Reminder {
    let id: String
    var title: String
    var notes: String?
    var calendarId: String
    var priority: Int = 0
    var dueDateComponents: DateComponents?
    var completionDate: Date?
    let creationDate: Date?
    var lastModifiedDate: Date?
    var url: URL?
    var alarms: [ReminderAlarm] = []
    var recurrenceRules: [ReminderRecurrenceRule] = []

    // Mirror EKReminderWrapper.isAllDay: infer from dueDateComponents and
    // strip/retain time components on set, so mock behavior matches real EventKit.
    // Heuristic limitations:
    // - A reminder at exactly midnight (hour=0) reports isAllDay=false (has time)
    // - A reminder with no due date returns false rather than nil
    var isAllDay: Bool {
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

    var isCompleted: Bool {
        return completionDate != nil
    }

    init(
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

    func getCalendarName(from store: ReminderStore) -> String {
        guard let mockStore = store as? MockReminderStore else { return "" }
        return mockStore.calendars.first { $0.id == calendarId }?.name ?? ""
    }

    func updateModificationDate() {
        lastModifiedDate = Date()
    }
}

/// In-memory mock reminder store for testing
class MockReminderStore: ReminderStore {
    var calendars: [MockCalendar] = []
    var reminders: [MockReminder] = []
    var defaultCalendarId: String?

    init() {
        // Create a default list
        let defaultCalendar = MockCalendar(name: "Reminders")
        calendars.append(defaultCalendar)
        defaultCalendarId = defaultCalendar.id
    }

    func requestAccess() async throws -> Bool {
        return true
    }

    func getAllCalendars() -> [ReminderCalendar] {
        return calendars
    }

    func getDefaultCalendar() -> ReminderCalendar? {
        return calendars.first { $0.id == defaultCalendarId }
    }

    func createCalendar(name: String) throws -> ReminderCalendar {
        let calendar = MockCalendar(name: name)
        calendars.append(calendar)
        return calendar
    }

    func fetchReminders(in calendars: [ReminderCalendar], status: ReminderStatus) async -> [Reminder] {
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

    func getReminder(withId id: String) -> Reminder? {
        return reminders.first { $0.id == id }
    }

    func saveReminder(_ reminder: Reminder) throws {
        guard let mockReminder = reminder as? MockReminder else {
            throw MCPToolError("Invalid reminder type")
        }

        mockReminder.updateModificationDate()

        // Check if it's an update or new reminder
        if let index = reminders.firstIndex(where: { $0.id == mockReminder.id }) {
            reminders[index] = mockReminder
        } else {
            reminders.append(mockReminder)
        }
    }

    func deleteReminder(_ reminder: Reminder) throws {
        guard let mockReminder = reminder as? MockReminder else {
            throw MCPToolError("Invalid reminder type")
        }

        guard let index = reminders.firstIndex(where: { $0.id == mockReminder.id }) else {
            throw MCPToolError("Reminder not found")
        }

        reminders.remove(at: index)
    }

    /// Create a new reminder in the specified calendar
    func createReminder(in calendar: ReminderCalendar) -> Reminder {
        let reminder = MockReminder(calendarId: calendar.id, store: self)
        return reminder
    }
}
