import Foundation
#if canImport(EventKit)
import EventKit
#endif
import JMESPath

// MARK: - Test Mode Configuration

struct TestModeConfig {
    static let envVar = "AR_MCP_TEST_MODE"
    static let testListPrefix = "[AR-MCP TEST]"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }

    static func isTestList(_ name: String) -> Bool {
        name.hasPrefix(testListPrefix)
    }
}

// MARK: - Mock Mode Configuration

struct MockModeConfig {
    static let envVar = "AR_MCP_MOCK_MODE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }
}

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

#if canImport(EventKit)
// MARK: - EventKit Implementations

/// Wrapper around EKCalendar to conform to ReminderCalendar
class EKCalendarWrapper: ReminderCalendar {
    let calendar: EKCalendar

    init(_ calendar: EKCalendar) {
        self.calendar = calendar
    }

    var id: String { calendar.calendarIdentifier }
    var name: String { calendar.title }
}

/// Wrapper around EKReminder to conform to Reminder
class EKReminderWrapper: Reminder {
    let reminder: EKReminder
    private let eventStore: EKEventStore

    init(_ reminder: EKReminder, eventStore: EKEventStore) {
        self.reminder = reminder
        self.eventStore = eventStore
    }

    var id: String { reminder.calendarItemIdentifier }

    var title: String {
        get { reminder.title ?? "" }
        set { reminder.title = newValue }
    }

    var notes: String? {
        get { reminder.notes }
        set { reminder.notes = newValue }
    }

    var calendarId: String {
        get { reminder.calendar?.calendarIdentifier ?? "" }
        set {
            if let calendar = eventStore.calendar(withIdentifier: newValue) {
                reminder.calendar = calendar
            }
        }
    }

    var isCompleted: Bool { reminder.isCompleted }

    var priority: Int {
        get { reminder.priority }
        set { reminder.priority = newValue }
    }

    var dueDateComponents: DateComponents? {
        get { reminder.dueDateComponents }
        set { reminder.dueDateComponents = newValue }
    }

    var completionDate: Date? {
        get { reminder.completionDate }
        set { reminder.completionDate = newValue }
    }

    var creationDate: Date? { reminder.creationDate }
    var lastModifiedDate: Date? { reminder.lastModifiedDate }

    var url: URL? {
        get { reminder.url }
        set { reminder.url = newValue }
    }

    var isAllDay: Bool {
        get {
            // EKReminder doesn't have isAllDay (that's EKEvent-only).
            // Infer from dueDateComponents: if hour is set, it includes time (not all-day).
            // Heuristic limitations:
            // - A reminder at exactly midnight (hour=0) reports isAllDay=false (has time)
            // - A reminder with no due date returns false rather than nil
            guard let components = reminder.dueDateComponents else { return false }
            return components.hour == nil
        }
        set {
            // Modify dueDateComponents to strip or retain time components.
            guard var components = reminder.dueDateComponents else { return }
            if newValue {
                // All-day: remove time components
                components.hour = nil
                components.minute = nil
                components.second = nil
            }
            // If setting isAllDay=false, time components should already be present
            // from the date parsing; no action needed.
            reminder.dueDateComponents = components
        }
    }

    var alarms: [ReminderAlarm] {
        get {
            return (reminder.alarms ?? []).map { ekAlarm in
                ReminderAlarm(
                    absoluteDate: ekAlarm.absoluteDate,
                    relativeOffset: ekAlarm.absoluteDate == nil ? ekAlarm.relativeOffset : nil
                )
            }
        }
        set {
            reminder.alarms = newValue.map { alarm in
                if let absoluteDate = alarm.absoluteDate {
                    return EKAlarm(absoluteDate: absoluteDate)
                } else {
                    return EKAlarm(relativeOffset: alarm.relativeOffset ?? 0)
                }
            }
        }
    }

    var recurrenceRules: [ReminderRecurrenceRule] {
        get {
            return (reminder.recurrenceRules ?? []).map { rule in
                let frequency: RecurrenceFrequency
                switch rule.frequency {
                case .daily: frequency = .daily
                case .weekly: frequency = .weekly
                case .monthly: frequency = .monthly
                case .yearly: frequency = .yearly
                @unknown default: frequency = .daily
                }

                let daysOfWeek = rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue }
                let daysOfMonth = rule.daysOfTheMonth?.map { $0.intValue }
                let monthsOfYear = rule.monthsOfTheYear?.map { $0.intValue }
                // Known limitation: our model uses a single weekPosition for all days.
                // EventKit stores a weekNumber per EKRecurrenceDayOfWeek, so rules with
                // different week numbers per day (e.g. "2nd Monday AND 3rd Wednesday")
                // will lose that per-day data on round-trip.
                let weekPosition = rule.daysOfTheWeek?.first?.weekNumber
                let endDate = rule.recurrenceEnd?.endDate
                let endCount = rule.recurrenceEnd?.occurrenceCount

                return ReminderRecurrenceRule(
                    frequency: frequency,
                    interval: rule.interval,
                    daysOfWeek: daysOfWeek,
                    daysOfMonth: daysOfMonth,
                    monthsOfYear: monthsOfYear,
                    weekPosition: weekPosition != 0 ? weekPosition : nil,
                    endDate: endDate,
                    endCount: endCount != 0 ? endCount : nil
                )
            }
        }
        set {
            // Remove existing rules first
            if let existingRules = reminder.recurrenceRules {
                for rule in existingRules {
                    reminder.removeRecurrenceRule(rule)
                }
            }

            for rule in newValue {
                let ekFrequency: EKRecurrenceFrequency
                switch rule.frequency {
                case .daily: ekFrequency = .daily
                case .weekly: ekFrequency = .weekly
                case .monthly: ekFrequency = .monthly
                case .yearly: ekFrequency = .yearly
                }

                var daysOfWeek: [EKRecurrenceDayOfWeek]? = nil
                if let days = rule.daysOfWeek {
                    let position = rule.weekPosition ?? 0
                    daysOfWeek = days.compactMap { dayNum in
                        guard let weekday = EKWeekday(rawValue: dayNum) else { return nil }
                        if position != 0 {
                            return EKRecurrenceDayOfWeek(weekday, weekNumber: position)
                        }
                        return EKRecurrenceDayOfWeek(weekday)
                    }
                }

                let daysOfMonth = rule.daysOfMonth?.map { NSNumber(value: $0) }
                let monthsOfYear = rule.monthsOfYear?.map { NSNumber(value: $0) }

                var recurrenceEnd: EKRecurrenceEnd? = nil
                if let endDate = rule.endDate {
                    recurrenceEnd = EKRecurrenceEnd(end: endDate)
                } else if let endCount = rule.endCount {
                    recurrenceEnd = EKRecurrenceEnd(occurrenceCount: endCount)
                }

                let ekRule = EKRecurrenceRule(
                    recurrenceWith: ekFrequency,
                    interval: rule.interval,
                    daysOfTheWeek: daysOfWeek,
                    daysOfTheMonth: daysOfMonth,
                    monthsOfTheYear: monthsOfYear,
                    weeksOfTheYear: nil,
                    daysOfTheYear: nil,
                    setPositions: nil,
                    end: recurrenceEnd
                )

                reminder.addRecurrenceRule(ekRule)
            }
        }
    }

    func getCalendarName(from store: ReminderStore) -> String {
        return reminder.calendar?.title ?? ""
    }
}

/// Real EventKit-based reminder store
class EKReminderStore: ReminderStore {
    private let eventStore = EKEventStore()

    func requestAccess() async throws -> Bool {
        return try await eventStore.requestFullAccessToReminders()
    }

    func getAllCalendars() -> [ReminderCalendar] {
        return eventStore.calendars(for: .reminder).map { EKCalendarWrapper($0) }
    }

    func getDefaultCalendar() -> ReminderCalendar? {
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            return nil
        }
        return EKCalendarWrapper(calendar)
    }

    func createCalendar(name: String) throws -> ReminderCalendar {
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = name

        guard let source = findBestSource() else {
            throw MCPToolError("No available source for creating reminder list")
        }

        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return EKCalendarWrapper(calendar)
    }

    private func findBestSource() -> EKSource? {
        if let iCloudSource = eventStore.sources.first(where: { $0.title == "iCloud" }) {
            return iCloudSource
        }
        if let defaultSource = eventStore.defaultCalendarForNewReminders()?.source {
            return defaultSource
        }
        return eventStore.sources.first
    }

    func fetchReminders(in calendars: [ReminderCalendar], status: ReminderStatus) async -> [Reminder] {
        let ekCalendars = calendars.compactMap { wrapper -> EKCalendar? in
            guard let ekWrapper = wrapper as? EKCalendarWrapper else { return nil }
            return ekWrapper.calendar
        }

        return await withCheckedContinuation { continuation in
            let predicate: NSPredicate
            switch status {
            case .completed:
                predicate = eventStore.predicateForCompletedReminders(
                    withCompletionDateStarting: nil,
                    ending: nil,
                    calendars: ekCalendars
                )
            case .incomplete:
                predicate = eventStore.predicateForIncompleteReminders(
                    withDueDateStarting: nil,
                    ending: nil,
                    calendars: ekCalendars
                )
            case .all:
                predicate = eventStore.predicateForReminders(in: ekCalendars)
            }

            eventStore.fetchReminders(matching: predicate) { reminders in
                let wrapped = (reminders ?? []).map { EKReminderWrapper($0, eventStore: self.eventStore) }
                continuation.resume(returning: wrapped)
            }
        }
    }

    func getReminder(withId id: String) -> Reminder? {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            return nil
        }
        return EKReminderWrapper(ekReminder, eventStore: eventStore)
    }

    func saveReminder(_ reminder: Reminder) throws {
        guard let wrapper = reminder as? EKReminderWrapper else {
            throw MCPToolError("Invalid reminder type")
        }
        try eventStore.save(wrapper.reminder, commit: true)
    }

    func deleteReminder(_ reminder: Reminder) throws {
        guard let wrapper = reminder as? EKReminderWrapper else {
            throw MCPToolError("Invalid reminder type")
        }
        try eventStore.remove(wrapper.reminder, commit: true)
    }

    /// Create a new reminder in the specified calendar
    func createReminder(in calendar: ReminderCalendar) -> Reminder {
        guard let wrapper = calendar as? EKCalendarWrapper else {
            fatalError("Invalid calendar type")
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = wrapper.calendar
        return EKReminderWrapper(reminder, eventStore: eventStore)
    }
}
#endif

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

