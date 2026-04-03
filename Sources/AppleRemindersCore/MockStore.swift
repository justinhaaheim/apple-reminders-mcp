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

        // Load seed data if AR_MCP_MOCK_SEED is set (inline JSON or file path)
        if let seedValue = ProcessInfo.processInfo.environment["AR_MCP_MOCK_SEED"] {
            loadSeedData(seedValue)
        }
    }

    /// Load seed data to pre-populate the mock store.
    /// Accepts either inline JSON (starts with '{') or a file path.
    /// The JSON format is: { "lists": [...], "reminders": [...] }
    /// where lists match ReminderListOutput and reminders match ReminderOutput.
    private func loadSeedData(_ seedValue: String) {
        let data: Data
        let source: String

        if seedValue.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            // Inline JSON
            guard let jsonData = seedValue.data(using: .utf8) else {
                logError("Mock seed: invalid UTF-8 in inline JSON")
                return
            }
            data = jsonData
            source = "inline JSON"
        } else {
            // File path
            let expandedPath = NSString(string: seedValue).expandingTildeInPath
            guard let fileData = FileManager.default.contents(atPath: expandedPath) else {
                logError("Mock seed file not found: \(expandedPath)")
                return
            }
            data = fileData
            source = expandedPath
        }

        do {
            let seed = try JSONDecoder().decode(MockSeedData.self, from: data)

            // Add seed lists (replace default if seed specifies one)
            for seedList in seed.lists {
                if let existingIndex = calendars.firstIndex(where: { $0.id == seedList.id }) {
                    calendars[existingIndex] = MockCalendar(id: seedList.id, name: seedList.name)
                } else {
                    calendars.append(MockCalendar(id: seedList.id, name: seedList.name))
                }
                if seedList.isDefault {
                    defaultCalendarId = seedList.id
                }
            }

            // Add seed reminders
            for seedReminder in seed.reminders {
                let reminder = MockReminder(
                    id: seedReminder.id,
                    title: seedReminder.title,
                    calendarId: seedReminder.listId,
                    store: self
                )
                reminder.notes = seedReminder.notes
                reminder.priority = Priority.fromString(seedReminder.priority)?.internalValue ?? 0

                if let urlString = seedReminder.url, let url = URL(string: urlString) {
                    reminder.url = url
                }

                if seedReminder.isCompleted {
                    if let completionDateStr = seedReminder.completionDate,
                       let completionDate = Date.fromISO8601(completionDateStr) {
                        reminder.completionDate = completionDate
                    } else {
                        reminder.completionDate = Date()
                    }
                }

                if let dueDateStr = seedReminder.dueDate,
                   let dueDate = Date.fromISO8601(dueDateStr) {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: dueDate
                    )
                }

                reminders.append(reminder)
            }

            log("Loaded mock seed data: \(seed.lists.count) lists, \(seed.reminders.count) reminders from \(source)")
        } catch {
            logError("Failed to parse mock seed file: \(error.localizedDescription)")
        }
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
    public func createReminder(in calendar: ReminderCalendar) throws -> Reminder {
        let reminder = MockReminder(calendarId: calendar.id, store: self)
        return reminder
    }
}

// MARK: - Mock Seed Data

/// JSON structure for pre-populating the mock store via AR_MCP_MOCK_SEED.
struct MockSeedData: Codable {
    let lists: [ReminderListOutput]
    let reminders: [ReminderOutput]
}
