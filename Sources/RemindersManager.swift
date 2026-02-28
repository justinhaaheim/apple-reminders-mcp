import Foundation
import JMESPath

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