// MARK: - MCP Protocol Types

struct MCPRequest: Codable {
    let jsonrpc: String
    let id: RequestID
    let method: String
    let params: Params?

    enum RequestID: Codable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else {
                throw DecodingError.typeMismatch(RequestID.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "ID must be string or int"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string):
                try container.encode(string)
            case .int(let int):
                try container.encode(int)
            }
        }
    }

    struct Params: Codable {
        let name: String?
        let arguments: [String: AnyCodable]?
        let protocolVersion: String?
        let capabilities: [String: AnyCodable]?
        let clientInfo: ClientInfo?

        struct ClientInfo: Codable {
            let name: String
            let version: String
        }
    }
}

struct MCPResponse: Codable {
    var jsonrpc: String = "2.0"
    let id: MCPRequest.RequestID
    let result: Result?
    let error: MCPError?

    struct Result: Codable {
        let content: [Content]?
        let tools: [Tool]?
        let protocolVersion: String?
        let capabilities: Capabilities?
        let serverInfo: ServerInfo?
        let instructions: String?
        let isError: Bool?

        struct Content: Codable {
            let type: String
            let text: String
        }

        struct Capabilities: Codable {
            let tools: ToolsCapability?

            struct ToolsCapability: Codable {
                let listChanged: Bool?
            }
        }

        struct ServerInfo: Codable {
            let name: String
            let version: String
        }

        struct Tool: Codable {
            let name: String
            let description: String
            let inputSchema: JSONValue
        }
    }

    struct MCPError: Codable {
        let code: Int
        let message: String
    }
}

// MARK: - JSON Value Type for Complex Schemas

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - API Data Models

struct AlarmOutput: Codable {
    let type: String       // "absolute" or "relative"
    let date: String?      // ISO 8601 for absolute alarms
    let offset: Int?       // seconds before due date for relative alarms

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let date = date { dict["date"] = date }
        if let offset = offset { dict["offset"] = offset }
        return dict
    }
}

struct RecurrenceRuleOutput: Codable {
    let frequency: String  // "daily", "weekly", "monthly", "yearly"
    let interval: Int
    let daysOfWeek: [Int]?
    let daysOfMonth: [Int]?
    let monthsOfYear: [Int]?
    let weekPosition: Int?
    let endDate: String?
    let endCount: Int?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "frequency": frequency,
            "interval": interval
        ]
        if let daysOfWeek = daysOfWeek { dict["daysOfWeek"] = daysOfWeek }
        if let daysOfMonth = daysOfMonth { dict["daysOfMonth"] = daysOfMonth }
        if let monthsOfYear = monthsOfYear { dict["monthsOfYear"] = monthsOfYear }
        if let weekPosition = weekPosition { dict["weekPosition"] = weekPosition }
        if let endDate = endDate { dict["endDate"] = endDate }
        if let endCount = endCount { dict["endCount"] = endCount }
        return dict
    }
}

struct ReminderOutput: Codable {
    let id: String
    let title: String
    let notes: String?
    let listId: String
    let listName: String
    let isCompleted: Bool
    let priority: String  // "none", "low", "medium", "high"
    let dueDate: String?
    let dueDateIncludesTime: Bool?
    let completionDate: String?
    let createdDate: String
    let lastModifiedDate: String
    let url: String?
    let alarms: [AlarmOutput]?
    let recurrenceRules: [RecurrenceRuleOutput]?
}

struct ReminderListOutput: Codable {
    let id: String
    let name: String
    let isDefault: Bool
}

// MARK: - Export Types

struct ExportStats: Codable {
    let lists: Int
    let reminders: Int
    let completed: Int
    let incomplete: Int
}

struct ExportData: Codable {
    let exportVersion: String
    let exportDate: String
    let source: String
    let stats: ExportStats
    let lists: [ReminderListOutput]
    let reminders: [ReminderOutput]
}

struct ExportResult: Codable {
    let success: Bool
    let path: String
    let exportDate: String
    let stats: ExportStats
    let fileSizeBytes: Int
    let note: String
}

// MARK: - Input Types

struct ListSelector {
    let name: String?
    let id: String?
    let all: Bool?

    init(from dict: [String: Any]?) {
        guard let dict = dict else {
            self.name = nil
            self.id = nil
            self.all = nil
            return
        }
        self.name = dict["name"] as? String
        self.id = dict["id"] as? String
        self.all = dict["all"] as? Bool
    }

    var isEmpty: Bool {
        return name == nil && id == nil && all != true
    }
}

/// Represents a field that can be set to a value or explicitly cleared (null).
/// Used in update operations where omission means "don't change" vs null means "clear".
enum Clearable<T> {
    case value(T)
    case clear
}

struct AlarmInput {
    let type: String          // "absolute" or "relative"
    let date: String?         // ISO 8601 for absolute alarms
    let offset: Int?          // seconds before due date for relative alarms
}

struct RecurrenceRuleInput {
    let frequency: String     // "daily", "weekly", "monthly", "yearly"
    let interval: Int?        // default 1
    let daysOfWeek: [Int]?
    let daysOfMonth: [Int]?
    let monthsOfYear: [Int]?
    let weekPosition: Int?
    let endDate: String?
    let endCount: Int?
}

struct CreateReminderInput {
    let title: String
    let notes: String?
    let list: ListSelector?
    let dueDate: String?
    let priority: String?
    let url: String?
    let dueDateIncludesTime: Bool?
    let alarms: [AlarmInput]?
    let recurrenceRule: RecurrenceRuleInput?
}

struct UpdateReminderInput {
    let id: String
    let title: String?
    let notes: Clearable<String>?
    let list: ListSelector?
    let dueDate: Clearable<String>?
    let priority: String?
    let completed: Bool?
    let completedDate: Clearable<String>?
    let url: Clearable<String>?
    let dueDateIncludesTime: Bool?
    let alarms: Clearable<[AlarmInput]>?
    let recurrenceRule: Clearable<RecurrenceRuleInput>?
}

// MARK: - Priority Conversion

enum Priority: String, CaseIterable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var internalValue: Int {
        switch self {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    static func fromInternal(_ value: Int) -> Priority {
        switch value {
        case 0: return .none
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    static func fromString(_ string: String) -> Priority? {
        return Priority(rawValue: string.lowercased())
    }
}

// MARK: - Date Formatting

extension Date {
    func toISO8601WithTimezone() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }

    static func fromISO8601(_ string: String) -> Date? {
        // Try with timezone offset first
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        if let date = formatter.date(from: string) {
            return date
        }

        // Try ISO8601 standard format
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: string) {
            return date
        }

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: string) {
            return date
        }

        // Try date-only format
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = TimeZone.current
        return dateOnly.date(from: string)
    }
}

// MARK: - Validation Error

struct MCPToolError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        return message
    }
}

// MARK: - Reminders Manager

class RemindersManager {
    private let store: ReminderStore
    private var hasAccess = false

    init(store: ReminderStore) {
        self.store = store
    }

    // MARK: - Access

    func requestAccess() async throws {
        hasAccess = try await store.requestAccess()
        if !hasAccess {
            throw MCPToolError("Access to Reminders denied")
        }
    }

    // MARK: - List Operations

    func getAllLists() -> [ReminderListOutput] {
        let calendars = store.getAllCalendars()
        let defaultCalendar = store.getDefaultCalendar()

        return calendars.map { calendar in
            ReminderListOutput(
                id: calendar.id,
                name: calendar.name,
                isDefault: calendar.id == defaultCalendar?.id
            )
        }
    }

    func resolveList(_ selector: ListSelector?) throws -> [ReminderCalendar] {
        let allCalendars = store.getAllCalendars()

        guard let selector = selector, !selector.isEmpty else {
            // No selector → default list
            guard let defaultCalendar = store.getDefaultCalendar() else {
                throw MCPToolError("No default list found")
            }
            return [defaultCalendar]
        }

        // Validate exactly one key is set
        let setCount = [selector.id != nil, selector.name != nil, selector.all == true].filter { $0 }.count
        if setCount != 1 {
            throw MCPToolError("List selector must specify exactly one of: 'id', 'name', or 'all'")
        }

        if selector.all == true {
            return allCalendars
        }

        if let id = selector.id {
            guard let match = allCalendars.first(where: { $0.id == id }) else {
                throw MCPToolError("No list found with ID: '\(id)'")
            }
            return [match]
        }

        if let name = selector.name {
            guard let match = allCalendars.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                let available = allCalendars.map { $0.name }.joined(separator: ", ")
                throw MCPToolError("No list found with name: '\(name)'. Available lists: \(available).")
            }
            return [match]
        }

