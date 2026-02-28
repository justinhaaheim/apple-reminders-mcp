import Foundation
#if canImport(EventKit)
import EventKit

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
