import Foundation

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