        throw MCPToolError("Invalid list selector")
    }

    func resolveListForCreate(_ selector: ListSelector?) throws -> ReminderCalendar {
        guard let selector = selector, !selector.isEmpty else {
            // No selector → default list
            guard let defaultCalendar = store.getDefaultCalendar() else {
                throw MCPToolError("No default list found")
            }
            return defaultCalendar
        }

        // Validate: only name or id allowed (not all)
        if selector.all == true {
            throw MCPToolError("Cannot create reminder in 'all' lists. Specify a single list by name or ID.")
        }

        let setCount = [selector.id != nil, selector.name != nil].filter { $0 }.count
        if setCount != 1 {
            throw MCPToolError("List selector must specify exactly one of: 'id' or 'name'")
        }

        let allCalendars = store.getAllCalendars()

        if let id = selector.id {
            guard let match = allCalendars.first(where: { $0.id == id }) else {
                throw MCPToolError("No list found with ID: '\(id)'")
            }
            return match
        }

        if let name = selector.name {
            guard let match = allCalendars.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                let available = allCalendars.map { $0.name }.joined(separator: ", ")
                throw MCPToolError("No list found with name: '\(name)'. Available lists: \(available).")
            }
            return match
        }

        throw MCPToolError("Invalid list selector")
    }

    func createList(name: String) throws -> ReminderListOutput {
        // Test mode validation
        if TestModeConfig.isEnabled && !TestModeConfig.isTestList(name) {
            throw MCPToolError(
                "TEST MODE: Cannot create list '\(name)'. " +
                "List name must start with '\(TestModeConfig.testListPrefix)'"
            )
        }

        let calendar = try store.createCalendar(name: name)

        log("Created reminder list '\(name)' with ID: \(calendar.id)")
        return ReminderListOutput(
            id: calendar.id,
            name: calendar.name,
            isDefault: false
        )
    }

    // MARK: - Query Operations

    func queryReminders(
        list: ListSelector?,
        status: String?,
        sortBy: String?,
        query: String?,
        limit: Int?,
        searchText: String?,
        dateFrom: String?,
        dateTo: String?,
        outputDetail: String?
    ) async throws -> Any {
        let startTime = Date()
        log("Starting queryReminders")

        // 1. Resolve list(s)
        let calendars = try resolveList(list)
        log("Resolved \(calendars.count) calendar(s)")

        // 2. Fetch reminders with status filter
        let reminderStatus: ReminderStatus
        switch status ?? "incomplete" {
        case "completed":
            reminderStatus = .completed
        case "incomplete":
            reminderStatus = .incomplete
        default:
            reminderStatus = .all
        }

        var filteredReminders = await store.fetchReminders(in: calendars, status: reminderStatus)

        let fetchTime = Date().timeIntervalSince(startTime)
        log("Fetched \(filteredReminders.count) reminders in \(Int(fetchTime * 1000))ms")

        // 2b. Apply searchText filter (case-insensitive across title and notes)
        if let searchText = searchText, !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            filteredReminders = filteredReminders.filter { reminder in
                if reminder.title.lowercased().contains(lowercasedSearch) {
                    return true
                }
                if let notes = reminder.notes, notes.lowercased().contains(lowercasedSearch) {
                    return true
                }
                return false
            }
            log("searchText filter '\(searchText)' reduced to \(filteredReminders.count) reminders")
        }

        // 2c. Apply date range filter on raw Reminder objects (avoids Date→String→Date round-trip)
        if dateFrom != nil || dateTo != nil {
            let fromDate: Date? = dateFrom != nil ? Date.fromISO8601(dateFrom!) : nil
            let toDate: Date? = dateTo != nil ? Date.fromISO8601(dateTo!) : nil

            if dateFrom != nil && fromDate == nil {
                throw MCPToolError("Invalid dateFrom format: '\(dateFrom!)'. Expected ISO 8601.")
            }
            if dateTo != nil && toDate == nil {
                throw MCPToolError("Invalid dateTo format: '\(dateTo!)'. Expected ISO 8601.")
            }

            filteredReminders = filteredReminders.filter { reminder in
                // For completed reminders, filter by completionDate
                // For incomplete reminders, filter by dueDate from dueDateComponents
                let reminderDate: Date?
                if reminder.isCompleted {
                    reminderDate = reminder.completionDate
                } else {
                    var components = reminder.dueDateComponents
                    if components != nil && components!.calendar == nil {
                        components!.calendar = Calendar.current
                    }
                    reminderDate = components?.date
                }

                guard let date = reminderDate else {
                    return false  // No date = excluded from date range filter
                }

                if let from = fromDate, date < from {
                    return false
                }
                if let to = toDate, date > to {
                    return false
                }
                return true
            }
            log("Date range filter reduced to \(filteredReminders.count) reminders")
        }

        // Convert to output format
        var reminderOutputs = filteredReminders.map { convertToOutput($0) }

        // 3. Apply JMESPath if provided — always uses full fields, outputDetail is ignored
        if let jmesQuery = query, !jmesQuery.isEmpty {
            do {
                let result = try applyJMESPath(reminderOutputs, query: jmesQuery)
                // Apply limit after JMESPath
                let maxResults = min(limit ?? 50, 200)
                if let arrayResult = result as? [Any] {
                    let limited = Array(arrayResult.prefix(maxResults))
                    log("JMESPath returned \(arrayResult.count) items, limited to \(limited.count)")
                    return limited
                }
                return result
            } catch {
                throw MCPToolError("Invalid JMESPath expression: \(error.localizedDescription). Expression: '\(jmesQuery)'.")
            }
        }

        // 4. Apply sortBy (only if no JMESPath query)
        let sortOrder = sortBy ?? "newest"
        reminderOutputs = applySorting(reminderOutputs, sortBy: sortOrder)

        // 5. Apply limit
        let maxResults = min(limit ?? 50, 200)
        if reminderOutputs.count > maxResults {
            reminderOutputs = Array(reminderOutputs.prefix(maxResults))
        }

        let totalTime = Date().timeIntervalSince(startTime)
        log("Total query took \(Int(totalTime * 1000))ms, returning \(reminderOutputs.count) reminders")

        // 6. Apply outputDetail field filtering
        let detail = outputDetail ?? "compact"
        let isSingleList = list == nil || list?.all != true
        return formatReminders(reminderOutputs, outputDetail: detail, isSingleList: isSingleList, statusFilter: reminderStatus)
    }

    private func applyJMESPath(_ reminders: [ReminderOutput], query: String) throws -> Any {
        // Convert reminders to JSON data
        let jsonData = try JSONEncoder().encode(reminders)

        // Compile and run JMESPath expression
        let expression = try JMESExpression.compile(query)
        let result = try expression.search(json: jsonData)
        return result ?? []
    }

    // Field sets for each output detail level
    private static let minimalFields: Set<String> = ["id", "title", "listName", "isCompleted"]
    private static let compactFields: Set<String> = [
        "id", "title", "notes", "listName", "isCompleted",
        "dueDate", "priority", "createdDate", "lastModifiedDate"
    ]
    // "full" uses all fields — no filtering needed

    /// Converts ReminderOutput array to [[String: Any]] with field filtering based on outputDetail level.
    /// - For "full": all fields included, null values shown explicitly
    /// - For "compact"/"minimal": only the specified field subset, null values omitted,
    ///   and listName/isCompleted conditionally omitted based on query context
    private func formatReminders(
        _ reminders: [ReminderOutput],
        outputDetail: String,
        isSingleList: Bool,
        statusFilter: ReminderStatus
    ) -> [[String: Any]] {
        let allowedFields: Set<String>?
        let stripNulls: Bool

        switch outputDetail {
        case "minimal":
            allowedFields = Self.minimalFields
            stripNulls = true
        case "full":
            allowedFields = nil  // all fields
            stripNulls = false
        default:  // "compact" (default)
            allowedFields = Self.compactFields
            stripNulls = true
        }

        // Determine which context-dependent fields to omit
        let omitListName = isSingleList && outputDetail != "full"
        let omitIsCompleted = (statusFilter == .incomplete || statusFilter == .completed) && outputDetail != "full"

        return reminders.map { reminder in
            var dict = buildFullDict(reminder)

            // Filter to allowed fields if not "full"
            if let allowed = allowedFields {
                dict = dict.filter { allowed.contains($0.key) }
            }

            // Conditionally omit context-implied fields
            if omitListName {
                dict.removeValue(forKey: "listName")
            }
            if omitIsCompleted {
                dict.removeValue(forKey: "isCompleted")
            }

            // Strip null values for compact/minimal
            if stripNulls {
                dict = dict.filter { !($0.value is NSNull) }
            }

            return dict
        }
    }

    /// Builds a complete dictionary with ALL fields for a single reminder.
    /// Null optional values are represented as NSNull() so they can be
    /// selectively stripped or preserved depending on outputDetail level.
    private func buildFullDict(_ reminder: ReminderOutput) -> [String: Any] {
        var dict: [String: Any] = [
            "id": reminder.id,
            "title": reminder.title,
            "notes": reminder.notes as Any? ?? NSNull(),
            "listId": reminder.listId,
            "listName": reminder.listName,
            "isCompleted": reminder.isCompleted,
            "priority": reminder.priority,
            "dueDate": reminder.dueDate as Any? ?? NSNull(),
            "dueDateIncludesTime": reminder.dueDateIncludesTime as Any? ?? NSNull(),
            "completionDate": reminder.completionDate as Any? ?? NSNull(),
            "createdDate": reminder.createdDate,
            "lastModifiedDate": reminder.lastModifiedDate,
            "url": reminder.url as Any? ?? NSNull(),
        ]

        // Alarms: array if present, NSNull if not
        if let alarms = reminder.alarms {
            dict["alarms"] = alarms.map { $0.toDict() }
        } else {
            dict["alarms"] = NSNull()
        }

        // Recurrence rules: array if present, NSNull if not
        if let rules = reminder.recurrenceRules {
            dict["recurrenceRules"] = rules.map { $0.toDict() }
        } else {
            dict["recurrenceRules"] = NSNull()
        }

        return dict
    }

    private func applySorting(_ reminders: [ReminderOutput], sortBy: String) -> [ReminderOutput] {
        switch sortBy {
        case "oldest":
            return reminders.sorted { $0.createdDate < $1.createdDate }
        case "priority":
            return reminders.sorted { r1, r2 in
                let p1 = prioritySortOrder(r1.priority)
                let p2 = prioritySortOrder(r2.priority)
                return p1 < p2
            }
        case "dueDate":
            return reminders.sorted { r1, r2 in
                // Nulls last
                guard let d1 = r1.dueDate else { return false }
                guard let d2 = r2.dueDate else { return true }
                return d1 < d2
            }
        case "newest":
            fallthrough
        default:
            return reminders.sorted { $0.createdDate > $1.createdDate }
        }
    }

    private func prioritySortOrder(_ priority: String) -> Int {
        switch priority {
        case "high": return 0
        case "medium": return 1
        case "low": return 2
        default: return 3  // "none"
        }
    }

    private func convertToOutput(_ reminder: Reminder) -> ReminderOutput {
        let alarmOutputs: [AlarmOutput]? = reminder.alarms.isEmpty ? nil : reminder.alarms.map { alarm in
            if let absoluteDate = alarm.absoluteDate {
                return AlarmOutput(
                    type: "absolute",
                    date: absoluteDate.toISO8601WithTimezone(),
                    offset: nil
                )
            } else {
                return AlarmOutput(
                    type: "relative",
                    date: nil,
                    offset: Int(-(alarm.relativeOffset ?? 0))
                )
            }
        }

        let recurrenceOutputs: [RecurrenceRuleOutput]? = reminder.recurrenceRules.isEmpty ? nil : reminder.recurrenceRules.map { rule in
            RecurrenceRuleOutput(
                frequency: rule.frequency.rawValue,
                interval: rule.interval,
                daysOfWeek: rule.daysOfWeek,
                daysOfMonth: rule.daysOfMonth,
                monthsOfYear: rule.monthsOfYear,
                weekPosition: rule.weekPosition,
                endDate: rule.endDate?.toISO8601WithTimezone(),
                endCount: rule.endCount
            )
        }

        return ReminderOutput(
            id: reminder.id,
            title: reminder.title,
            notes: reminder.notes,
            listId: reminder.calendarId,
            listName: reminder.getCalendarName(from: store),
            isCompleted: reminder.isCompleted,
            priority: Priority.fromInternal(reminder.priority).rawValue,
            dueDate: {
                guard var components = reminder.dueDateComponents else { return nil }
                if components.calendar == nil { components.calendar = Calendar.current }
                return components.date?.toISO8601WithTimezone()
            }(),
            dueDateIncludesTime: reminder.dueDateComponents != nil ? !reminder.isAllDay : nil,
            completionDate: reminder.completionDate?.toISO8601WithTimezone(),
            createdDate: reminder.creationDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            lastModifiedDate: reminder.lastModifiedDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            url: reminder.url?.absoluteString,
            alarms: alarmOutputs,
            recurrenceRules: recurrenceOutputs
        )
    }

    // MARK: - Create Operations

    func createReminders(inputs: [CreateReminderInput]) -> (created: [ReminderOutput], failed: [(index: Int, error: String)]) {
        var created: [ReminderOutput] = []
        var failed: [(index: Int, error: String)] = []

        for (index, input) in inputs.enumerated() {
            do {
                let output = try createSingleReminder(input)
                created.append(output)
            } catch {
                failed.append((index: index, error: error.localizedDescription))
            }
        }

        return (created, failed)
    }

    private func createSingleReminder(_ input: CreateReminderInput) throws -> ReminderOutput {
        let calendar = try resolveListForCreate(input.list)

        // Test mode validation
        if TestModeConfig.isEnabled && !TestModeConfig.isTestList(calendar.name) {
            throw MCPToolError(
                "TEST MODE: Cannot create reminder in list '\(calendar.name)'. " +
                "Target list must start with '\(TestModeConfig.testListPrefix)'"
            )
        }

        // Create reminder via the protocol
        let reminder = store.createReminder(in: calendar)

        var mutableReminder = reminder
        mutableReminder.title = input.title

        if let notes = input.notes {
            mutableReminder.notes = notes
        }

        if let dueDateString = input.dueDate {
            if let date = Date.fromISO8601(dueDateString) {
                mutableReminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            } else {
                throw MCPToolError("Invalid date format: '\(dueDateString)'. Expected ISO 8601 format like '2024-01-15T10:00:00-05:00'.")
            }
        }

        if let priorityString = input.priority {
            guard let priority = Priority.fromString(priorityString) else {
                throw MCPToolError("Invalid priority: '\(priorityString)'. Must be one of: none, low, medium, high.")
            }
            mutableReminder.priority = priority.internalValue
        }

        if let urlString = input.url {
            guard let url = URL(string: urlString) else {
                throw MCPToolError("Invalid URL: '\(urlString)'")
            }
            mutableReminder.url = url
        }

        if let includesTime = input.dueDateIncludesTime {
            if mutableReminder.dueDateComponents == nil {
                throw MCPToolError("dueDateIncludesTime requires a dueDate to be set.")
            }
            mutableReminder.isAllDay = !includesTime
        }

        if let alarmInputs = input.alarms {
            mutableReminder.alarms = try alarmInputs.map { alarmInput in
                try parseAlarmInput(alarmInput)
            }
        }

        if let recurrenceInput = input.recurrenceRule {
            mutableReminder.recurrenceRules = [try parseRecurrenceInput(recurrenceInput)]
        }

        try store.saveReminder(mutableReminder)
        log("Created reminder '\(input.title)' in list '\(calendar.name)'")

        return convertToOutput(mutableReminder)
    }

    // MARK: - Update Operations

    func updateReminders(inputs: [UpdateReminderInput]) -> (updated: [ReminderOutput], failed: [(id: String, error: String)]) {
        var updated: [ReminderOutput] = []
        var failed: [(id: String, error: String)] = []

        for input in inputs {
            do {
                let output = try updateSingleReminder(input)
                updated.append(output)
            } catch {
                failed.append((id: input.id, error: error.localizedDescription))
            }
        }

        return (updated, failed)
    }

    private func updateSingleReminder(_ input: UpdateReminderInput) throws -> ReminderOutput {
        guard var reminder = store.getReminder(withId: input.id) else {
            throw MCPToolError("No reminder found with ID: '\(input.id)'")
        }

        let calendarName = reminder.getCalendarName(from: store)

        // Test mode validation
        if TestModeConfig.isEnabled && !TestModeConfig.isTestList(calendarName) {
            throw MCPToolError(
                "TEST MODE: Cannot modify reminder in list '\(calendarName)'. " +
                "Reminder must be in a list starting with '\(TestModeConfig.testListPrefix)'"
            )
        }

        // Update title
        if let title = input.title {
            reminder.title = title
        }

        // Update notes (can be cleared with null)
        if let notesValue = input.notes {
            switch notesValue {
            case .clear:
                reminder.notes = nil
            case .value(let notes):
                reminder.notes = notes
            }
        }

        // Move to different list
        if let listSelector = input.list, !listSelector.isEmpty {
            let newCalendar = try resolveListForCreate(listSelector)

            // Test mode validation for target list
            if TestModeConfig.isEnabled && !TestModeConfig.isTestList(newCalendar.name) {
                throw MCPToolError(
                    "TEST MODE: Cannot move reminder to list '\(newCalendar.name)'. " +
                    "Target list must start with '\(TestModeConfig.testListPrefix)'"
                )
            }

            reminder.calendarId = newCalendar.id
        }

        // Update due date (can be cleared with null)
        if let dueDateValue = input.dueDate {
            switch dueDateValue {
            case .clear:
                reminder.dueDateComponents = nil
            case .value(let dueDateString):
                guard let date = Date.fromISO8601(dueDateString) else {
                    throw MCPToolError("Invalid date format: '\(dueDateString)'. Expected ISO 8601 format like '2024-01-15T10:00:00-05:00'.")
                }
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            }
        }

        // Update priority
        if let priorityString = input.priority {
            guard let priority = Priority.fromString(priorityString) else {
                throw MCPToolError("Invalid priority: '\(priorityString)'. Must be one of: none, low, medium, high.")
            }
            reminder.priority = priority.internalValue
        }

        // Handle completion - completedDate takes precedence over completed
        if let completedDateValue = input.completedDate {
            switch completedDateValue {
            case .clear:
                reminder.completionDate = nil
            case .value(let completedDateString):
                guard let date = Date.fromISO8601(completedDateString) else {
                    throw MCPToolError("Invalid date format: '\(completedDateString)'. Expected ISO 8601 format like '2024-01-15T10:00:00-05:00'.")
                }
                reminder.completionDate = date
            }
        } else if let completed = input.completed {
            if completed {
                reminder.completionDate = Date()
            } else {
                reminder.completionDate = nil
            }
        }

        // Update URL (can be cleared with null)
        if let urlValue = input.url {
            switch urlValue {
            case .clear:
                reminder.url = nil
            case .value(let urlString):
                guard let url = URL(string: urlString) else {
                    throw MCPToolError("Invalid URL: '\(urlString)'")
                }
                reminder.url = url
            }
        }

        // Update dueDateIncludesTime
        if let includesTime = input.dueDateIncludesTime {
            if reminder.dueDateComponents == nil {
                throw MCPToolError("dueDateIncludesTime requires a dueDate to be set.")
            }
            reminder.isAllDay = !includesTime
        }

        // Update alarms (can be cleared with null)
        if let alarmsValue = input.alarms {
            switch alarmsValue {
            case .clear:
                reminder.alarms = []
            case .value(let alarmInputs):
                reminder.alarms = try alarmInputs.map { try parseAlarmInput($0) }
            }
        }

        // Update recurrence rule (can be cleared with null)
        if let ruleValue = input.recurrenceRule {
            switch ruleValue {
            case .clear:
                reminder.recurrenceRules = []
            case .value(let ruleInput):
                reminder.recurrenceRules = [try parseRecurrenceInput(ruleInput)]
            }
        }

        try store.saveReminder(reminder)
        log("Updated reminder '\(reminder.title)'")

        return convertToOutput(reminder)
    }

    // MARK: - Input Parsing Helpers

    private func parseAlarmInput(_ input: AlarmInput) throws -> ReminderAlarm {
        switch input.type {
        case "absolute":
            guard let dateString = input.date else {
                throw MCPToolError("Absolute alarm requires 'date' field")
            }
            guard let date = Date.fromISO8601(dateString) else {
                throw MCPToolError("Invalid alarm date format: '\(dateString)'. Expected ISO 8601.")
            }
            return ReminderAlarm(absoluteDate: date, relativeOffset: nil)
        case "relative":
            guard let offset = input.offset else {
                throw MCPToolError("Relative alarm requires 'offset' field (seconds before due date)")
            }
            if offset < 0 {
                throw MCPToolError("Alarm offset must be a positive number of seconds (e.g., 3600 = 1 hour before due date). Got \(offset).")
            }
            return ReminderAlarm(absoluteDate: nil, relativeOffset: TimeInterval(-offset))
        default:
            throw MCPToolError("Invalid alarm type: '\(input.type)'. Must be 'absolute' or 'relative'.")
        }
    }

    private func parseRecurrenceInput(_ input: RecurrenceRuleInput) throws -> ReminderRecurrenceRule {
        guard let frequency = RecurrenceFrequency(rawValue: input.frequency.lowercased()) else {
            throw MCPToolError("Invalid recurrence frequency: '\(input.frequency)'. Must be one of: daily, weekly, monthly, yearly.")
        }

        let interval = input.interval ?? 1
        if interval < 1 {
            throw MCPToolError("Recurrence interval must be at least 1")
        }

        if input.endDate != nil && input.endCount != nil {
            throw MCPToolError("Cannot specify both endDate and endCount in a recurrence rule. Use one or the other.")
        }

        if let position = input.weekPosition {
            let validRanges = (-4)...(-1)
            let validPositive = 1...5
            if position != 0 && !validRanges.contains(position) && !validPositive.contains(position) {
                throw MCPToolError("Invalid weekPosition: \(position). Must be 1-5 (first through fifth), -1 to -4 (last through fourth-to-last), or 0.")
            }
        }

        var endDate: Date? = nil
        if let endDateString = input.endDate {
            guard let date = Date.fromISO8601(endDateString) else {
                throw MCPToolError("Invalid recurrence end date: '\(endDateString)'. Expected ISO 8601.")
            }
            endDate = date
        }

        return ReminderRecurrenceRule(
            frequency: frequency,
            interval: interval,
            daysOfWeek: input.daysOfWeek,
            daysOfMonth: input.daysOfMonth,
            monthsOfYear: input.monthsOfYear,
            weekPosition: input.weekPosition,
            endDate: endDate,
            endCount: input.endCount
        )
    }

    // MARK: - Delete Operations

    func deleteReminders(ids: [String]) -> (deleted: [String], failed: [(id: String, error: String)]) {
        var deleted: [String] = []
        var failed: [(id: String, error: String)] = []

        for id in ids {
            do {
                try deleteSingleReminder(id: id)
                deleted.append(id)
            } catch {
                failed.append((id: id, error: error.localizedDescription))
            }
        }

        return (deleted, failed)
    }

    private func deleteSingleReminder(id: String) throws {
        guard let reminder = store.getReminder(withId: id) else {
            throw MCPToolError("No reminder found with ID: '\(id)'")
        }

        let calendarName = reminder.getCalendarName(from: store)

        // Test mode validation
        if TestModeConfig.isEnabled && !TestModeConfig.isTestList(calendarName) {
            throw MCPToolError(
                "TEST MODE: Cannot delete reminder in list '\(calendarName)'. " +
                "Reminder must be in a list starting with '\(TestModeConfig.testListPrefix)'"
            )
        }

        try store.deleteReminder(reminder)
        log("Deleted reminder '\(reminder.title)'")
    }

    // MARK: - Export Operations

    func exportReminders(
        path: String?,
        lists: [ListSelector]?,
        includeCompleted: Bool
    ) async throws -> ExportResult {
        // Generate timestamp for filename
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
        let exportDate = isoFormatter.string(from: now)

        // Generate filename-safe timestamp
        let fileFormatter = DateFormatter()
        fileFormatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let fileTimestamp = fileFormatter.string(from: now)

        // Determine output path
        let outputPath: String
        if let customPath = path {
            // Expand ~ to home directory
            outputPath = NSString(string: customPath).expandingTildeInPath
        } else {
            // Use temp directory with timestamped filename
            let tempDir = NSTemporaryDirectory()
            outputPath = (tempDir as NSString).appendingPathComponent("reminders-export-\(fileTimestamp).json")
        }

        // Determine which calendars to export
        let calendarsToExport: [ReminderCalendar]
        if let listSelectors = lists, !listSelectors.isEmpty {
            // Export specific lists
            var selectedCalendars: [ReminderCalendar] = []
            for selector in listSelectors {
                let calendars = try resolveList(selector)
                selectedCalendars.append(contentsOf: calendars)
            }
            calendarsToExport = selectedCalendars
        } else {
            // Export all lists
            calendarsToExport = store.getAllCalendars()
        }

        // Fetch reminders
        let status: ReminderStatus = includeCompleted ? .all : .incomplete
        let reminders = await store.fetchReminders(in: calendarsToExport, status: status)

        // Convert to output format
        let reminderOutputs = reminders.map { convertToOutput($0) }

        // Get list information
        let defaultCalendar = store.getDefaultCalendar()
        let listOutputs = calendarsToExport.map { calendar in
            ReminderListOutput(
                id: calendar.id,
                name: calendar.name,
                isDefault: calendar.id == defaultCalendar?.id
            )
        }

        // Calculate stats
        let completedCount = reminderOutputs.filter { $0.isCompleted }.count
        let incompleteCount = reminderOutputs.filter { !$0.isCompleted }.count
        let stats = ExportStats(
            lists: listOutputs.count,
            reminders: reminderOutputs.count,
            completed: completedCount,
            incomplete: incompleteCount
        )

        // Create export data
        let exportData = ExportData(
            exportVersion: "1.0",
            exportDate: exportDate,
            source: "apple-reminders-mcp",
            stats: stats,
            lists: listOutputs,
            reminders: reminderOutputs
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)

        // Write to file
        let fileURL = URL(fileURLWithPath: outputPath)

        // Create parent directory if needed
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        try jsonData.write(to: fileURL)
        log("Exported \(reminderOutputs.count) reminders to \(outputPath)")

        // Return result
        return ExportResult(
            success: true,
            path: outputPath,
            exportDate: exportDate,
            stats: stats,
            fileSizeBytes: jsonData.count,
            note: "File is in temp directory. Move it to a permanent location to keep it."
        )
    }
}

