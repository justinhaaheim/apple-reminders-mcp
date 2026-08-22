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

    // MARK: - Seed Data API

    /// Inject seed data directly into the mock store via the _seed_mock_data MCP tool.
    /// Accepts lists and reminders arrays from the tool arguments.
    func seedData(from arguments: [String: AnyCodable]) throws {
        // Seed lists
        if let listsArray = arguments["lists"]?.value as? [[String: Any]] {
            for listDict in listsArray {
                guard let id = listDict["id"] as? String,
                      let name = listDict["name"] as? String else {
                    throw RemindersError("Seed list requires 'id' and 'name'")
                }
                let isDefault = listDict["isDefault"] as? Bool ?? false

                if let existingIndex = calendars.firstIndex(where: { $0.id == id }) {
                    calendars[existingIndex] = MockCalendar(id: id, name: name)
                } else {
                    calendars.append(MockCalendar(id: id, name: name))
                }
                if isDefault {
                    defaultCalendarId = id
                }
            }
        }

        // Seed reminders
        if let remindersArray = arguments["reminders"]?.value as? [[String: Any]] {
            for dict in remindersArray {
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String,
                      let listId = dict["listId"] as? String else {
                    throw RemindersError("Seed reminder requires 'id', 'title', and 'listId'")
                }

                let reminder = MockReminder(id: id, title: title, calendarId: listId, store: self)
                reminder.notes = dict["notes"] as? String
                if let priorityStr = dict["priority"] as? String {
                    reminder.priority = Priority.fromString(priorityStr)?.internalValue ?? 0
                }
                if let urlString = dict["url"] as? String, let url = URL(string: urlString) {
                    reminder.url = url
                }
                if let isCompleted = dict["isCompleted"] as? Bool, isCompleted {
                    reminder.completionDate = Date()
                }
                if let dueDateStr = dict["dueDate"] as? String,
                   let dueDate = Date.fromISO8601(dueDateStr) {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: dueDate
                    )
                }

                reminders.append(reminder)
            }
        }

        let listCount = (arguments["lists"]?.value as? [[String: Any]])?.count ?? 0
        let reminderCount = (arguments["reminders"]?.value as? [[String: Any]])?.count ?? 0
        log("Seeded mock store: \(listCount) lists, \(reminderCount) reminders")
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

    public func deleteCalendar(_ calendar: ReminderCalendar) throws {
        guard let index = calendars.firstIndex(where: { $0.id == calendar.id }) else {
            throw RemindersError("List not found")
        }
        calendars.remove(at: index)
        // Deleting a list also deletes every reminder it contains.
        reminders.removeAll { $0.calendarId == calendar.id }
        if defaultCalendarId == calendar.id {
            defaultCalendarId = nil
        }
    }

    public func fetchReminders(
        in calendars: [ReminderCalendar],
        status: ReminderStatus,
        dueDateStart: Date?,
        dueDateEnd: Date?
    ) async -> [Reminder] {
        let calendarIds = Set(calendars.map { $0.id })

        return reminders.filter { reminder in
            guard calendarIds.contains(reminder.calendarId) else { return false }

            switch status {
            case .completed:
                guard reminder.isCompleted else { return false }
            case .incomplete:
                guard !reminder.isCompleted else { return false }
            case .all:
                break
            }

            // Mirror EventKit's predicateForIncompleteReminders(withDueDateStarting:ending:)
            // semantics for parity. Only applied to incomplete reminders; otherwise the
            // RemindersManager post-filters dueFrom/dueTo.
            if status == .incomplete, dueDateStart != nil || dueDateEnd != nil {
                guard var components = reminder.dueDateComponents else { return false }
                if components.calendar == nil { components.calendar = Calendar.current }
                guard let dueDate = components.date else { return false }
                if let start = dueDateStart, dueDate < start { return false }
                if let end = dueDateEnd, dueDate > end { return false }
            }

            return true
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
    public func createReminder(in calendar: ReminderCalendar) throws -> Reminder {
        let reminder = MockReminder(calendarId: calendar.id, store: self)
        return reminder
    }
}
