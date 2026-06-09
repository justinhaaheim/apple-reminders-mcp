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
    public let priority: String?  // "low", "medium", "high"; nil when unset
    public let dueDate: String?
    public let dueDateIncludesTime: Bool?
    public let completedDate: String?
    public let createdDate: String
    public let modifiedDate: String
    public let url: String?
    public let alarms: [AlarmOutput]?
    public let recurrenceRules: [RecurrenceRuleOutput]?

    // SQLite-derived enrichment (populated when ReminderDBReader is
    // available to the caller). nil means "DB enrichment unavailable";
    // an empty value means "DB available, this reminder has none".
    public var hashtags: [String]?

    /// UUID of the parent reminder when this reminder is a subtask.
    /// nil means either "top-level" or "DB enrichment unavailable" — the
    /// two cases are functionally indistinguishable from a single field.
    public var parentId: String?

    /// UUIDs of direct children. nil when DB enrichment is unavailable;
    /// `[]` when the reminder has no children. Order matches the user's
    /// arrangement in Reminders.app (sorted by `ZICSDISPLAYORDER`).
    public var childIds: [String]?

    /// Within-list section ("kanban column"), if the reminder is in one.
    /// `nil` either means "DB unavailable" or "not in a section" — same
    /// ambiguity as parentId.
    public var section: SectionInfo?

    public init(
        id: String, title: String, notes: String?,
        listId: String, listName: String, isCompleted: Bool,
        priority: String?, dueDate: String?, dueDateIncludesTime: Bool?,
        completedDate: String?, createdDate: String, modifiedDate: String,
        url: String?, alarms: [AlarmOutput]?, recurrenceRules: [RecurrenceRuleOutput]?,
        hashtags: [String]? = nil,
        parentId: String? = nil,
        childIds: [String]? = nil,
        section: SectionInfo? = nil
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
        self.completedDate = completedDate
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.url = url
        self.alarms = alarms
        self.recurrenceRules = recurrenceRules
        self.hashtags = hashtags
        self.parentId = parentId
        self.childIds = childIds
        self.section = section
    }
}

public struct ReminderListOutput: Codable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    /// Within-list sections (kanban columns) defined in Reminders.app.
    /// nil when DB enrichment is unavailable; `[]` when the list has no
    /// sections; populated array when it does.
    public var sections: [SectionInfo]?

    public init(id: String, name: String, isDefault: Bool, sections: [SectionInfo]? = nil) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.sections = sections
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
    public let note: String?

    public init(
        success: Bool, path: String, exportDate: String,
        stats: ExportStats, fileSizeBytes: Int, note: String?
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

public struct ListSelector: Encodable {
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

extension Clearable: Encodable where T: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let val):
            try container.encode(val)
        case .clear:
            try container.encodeNil()
        }
    }
}

public struct AlarmInput: Encodable {
    public let type: String          // "absolute" or "relative"
    public let date: String?         // ISO 8601 for absolute alarms
    public let offset: Int?          // seconds before due date for relative alarms

    public init(type: String, date: String?, offset: Int?) {
        self.type = type
        self.date = date
        self.offset = offset
    }
}

public struct RecurrenceRuleInput: Encodable {
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

public struct CreateReminderInput: Encodable {
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

public struct UpdateReminderInput: Encodable {
    public let id: String
    public let title: String?
    public let notes: Clearable<String>?
    public let list: ListSelector?
    public let dueDate: Clearable<String>?
    public let priority: Clearable<String>?
    public let completed: Bool?
    public let completedDate: Clearable<String>?
    public let url: Clearable<String>?
    public let dueDateIncludesTime: Bool?
    public let alarms: Clearable<[AlarmInput]>?
    public let recurrenceRule: Clearable<RecurrenceRuleInput>?

    public init(
        id: String, title: String? = nil, notes: Clearable<String>? = nil,
        list: ListSelector? = nil, dueDate: Clearable<String>? = nil,
        priority: Clearable<String>? = nil, completed: Bool? = nil,
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

// MARK: - Pagination Types

public struct PageInfo: Codable {
    public let hasNextPage: Bool
    public let endCursor: String?

    public init(hasNextPage: Bool, endCursor: String?) {
        self.hasNextPage = hasNextPage
        self.endCursor = endCursor
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "hasNextPage": hasNextPage,
        ]
        if let endCursor = endCursor {
            dict["endCursor"] = endCursor
        } else {
            dict["endCursor"] = NSNull()
        }
        return dict
    }
}

// MARK: - Cursor Encoding/Decoding

public enum CursorError: Error, LocalizedError {
    case invalidCursor(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCursor(let message):
            return message
        }
    }
}

public func decodeCursor(_ cursor: String) throws -> Int {
    guard let data = Data(base64Encoded: cursor) else {
        throw CursorError.invalidCursor("Invalid cursor: not valid base64")
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let offset = json["offset"] as? Int else {
        throw CursorError.invalidCursor("Invalid cursor: malformed cursor data")
    }
    if offset < 0 {
        throw CursorError.invalidCursor("Invalid cursor: negative offset")
    }
    return offset
}

public func encodeCursor(offset: Int) throws -> String {
    let json: [String: Any] = ["offset": offset]
    let data = try JSONSerialization.data(withJSONObject: json)
    return data.base64EncodedString()
}

// MARK: - Priority Conversion

public enum Priority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var internalValue: Int {
        switch self {
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    /// Maps an EventKit priority integer (0 = unset, 1-9 = bucketed)
    /// to a Priority case. Returns nil when no priority is set.
    public static func fromInternal(_ value: Int) -> Priority? {
        switch value {
        case 0: return nil
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return nil
        }
    }

    public static func fromString(_ string: String) -> Priority? {
        return Priority(rawValue: string.lowercased())
    }

    /// The single shared validator for user-supplied priority input, used by
    /// both the CLI and the MCP server so they accept exactly the same values
    /// and surface the same errors. Returns nil for "no priority".
    ///
    /// Accepted inputs (case-insensitive, whitespace-trimmed):
    ///   - "low" / "medium" / "high"        → that level
    ///   - "none" or "0"                    → nil (no priority)
    ///   - Apple's native integers as text:  "1"→high, "5"→medium, "9"→low
    ///
    /// Canonical *output* is always null | low | medium | high; "none" and the
    /// integer forms are accepted for convenience but never emitted. Throws
    /// `RemindersError` for anything else — never a silent drop.
    public static func parse(_ token: String) throws -> Priority? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none", "0": return nil
        case "high", "1": return .high
        case "medium", "5": return .medium
        case "low", "9": return .low
        default:
            throw RemindersError(
                "Invalid priority: \"\(token)\". Accepted: \"low\", \"medium\", \"high\", "
                    + "or \"none\"/null for no priority (Apple integer constants 0/1/5/9 also work). "
                    + "Output is always null, low, medium, or high."
            )
        }
    }
}

// MARK: - Date Formatting

private let iso8601WithTimezoneFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
    f.timeZone = TimeZone.current
    return f
}()

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    return f
}()

private let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Standard: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

extension Date {
    public func toISO8601WithTimezone() -> String {
        return iso8601WithTimezoneFormatter.string(from: self)
    }

    public static func fromISO8601(_ string: String) -> Date? {
        if let date = iso8601WithTimezoneFormatter.date(from: string) {
            return date
        }
        if let date = iso8601WithFractionalSeconds.date(from: string) {
            return date
        }
        if let date = iso8601Standard.date(from: string) {
            return date
        }
        return dateOnlyFormatter.date(from: string)
    }
}