// MARK: - MCP Server

class MCPServer {
    private let remindersManager: RemindersManager

    init() {
        // Choose store based on mock mode
        let store: ReminderStore
        if MockModeConfig.isEnabled {
            store = MockReminderStore()
        } else {
            #if canImport(EventKit)
            store = EKReminderStore()
            #else
            // EventKit not available (Linux) — force mock mode
            store = MockReminderStore()
            #endif
        }
        self.remindersManager = RemindersManager(store: store)
    }

    func start() async {
        do {
            try await remindersManager.requestAccess()
            log("Successfully obtained access to Reminders")
        } catch {
            logError("Failed to get access to Reminders: \(error)")
            exit(1)
        }

        if MockModeConfig.isEnabled {
            log("MOCK MODE ENABLED - Using in-memory storage (no real reminders)")
        }

        if TestModeConfig.isEnabled {
            log("TEST MODE ENABLED - Write operations restricted to lists prefixed with '\(TestModeConfig.testListPrefix)'")
        }

        log("Apple Reminders MCP Server running on stdio")

        while let line = readLine() {
            await handleRequest(line)
        }
    }

    private func handleRequest(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        var requestId: MCPRequest.RequestID?
        if let partialRequest = try? JSONDecoder().decode(MCPRequest.self, from: data) {
            requestId = partialRequest.id
        }

        do {
            let request = try JSONDecoder().decode(MCPRequest.self, from: data)
            let response = try await processRequest(request)
            sendResponse(response)
        } catch {
            logError("Error processing request: \(error)")
            sendErrorResponse(id: requestId ?? .int(-1), code: -32603, message: error.localizedDescription)
        }
    }

