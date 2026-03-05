import Foundation

// MARK: - API Data Models

public struct AlarmOutput: Codable {
    public let type: String       // "absolute" or "relative"
    public let date: String?      // ISO 8601 for absolute alarms
    public let offset: Int?       // seconds before due date for relative alarms

    public init(type: String, date: String?, offset: Int?) {
        self.type = type
        self.date = date
        self.offset = offset
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let date = date { dict["date"] = date }
        if let offset = offset { dict["offset"] = offset }
        return dict
    }
}

public struct RecurrenceRuleOutput: Codable {
    public let frequency: String  // "daily", "weekly", "monthly", "yearly"
    public let interval: Int
    public let daysOfWeek: [Int]?
    public let daysOfMonth: [Int]?
    public let monthsOfYear: [Int]?
    public let weekPosition: Int?
    public let endDate: String?
    public let endCount: Int?

    public init(
        frequency: String, interval: Int,
        daysOfWeek: [Int]?, daysOfMonth: [Int]?,
        monthsOfYear: [Int]?, weekPosition: Int?,
        endDate: String?, endCount: Int?
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth
        self.monthsOfYear = monthsOfYear
        self.weekPosition = weekPosition
        self.endDate = endDate
        self.endCount = endCount
    }

    public func toDict() -> [String: Any] {
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

public struct ReminderOutput: Codable {
    public let id: String
    public let title: String
    public let notes: String?
    public let listId: String
    public let listName: String
    public let isCompleted: Bool
    public let priority: String  // "none", "low", "medium", "high"
    public let dueDate: String?
    public let dueDateIncludesTime: Bool?
    public let completionDate: String?
    public let createdDate: String
    public let lastModifiedDate: String
    public let url: String?
    public let alarms: [AlarmOutput]?
    public let recurrenceRules: [RecurrenceRuleOutput]?

    public init(
        id: String, title: String, notes: String?,
        listId: String, listName: String, isCompleted: Bool,
        priority: String, dueDate: String?, dueDateIncludesTime: Bool?,
        completionDate: String?, createdDate: String, lastModifiedDate: String,
        url: String?, alarms: [AlarmOutput]?, recurrenceRules: [RecurrenceRuleOutput]?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.listId = listId
        self.listName = listName
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.dueDateIncludesTime = dueDateIncludesTime
        self.completionDate = completionDate
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.url = url
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
    }
}

public struct ReminderListOutput: Codable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

// MARK: - Export Types

public struct ExportStats: Codable {
    public let lists: Int
    public let reminders: Int
    public let completed: Int
    public let incomplete: Int

    public init(lists: Int, reminders: Int, completed: Int, incomplete: Int) {
        self.lists = lists
        self.reminders = reminders
        self.completed = completed
        self.incomplete = incomplete
    }
}

public struct ExportData: Codable {
    public let exportVersion: String
    public let exportDate: String
    public let source: String
    public let stats: ExportStats
    public let lists: [ReminderListOutput]
    public let reminders: [ReminderOutput]

    public init(
        exportVersion: String, exportDate: String, source: String,
        stats: ExportStats, lists: [ReminderListOutput], reminders: [ReminderOutput]
    ) {
        self.exportVersion = exportVersion
        self.exportDate = exportDate
        self.source = source
        self.stats = stats
        self.lists = lists
        self.reminders = reminders
    }
}

public struct ExportResult: Codable {
    public let success: Bool
    public let path: String
    public let exportDate: String
    public let stats: ExportStats
    public let fileSizeBytes: Int
    public let note: String

    public init(
        success: Bool, path: String, exportDate: String,
        stats: ExportStats, fileSizeBytes: Int, note: String
    ) {
        self.success = success
        self.path = path
        self.exportDate = exportDate
        self.stats = stats
        self.fileSizeBytes = fileSizeBytes
        self.note = note
    }
}

// MARK: - Input Types

public struct ListSelector {
    public let name: String?
    public let id: String?
    public let all: Bool?

    public init(from dict: [String: Any]?) {
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

    public init(name: String? = nil, id: String? = nil, all: Bool? = nil) {
        self.name = name
        self.id = id
        self.all = all
    }

    public var isEmpty: Bool {
        return name == nil && id == nil && all != true
    }
}

/// Represents a field that can be set to a value or explicitly cleared (null).
/// Used in update operations where omission means "don't change" vs null means "clear".
public enum Clearable<T> {
    case value(T)
    case clear
}

public struct AlarmInput {
    public let type: String          // "absolute" or "relative"
    public let date: String?         // ISO 8601 for absolute alarms
    public let offset: Int?          // seconds before due date for relative alarms

    public init(type: String, date: String?, offset: Int?) {
        self.type = type
        self.date = date
        self.offset = offset
    }
}

public struct RecurrenceRuleInput {
    public let frequency: String     // "daily", "weekly", "monthly", "yearly"
    public let interval: Int?        // default 1
    public let daysOfWeek: [Int]?
    public let daysOfMonth: [Int]?
    public let monthsOfYear: [Int]?
    public let weekPosition: Int?
    public let endDate: String?
    public let endCount: Int?

    public init(
        frequency: String, interval: Int? = nil,
        daysOfWeek: [Int]? = nil, daysOfMonth: [Int]? = nil,
        monthsOfYear: [Int]? = nil, weekPosition: Int? = nil,
        endDate: String? = nil, endCount: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth
        self.monthsOfYear = monthsOfYear
        self.weekPosition = weekPosition
        self.endDate = endDate
        self.endCount = endCount
    }
}

public struct CreateReminderInput {
    public let title: String
    public let notes: String?
    public let list: ListSelector?
    public let dueDate: String?
    public let priority: String?
    public let url: String?
    public let dueDateIncludesTime: Bool?
    public let alarms: [AlarmInput]?
    public let recurrenceRule: RecurrenceRuleInput?

    public init(
        title: String, notes: String? = nil, list: ListSelector? = nil,
        dueDate: String? = nil, priority: String? = nil, url: String? = nil,
        dueDateIncludesTime: Bool? = nil, alarms: [AlarmInput]? = nil,
        recurrenceRule: RecurrenceRuleInput? = nil
    ) {
        self.title = title
        self.notes = notes
        self.list = list
        self.dueDate = dueDate
        self.priority = priority
        self.url = url
        self.dueDateIncludesTime = dueDateIncludesTime
        self.alarms = alarms
        self.recurrenceRule = recurrenceRule
    }
}

public struct UpdateReminderInput {
    public let id: String
    public let title: String?
    public let notes: Clearable<String>?
    public let list: ListSelector?
    public let dueDate: Clearable<String>?
    public let priority: String?
    public let completed: Bool?
    public let completedDate: Clearable<String>?
    public let url: Clearable<String>?
    public let dueDateIncludesTime: Bool?
    public let alarms: Clearable<[AlarmInput]>?
    public let recurrenceRule: Clearable<RecurrenceRuleInput>?

    public init(
        id: String, title: String? = nil, notes: Clearable<String>? = nil,
        list: ListSelector? = nil, dueDate: Clearable<String>? = nil,
        priority: String? = nil, completed: Bool? = nil,
        completedDate: Clearable<String>? = nil, url: Clearable<String>? = nil,
        dueDateIncludesTime: Bool? = nil, alarms: Clearable<[AlarmInput]>? = nil,
        recurrenceRule: Clearable<RecurrenceRuleInput>? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.list = list
        self.dueDate = dueDate
        self.priority = priority
        self.completed = completed
        self.completedDate = completedDate
        self.url = url
        self.dueDateIncludesTime = dueDateIncludesTime
        self.alarms = alarms
        self.recurrenceRule = recurrenceRule
    }
}

// MARK: - Priority Conversion

public enum Priority: String, CaseIterable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var internalValue: Int {
        switch self {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    public static func fromInternal(_ value: Int) -> Priority {
        switch value {
        case 0: return .none
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    public static func fromString(_ string: String) -> Priority? {
        return Priority(rawValue: string.lowercased())
    }
}

// MARK: - Date Formatting

extension Date {
    public func toISO8601WithTimezone() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }

    public static func fromISO8601(_ string: String) -> Date? {
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
