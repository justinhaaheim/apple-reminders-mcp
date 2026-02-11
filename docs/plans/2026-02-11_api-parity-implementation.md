# API Parity Implementation

## Goal

Implement all 6 missing features to reach parity with the Claude iOS Reminders API.

## Features (ordered by complexity)

### 1. URL field (simple)

- Add `url` to `Reminder` protocol, `EKReminderWrapper`, `MockReminder`
- Add to `ReminderOutput`, `CreateReminderInput`, `UpdateReminderInput`
- Add to tool schemas, `convertToOutput`, create/update logic, `encodableArray`

### 2. dueDateIncludesTime field (simple)

- Maps to EventKit's `isAllDay` (inverted: `dueDateIncludesTime = !isAllDay`)
- Add to `Reminder` protocol as `isAllDay`, expose as `dueDateIncludesTime` in output
- Add to create/update input and logic

### 3. searchText parameter (medium)

- Add `searchText` param to `query_reminders` tool
- Case-insensitive search across title and notes
- Applied after status filter, before JMESPath

### 4. dateFrom/dateTo parameters (medium)

- Add to `query_reminders` tool
- For incomplete: filter by dueDate. For completed: filter by completionDate
- ISO 8601 format

### 5. Alarms (complex)

- Add `alarms` array to reminder model
- Each alarm: either `absoluteDate` (ISO 8601) or `offset` (seconds before due)
- Maps to EventKit's `EKAlarm` with `absoluteDate` and `relativeOffset`

### 6. Recurrence (complex)

- Add `recurrenceRule` to reminder model
- Structured fields: frequency, interval, daysOfWeek, dayOfMonth, months, position, end
- Maps to EventKit's `EKRecurrenceRule`

## Progress

- [x] URL field
- [x] dueDateIncludesTime
- [x] searchText
- [x] dateFrom/dateTo
- [x] Alarms
- [x] Recurrence

## Implementation Notes

All 6 features implemented in a single pass in `Sources/main.swift`:

1. **Protocol layer** — Extended `Reminder` protocol with `url`, `isAllDay`, `alarms`, `recurrenceRules`
2. **EKReminderWrapper** — Full EventKit integration for alarms (EKAlarm) and recurrence (EKRecurrenceRule)
3. **MockReminder** — In-memory storage for all new fields (testing)
4. **Input/Output models** — New structs: `AlarmInput`, `AlarmOutput`, `RecurrenceRuleInput`, `RecurrenceRuleOutput`
5. **Tool schemas** — Updated JSON schemas for `create_reminders`, `update_reminders`, `query_reminders`
6. **Tests** — Comprehensive test suite in `test/api-parity.test.ts`