    private func sendErrorResponse(id: MCPRequest.RequestID, code: Int, message: String) {
        let errorResponse = MCPResponse(
            id: id,
            result: nil,
            error: MCPResponse.MCPError(code: code, message: message)
        )
        sendResponse(errorResponse)
    }

    private func processRequest(_ request: MCPRequest) async throws -> MCPResponse {
        switch request.method {
        case "initialize":
            let instructions = """
            Apple Reminders MCP Server - Access Apple Reminders with 7 powerful tools.

            TOOLS:
            • query_reminders - Search and filter reminders (text search, date range, JMESPath)
            • get_lists - Get all reminder lists
            • create_list - Create a new list
            • create_reminders - Create reminders with alarms, recurrence, URLs
            • update_reminders - Update reminders (including mark complete/incomplete)
            • delete_reminders - Delete reminders
            • export_reminders - Export reminders to JSON file (for backup)

            QUICK START:
            1. Call query_reminders with {} to see incomplete reminders from default list
            2. Use get_lists to see all available lists
            3. Specify list by name: {"list": {"name": "Work"}}
            4. Specify list by ID: {"list": {"id": "x-apple-..."}}
            5. Search by text: {"searchText": "meeting"}
            6. Search all lists: {"list": {"all": true}}

            PRIORITY: Use "none", "low", "medium", or "high" (not numbers)
            DATES: ISO 8601 with timezone, e.g., "2024-01-15T10:00:00-05:00"
            ALARMS: [{"type": "relative", "offset": 3600}] (1 hour before)
            RECURRENCE: {"frequency": "weekly", "interval": 1}
            """

            return MCPResponse(
                id: request.id,
                result: MCPResponse.Result(
                    content: nil,
                    tools: nil,
                    protocolVersion: "2024-11-05",
                    capabilities: MCPResponse.Result.Capabilities(
                        tools: MCPResponse.Result.Capabilities.ToolsCapability(listChanged: false)
                    ),
                    serverInfo: MCPResponse.Result.ServerInfo(
                        name: "apple-reminders",
                        version: "2.0.0"
                    ),
                    instructions: instructions,
                    isError: nil
                ),
                error: nil
            )

        case "tools/list":
            return MCPResponse(
                id: request.id,
                result: MCPResponse.Result(
                    content: nil,
                    tools: getTools(),
                    protocolVersion: nil,
                    capabilities: nil,
                    serverInfo: nil,
                    instructions: nil,
                    isError: nil
                ),
                error: nil
            )

        case "tools/call":
            guard let params = request.params,
                  let toolName = params.name else {
                throw MCPToolError("Missing tool name")
            }

            do {
                let resultText = try await callTool(toolName, arguments: params.arguments ?? [:])
                return MCPResponse(
                    id: request.id,
                    result: MCPResponse.Result(
                        content: [MCPResponse.Result.Content(type: "text", text: resultText)],
                        tools: nil,
                        protocolVersion: nil,
                        capabilities: nil,
                        serverInfo: nil,
                        instructions: nil,
                        isError: nil
                    ),
                    error: nil
                )
            } catch {
                // Return tool errors with isError: true
                let errorMessage = error.localizedDescription
                return MCPResponse(
                    id: request.id,
                    result: MCPResponse.Result(
                        content: [MCPResponse.Result.Content(type: "text", text: errorMessage)],
                        tools: nil,
                        protocolVersion: nil,
                        capabilities: nil,
                        serverInfo: nil,
                        instructions: nil,
                        isError: true
                    ),
                    error: nil
                )
            }

        default:
            throw MCPToolError("Unknown method: \(request.method)")
        }
    }

    private func getTools() -> [MCPResponse.Result.Tool] {
        return [
            // query_reminders
            MCPResponse.Result.Tool(
                name: "query_reminders",
                description: """
                Query reminders from Apple Reminders.

                **Default behavior (no parameters needed):**
                - Searches DEFAULT LIST only
                - Returns INCOMPLETE reminders only
                - Sorted by NEWEST CREATED first
                - Limited to 50 results
                - Uses "compact" output (most useful fields, nulls omitted)

                **Parameters (all optional):**

                list — Which list to search. Omit for default list.
                  • {"name": "Work"} → by exact name (case-insensitive)
                  • {"id": "x-apple-..."} → by exact ID
                  • {"all": true} → all lists

                status — "incomplete" (default), "completed", or "all"

                searchText — Case-insensitive text search across title and notes

                dateFrom / dateTo — Date range filter (ISO 8601). For incomplete reminders filters by dueDate, for completed by completionDate.

                sortBy — "newest" (default), "oldest", "priority", "dueDate"

                query — JMESPath expression for advanced filtering (overrides sortBy and outputDetail — always uses full fields as input)

                outputDetail — Controls which fields are returned:
                  • "minimal" — id, title only (plus listName if searching all lists, isCompleted if status is "all")
                  • "compact" (default) — id, title, notes, dueDate, priority, createdDate, lastModifiedDate (plus listName/isCompleted when contextually useful). Null fields omitted.
                  • "full" — All fields always included, null values shown explicitly

                limit — Max results (default 50, max 200)

                **Examples:**

                Recent incomplete from default list:
                  {}

                From specific list:
                  {"list": {"name": "Work"}}

                All lists, completed:
                  {"list": {"all": true}, "status": "completed"}

                Search by text:
                  {"searchText": "meeting"}

                Due this week:
                  {"dateFrom": "2024-01-15T00:00:00-05:00", "dateTo": "2024-01-21T23:59:59-05:00"}

                Full detail for debugging:
                  {"outputDetail": "full"}

                Minimal for quick overview:
                  {"outputDetail": "minimal"}

                High priority only:
                  {"query": "[?priority == 'high']"}

                Created today or later (via JMESPath):
                  {"query": "[?createdDate >= '2024-01-15']"}

                Modified in the last week (via JMESPath):
                  {"query": "[?lastModifiedDate >= '2024-01-08']"}

                **Reminder fields available in JMESPath (always full):**
                - id, title, notes, listId, listName, isCompleted
                - priority (string: "none", "low", "medium", "high")
                - dueDate, dueDateIncludesTime, completionDate, createdDate, lastModifiedDate
                - url, alarms, recurrenceRules
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "list": .object([
                            "type": .string("object"),
                            "description": .string("Which list to search. Omit for default list."),
                            "properties": .object([
                                "name": .object(["type": .string("string"), "description": .string("List name (case-insensitive match)")]),
                                "id": .object(["type": .string("string"), "description": .string("Exact list ID")]),
                                "all": .object(["type": .string("boolean"), "description": .string("Set true to search all lists")])
                            ]),
                            "additionalProperties": .bool(false)
                        ]),
                        "status": .object([
                            "type": .string("string"),
                            "enum": .array([.string("incomplete"), .string("completed"), .string("all")]),
                            "default": .string("incomplete"),
                            "description": .string("Filter by completion status")
                        ]),
                        "searchText": .object([
                            "type": .string("string"),
                            "description": .string("Case-insensitive text search across reminder titles and notes")
                        ]),
                        "dateFrom": .object([
                            "type": .string("string"),
                            "description": .string("Start of date range (ISO 8601). Filters by dueDate for incomplete, completionDate for completed reminders.")
                        ]),
                        "dateTo": .object([
                            "type": .string("string"),
                            "description": .string("End of date range (ISO 8601). Filters by dueDate for incomplete, completionDate for completed reminders.")
                        ]),
                        "sortBy": .object([
                            "type": .string("string"),
                            "enum": .array([.string("newest"), .string("oldest"), .string("priority"), .string("dueDate")]),
                            "default": .string("newest"),
                            "description": .string("Sort order. Ignored if 'query' includes sorting.")
                        ]),
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("JMESPath expression for advanced filtering/projection. Applied after list, status, searchText, and date filters. When provided, outputDetail is ignored (always uses full fields as input).")
                        ]),
                        "outputDetail": .object([
                            "type": .string("string"),
                            "enum": .array([.string("minimal"), .string("compact"), .string("full")]),
                            "default": .string("compact"),
                            "description": .string("Controls which fields are returned. 'minimal': id, title. 'compact' (default): most useful fields, nulls omitted. 'full': all fields, nulls shown. Ignored when 'query' (JMESPath) is provided. listName and isCompleted are contextually omitted in minimal/compact when implied by query params.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "maximum": .int(200),
                            "default": .int(50),
                            "description": .string("Maximum results to return")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // get_lists
            MCPResponse.Result.Tool(
                name: "get_lists",
                description: """
                Get all available reminder lists.

                Returns list names, IDs, and which one is the default. Call this if you need to know what lists exist before querying reminders.

                **Parameters:** None

                **Example:**
                  {}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // create_list
            MCPResponse.Result.Tool(
                name: "create_list",
                description: """
                Create a new reminder list.

                **Parameters:**

                name (required) — Name for the new list

                **Example:**

                Create a "Groceries" list:
                  {"name": "Groceries"}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("name")]),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Name for the new list")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // create_reminders
            MCPResponse.Result.Tool(
                name: "create_reminders",
                description: """
                Create one or more reminders.

                **Parameters:**

                reminders — Array of reminder objects to create. Each object:
                  • title (required) — Reminder title
                  • notes — Body text
                  • list — Target list as {"name": "..."} or {"id": "..."}. Default list if omitted.
                  • dueDate — ISO 8601 datetime (e.g., "2024-01-15T10:00:00-05:00")
                  • dueDateIncludesTime — Whether the due date has a specific time (default true). Set false for all-day reminders.
                  • priority — "none", "low", "medium", or "high"
                  • url — URL to associate with the reminder
                  • alarms — Array of alarm objects: {"type": "relative", "offset": 3600} or {"type": "absolute", "date": "..."}
                  • recurrenceRule — Recurrence rule: {"frequency": "daily|weekly|monthly|yearly", "interval": 1, ...}

                **Examples:**

                Single reminder:
                  {"reminders": [{"title": "Buy milk"}]}

                With details:
                  {"reminders": [{"title": "Call dentist", "list": {"name": "Personal"}, "dueDate": "2024-01-20T09:00:00-05:00", "priority": "high"}]}

                With alarm (1 hour before):
                  {"reminders": [{"title": "Meeting", "dueDate": "2024-01-20T14:00:00-05:00", "alarms": [{"type": "relative", "offset": 3600}]}]}

                Weekly recurrence:
                  {"reminders": [{"title": "Team standup", "dueDate": "2024-01-20T09:00:00-05:00", "recurrenceRule": {"frequency": "weekly", "interval": 1, "daysOfWeek": [2, 3, 4, 5, 6]}}]}

                Batch create:
                  {"reminders": [
                    {"title": "Buy milk"},
                    {"title": "Buy eggs"},
                    {"title": "Buy bread", "priority": "low"}
                  ]}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("reminders")]),
                    "properties": .object([
                        "reminders": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("object"),
                                "required": .array([.string("title")]),
                                "properties": .object([
                                    "title": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder title")
                                    ]),
                                    "notes": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder notes/body text")
                                    ]),
                                    "list": .object([
                                        "type": .string("object"),
                                        "description": .string("Target list. Uses default list if omitted."),
                                        "properties": .object([
                                            "name": .object(["type": .string("string")]),
                                            "id": .object(["type": .string("string")])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ]),
                                    "dueDate": .object([
                                        "type": .string("string"),
                                        "description": .string("Due date in ISO 8601 format")
                                    ]),
                                    "dueDateIncludesTime": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Whether the due date includes a specific time. Set false for all-day reminders. Default: true.")
                                    ]),
                                    "priority": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("none"), .string("low"), .string("medium"), .string("high")]),
                                        "description": .string("Priority level")
                                    ]),
                                    "url": .object([
                                        "type": .string("string"),
                                        "description": .string("URL to associate with the reminder")
                                    ]),
                                    "alarms": .object([
                                        "type": .string("array"),
                                        "description": .string("Alarm notifications for the reminder"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "required": .array([.string("type")]),
                                            "properties": .object([
                                                "type": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([.string("relative"), .string("absolute")]),
                                                    "description": .string("Alarm type: 'relative' (offset from due date) or 'absolute' (specific date/time)")
                                                ]),
                                                "offset": .object([
                                                    "type": .string("integer"),
                                                    "description": .string("Seconds before due date (for relative alarms). E.g., 3600 = 1 hour before.")
                                                ]),
                                                "date": .object([
                                                    "type": .string("string"),
                                                    "description": .string("ISO 8601 date/time (for absolute alarms)")
                                                ])
                                            ]),
                                            "additionalProperties": .bool(false)
                                        ])
                                    ]),
                                    "recurrenceRule": .object([
                                        "type": .string("object"),
                                        "description": .string("Recurrence rule for repeating reminders"),
                                        "required": .array([.string("frequency")]),
                                        "properties": .object([
                                            "frequency": .object([
                                                "type": .string("string"),
                                                "enum": .array([.string("daily"), .string("weekly"), .string("monthly"), .string("yearly")]),
                                                "description": .string("How often the reminder repeats")
                                            ]),
                                            "interval": .object([
                                                "type": .string("integer"),
                                                "minimum": .int(1),
                                                "default": .int(1),
                                                "description": .string("Repeat every N periods (e.g., 2 = every other week)")
                                            ]),
                                            "daysOfWeek": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(7)]),
                                                "description": .string("Days of week (1=Sunday, 2=Monday, ..., 7=Saturday). For weekly/monthly frequency.")
                                            ]),
                                            "daysOfMonth": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(-31), "maximum": .int(31)]),
                                                "description": .string("Days of month (1-31, or negative for last N days: -1=last day, -2=second-to-last, etc.). For monthly frequency.")
                                            ]),
                                            "monthsOfYear": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(12)]),
                                                "description": .string("Months of year (1-12). For yearly frequency.")
                                            ]),
                                            "weekPosition": .object([
                                                "type": .string("integer"),
                                                "description": .string("Week position within month: 1=first, 2=second, ..., -1=last. Used with daysOfWeek for 'first Monday' patterns.")
                                            ]),
                                            "endDate": .object([
                                                "type": .string("string"),
                                                "description": .string("ISO 8601 date when recurrence stops")
                                            ]),
                                            "endCount": .object([
                                                "type": .string("integer"),
                                                "minimum": .int(1),
                                                "description": .string("Number of occurrences before stopping")
                                            ])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // update_reminders
            MCPResponse.Result.Tool(
                name: "update_reminders",
                description: """
                Update one or more reminders. Only specified fields are changed.

                **Parameters:**

                reminders — Array of update objects. Each object:
                  • id (required) — Reminder ID to update
                  • title — New title
                  • notes — New notes (null to clear)
                  • list — Move to list as {"name": "..."} or {"id": "..."}
                  • dueDate — New due date as ISO 8601 (null to clear)
                  • dueDateIncludesTime — Whether due date has specific time (false = all-day)
                  • priority — "none", "low", "medium", or "high"
                  • completed — true to complete, false to uncomplete
                  • completedDate — ISO 8601 completion date (null to uncomplete)
                  • url — URL to associate (null to clear)
                  • alarms — Array of alarm objects (null to clear all alarms)
                  • recurrenceRule — Recurrence rule object (null to clear)

                **Examples:**

                Update title:
                  {"reminders": [{"id": "...", "title": "Buy oat milk"}]}

                Move to different list:
                  {"reminders": [{"id": "...", "list": {"name": "Groceries"}}]}

                Complete a reminder:
                  {"reminders": [{"id": "...", "completed": true}]}

                Uncomplete a reminder:
                  {"reminders": [{"id": "...", "completed": false}]}

                Complete with specific date:
                  {"reminders": [{"id": "...", "completedDate": "2024-01-15T10:00:00-05:00"}]}

                Clear due date:
                  {"reminders": [{"id": "...", "dueDate": null}]}

                Add alarm:
                  {"reminders": [{"id": "...", "alarms": [{"type": "relative", "offset": 1800}]}]}

                Set weekly recurrence:
                  {"reminders": [{"id": "...", "recurrenceRule": {"frequency": "weekly"}}]}

                Clear recurrence:
                  {"reminders": [{"id": "...", "recurrenceRule": null}]}

                Batch update (complete multiple):
                  {"reminders": [
                    {"id": "abc", "completed": true},
                    {"id": "def", "completed": true},
                    {"id": "ghi", "completed": true}
                  ]}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("reminders")]),
                    "properties": .object([
                        "reminders": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("object"),
                                "required": .array([.string("id")]),
                                "properties": .object([
                                    "id": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder ID to update")
                                    ]),
                                    "title": .object([
                                        "type": .string("string"),
                                        "description": .string("New title")
                                    ]),
                                    "notes": .object([
                                        "type": .string("string"),
                                        "description": .string("New notes. Set to null to clear.")
                                    ]),
                                    "list": .object([
                                        "type": .string("object"),
                                        "description": .string("Move to this list"),
                                        "properties": .object([
                                            "name": .object(["type": .string("string")]),
                                            "id": .object(["type": .string("string")])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ]),
                                    "dueDate": .object([
                                        "type": .string("string"),
                                        "description": .string("New due date in ISO 8601 format. Set to null to clear.")
                                    ]),
                                    "dueDateIncludesTime": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Whether the due date includes a specific time. Set false for all-day reminders.")
                                    ]),
                                    "priority": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("none"), .string("low"), .string("medium"), .string("high")]),
                                        "description": .string("New priority level")
                                    ]),
                                    "completed": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Set true to complete, false to uncomplete")
                                    ]),
                                    "completedDate": .object([
                                        "type": .string("string"),
                                        "description": .string("Completion date in ISO 8601 format. Set to null to uncomplete. Overrides 'completed' if both provided.")
                                    ]),
                                    "url": .object([
                                        "type": .string("string"),
                                        "description": .string("URL to associate with the reminder. Set to null to clear.")
                                    ]),
                                    "alarms": .object([
                                        "type": .string("array"),
                                        "description": .string("Alarm notifications. Set to null to clear all alarms."),
                                        "items": .object([
                                            "type": .string("object"),
                                            "required": .array([.string("type")]),
                                            "properties": .object([
                                                "type": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([.string("relative"), .string("absolute")]),
                                                    "description": .string("Alarm type")
                                                ]),
                                                "offset": .object([
                                                    "type": .string("integer"),
                                                    "description": .string("Seconds before due date (for relative alarms)")
                                                ]),
                                                "date": .object([
                                                    "type": .string("string"),
                                                    "description": .string("ISO 8601 date/time (for absolute alarms)")
                                                ])
                                            ]),
                                            "additionalProperties": .bool(false)
                                        ])
                                    ]),
                                    "recurrenceRule": .object([
                                        "type": .string("object"),
                                        "description": .string("Recurrence rule. Set to null to clear."),
                                        "required": .array([.string("frequency")]),
                                        "properties": .object([
                                            "frequency": .object([
                                                "type": .string("string"),
                                                "enum": .array([.string("daily"), .string("weekly"), .string("monthly"), .string("yearly")])
                                            ]),
                                            "interval": .object(["type": .string("integer"), "minimum": .int(1), "default": .int(1)]),
                                            "daysOfWeek": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "daysOfMonth": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "monthsOfYear": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "weekPosition": .object(["type": .string("integer")]),
                                            "endDate": .object(["type": .string("string")]),
                                            "endCount": .object(["type": .string("integer"), "minimum": .int(1)])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // delete_reminders
            MCPResponse.Result.Tool(
                name: "delete_reminders",
                description: """
                Delete one or more reminders permanently.

                **Parameters:**

                ids — Array of reminder IDs to delete

                **Examples:**

                Single delete:
                  {"ids": ["abc123"]}

                Batch delete:
                  {"ids": ["abc123", "def456", "ghi789"]}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("ids")]),
                    "properties": .object([
                        "ids": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("string")
                            ]),
                            "description": .string("Array of reminder IDs to delete")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // export_reminders
            MCPResponse.Result.Tool(
                name: "export_reminders",
                description: """
                Export reminders to a JSON file for backup or data portability.

                Writes all reminder data to a file without consuming LLM context tokens.
                Default location is system temp directory; move the file to keep it permanently.

                **Parameters (all optional):**

                path — Custom file path (default: temp directory with timestamp)
                  • Supports ~ for home directory
                  • Example: "~/Desktop/my-backup.json"

                lists — Array of lists to export (default: all lists)
                  • Each item: {"name": "..."} or {"id": "..."}
                  • Example: [{"name": "Work"}, {"name": "Personal"}]

                includeCompleted — Include completed reminders (default: true)

                **Examples:**

                Export everything to temp:
                  {}

                Export to Desktop:
                  {"path": "~/Desktop/reminders-backup.json"}

                Export only incomplete reminders:
                  {"includeCompleted": false}

                Export specific lists:
                  {"lists": [{"name": "Work"}, {"name": "Shopping"}]}

                **File format:**
                JSON with exportVersion, exportDate, stats, lists[], and reminders[].
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Custom file path. Supports ~ for home directory. Default: temp directory with timestamp.")
                        ]),
                        "lists": .object([
                            "type": .string("array"),
                            "description": .string("Lists to export. Default: all lists."),
                            "items": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "name": .object(["type": .string("string"), "description": .string("List name")]),
                                    "id": .object(["type": .string("string"), "description": .string("List ID")])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ]),
                        "includeCompleted": .object([
                            "type": .string("boolean"),
                            "default": .bool(true),
                            "description": .string("Include completed reminders in export")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            )
        ]
    }

    private func callTool(_ name: String, arguments: [String: AnyCodable]) async throws -> String {
        switch name {
        case "get_lists":
            let lists = remindersManager.getAllLists()
            return try toJSON(lists)

        case "create_list":
            guard let listName = arguments["name"]?.value as? String else {
                throw MCPToolError("Missing required field: 'name'")
            }
            let createdList = try remindersManager.createList(name: listName)
            return try toJSON(createdList)

        case "query_reminders":
            let listDict = arguments["list"]?.value as? [String: Any]
            let listSelector = ListSelector(from: listDict)
            let status = arguments["status"]?.value as? String
            let sortBy = arguments["sortBy"]?.value as? String
            let query = arguments["query"]?.value as? String
            let limit = arguments["limit"]?.value as? Int
            let searchText = arguments["searchText"]?.value as? String
            let dateFrom = arguments["dateFrom"]?.value as? String
            let dateTo = arguments["dateTo"]?.value as? String
            let outputDetail = arguments["outputDetail"]?.value as? String

            let result = try await remindersManager.queryReminders(
                list: listDict == nil ? nil : listSelector,
                status: status,
                sortBy: sortBy,
                query: query,
                limit: limit,
                searchText: searchText,
                dateFrom: dateFrom,
                dateTo: dateTo,
                outputDetail: outputDetail
            )

            return try toJSON(result)

        case "create_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw MCPToolError("Missing required field: 'reminders'")
            }

            var inputs: [CreateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let title = dict["title"] as? String else {
                    throw MCPToolError("Missing required field 'title' in reminder at index \(index)")
                }
                // Parse alarm inputs
                var alarmInputs: [AlarmInput]? = nil
                if let alarmsArray = dict["alarms"] as? [[String: Any]] {
                    alarmInputs = alarmsArray.map { alarmDict in
                        AlarmInput(
                            type: alarmDict["type"] as? String ?? "relative",
                            date: alarmDict["date"] as? String,
                            offset: alarmDict["offset"] as? Int
                        )
                    }
                }

                // Parse recurrence rule input
                var recurrenceInput: RecurrenceRuleInput? = nil
                if let ruleDict = dict["recurrenceRule"] as? [String: Any] {
                    recurrenceInput = RecurrenceRuleInput(
                        frequency: ruleDict["frequency"] as? String ?? "daily",
                        interval: ruleDict["interval"] as? Int,
                        daysOfWeek: ruleDict["daysOfWeek"] as? [Int],
                        daysOfMonth: ruleDict["daysOfMonth"] as? [Int],
                        monthsOfYear: ruleDict["monthsOfYear"] as? [Int],
                        weekPosition: ruleDict["weekPosition"] as? Int,
                        endDate: ruleDict["endDate"] as? String,
                        endCount: ruleDict["endCount"] as? Int
                    )
                }

                inputs.append(CreateReminderInput(
                    title: title,
                    notes: dict["notes"] as? String,
                    list: ListSelector(from: dict["list"] as? [String: Any]),
                    dueDate: dict["dueDate"] as? String,
                    priority: dict["priority"] as? String,
                    url: dict["url"] as? String,
                    dueDateIncludesTime: dict["dueDateIncludesTime"] as? Bool,
                    alarms: alarmInputs,
                    recurrenceRule: recurrenceInput
                ))
            }

            let (created, failed) = remindersManager.createReminders(inputs: inputs)

            if failed.isEmpty {
                return try toJSON(created)
            } else {
                let failedOutput = failed.map { ["index": $0.index, "error": $0.error] }
                let response: [String: Any] = ["created": encodableArray(created), "failed": failedOutput]
                return try toJSON(response)
            }

        case "update_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw MCPToolError("Missing required field: 'reminders'")
            }

            var inputs: [UpdateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let id = dict["id"] as? String else {
                    throw MCPToolError("Missing required field 'id' in reminder at index \(index)")
                }
                // Parse alarm inputs if present
                var alarmsClearable: Clearable<[AlarmInput]>? = nil
                if let alarmsRaw = dict["alarms"] {
                    if alarmsRaw is NSNull {
                        alarmsClearable = .clear
                    } else if let alarmsArray = alarmsRaw as? [[String: Any]] {
                        alarmsClearable = .value(alarmsArray.map { alarmDict in
                            AlarmInput(
                                type: alarmDict["type"] as? String ?? "relative",
                                date: alarmDict["date"] as? String,
                                offset: alarmDict["offset"] as? Int
                            )
                        })
                    }
                }

                // Parse recurrence rule if present
                var recurrenceClearable: Clearable<RecurrenceRuleInput>? = nil
                if let ruleRaw = dict["recurrenceRule"] {
                    if ruleRaw is NSNull {
                        recurrenceClearable = .clear
                    } else if let ruleDict = ruleRaw as? [String: Any] {
                        recurrenceClearable = .value(RecurrenceRuleInput(
                            frequency: ruleDict["frequency"] as? String ?? "daily",
                            interval: ruleDict["interval"] as? Int,
                            daysOfWeek: ruleDict["daysOfWeek"] as? [Int],
                            daysOfMonth: ruleDict["daysOfMonth"] as? [Int],
                            monthsOfYear: ruleDict["monthsOfYear"] as? [Int],
                            weekPosition: ruleDict["weekPosition"] as? Int,
                            endDate: ruleDict["endDate"] as? String,
                            endCount: ruleDict["endCount"] as? Int
                        ))
                    }
                }

                inputs.append(UpdateReminderInput(
                    id: id,
                    title: dict["title"] as? String,
                    notes: parseClearable(dict["notes"]),
                    list: ListSelector(from: dict["list"] as? [String: Any]),
                    dueDate: parseClearable(dict["dueDate"]),
                    priority: dict["priority"] as? String,
                    completed: dict["completed"] as? Bool,
                    completedDate: parseClearable(dict["completedDate"]),
                    url: parseClearable(dict["url"]),
                    dueDateIncludesTime: dict["dueDateIncludesTime"] as? Bool,
                    alarms: alarmsClearable,
                    recurrenceRule: recurrenceClearable
                ))
            }

            let (updated, failed) = remindersManager.updateReminders(inputs: inputs)

            if failed.isEmpty {
                return try toJSON(updated)
            } else {
                let failedOutput = failed.map { ["id": $0.id, "error": $0.error] }
                let response: [String: Any] = ["updated": encodableArray(updated), "failed": failedOutput]
                return try toJSON(response)
            }

        case "delete_reminders":
            guard let ids = arguments["ids"]?.value as? [String] else {
                throw MCPToolError("Missing required field: 'ids'")
            }

            let (deleted, failed) = remindersManager.deleteReminders(ids: ids)
            let failedOutput = failed.map { ["id": $0.id, "error": $0.error] }
            let response: [String: Any] = ["deleted": deleted, "failed": failedOutput]
            return try toJSON(response)

        case "export_reminders":
            let path = arguments["path"]?.value as? String
            let includeCompleted = arguments["includeCompleted"]?.value as? Bool ?? true

            // Parse lists array if provided
            var listSelectors: [ListSelector]? = nil
            if let listsArray = arguments["lists"]?.value as? [[String: Any]] {
                listSelectors = listsArray.map { ListSelector(from: $0) }
            }

            let result = try await remindersManager.exportReminders(
                path: path,
                lists: listSelectors,
                includeCompleted: includeCompleted
            )

            return try toJSON(result)

        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    /// Parses a JSON value into a Clearable: NSNull → .clear, castable T → .value(T), absent key → nil
    private func parseClearable<T>(_ raw: Any?) -> Clearable<T>? {
        guard let raw = raw else { return nil }
        if raw is NSNull { return .clear }
        if let value = raw as? T { return .value(value) }
        return nil
    }

    private func encodableArray(_ reminders: [ReminderOutput]) -> [[String: Any]] {
        return reminders.map { reminder in
            var dict: [String: Any] = [
                "id": reminder.id,
                "title": reminder.title,
                "listId": reminder.listId,
                "listName": reminder.listName,
                "isCompleted": reminder.isCompleted,
                "priority": reminder.priority,
                "createdDate": reminder.createdDate,
                "lastModifiedDate": reminder.lastModifiedDate
            ]
            if let notes = reminder.notes {
                dict["notes"] = notes
            }
            if let dueDate = reminder.dueDate {
                dict["dueDate"] = dueDate
            }
            if let dueDateIncludesTime = reminder.dueDateIncludesTime {
                dict["dueDateIncludesTime"] = dueDateIncludesTime
            }
            if let completionDate = reminder.completionDate {
                dict["completionDate"] = completionDate
            }
            if let url = reminder.url {
                dict["url"] = url
            }
            if let alarms = reminder.alarms {
                dict["alarms"] = alarms.map { $0.toDict() }
            }
            if let rules = reminder.recurrenceRules {
                dict["recurrenceRules"] = rules.map { $0.toDict() }
            }
            return dict
        }
    }

    private func sendResponse(_ response: MCPResponse) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
        } catch {
            logError("Error encoding response: \(error)")
        }
    }

    private func toJSON(_ object: Any) throws -> String {
        if let encodable = object as? Encodable {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(AnyEncodable(encodable))
            guard let string = String(data: data, encoding: .utf8) else {
                throw MCPToolError("Failed to convert to JSON string")
            }
            return string
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPToolError("Failed to convert to JSON string")
        }
        return string
    }
}

// MARK: - AnyEncodable Helper

struct AnyEncodable: Encodable {
    private let encodable: Encodable

    init(_ encodable: Encodable) {
        self.encodable = encodable
    }

    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}

// MARK: - Logging

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

func logError(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
    fflush(stderr)
}

// MARK: - Main

@main
struct AppleRemindersMCP {
    static func main() async {
        let server = MCPServer()
        await server.start()
    }
}
