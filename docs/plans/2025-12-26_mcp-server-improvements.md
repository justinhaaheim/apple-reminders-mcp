# Apple Reminders MCP Server - Improvement Scratchpad

## Goal

Enhance this MCP server to provide Claude iOS-level Reminders functionality on macOS, enabling:

- Full CRUD operations with rich features (alarms, recurrence, URLs)
- Powerful search and filtering capabilities
- Batch operations for efficiency
- API parity with Claude iOS where sensible

## Status: PLANNING

Forked from [farmerajf/apple-reminders-mcp](https://github.com/farmerajf/apple-reminders-mcp). Project tooling set up. Ready to implement improvements.

---

## Current State (What We Have)

### Tools Available (8)

| Tool                   | Description                             | Limitations                      |
| ---------------------- | --------------------------------------- | -------------------------------- |
| `list_reminder_lists`  | Get all reminder lists                  | No search/filter                 |
| `create_reminder_list` | Create a new list                       | ✅ Complete                      |
| `list_today_reminders` | Get today's/overdue reminders           | ✅ Complete                      |
| `list_reminders`       | Get reminders with list/complete filter | No text search, no date range    |
| `create_reminder`      | Create reminder                         | No alarms, no recurrence, no URL |
| `complete_reminder`    | Mark complete                           | ✅ Complete                      |
| `delete_reminder`      | Delete a reminder                       | ✅ Complete                      |
| `update_reminder`      | Update title, notes, due, priority      | No alarms, no recurrence, no URL |

### What's Missing vs Claude iOS API

| Feature                 | Current  | Claude iOS            | Priority |
| ----------------------- | -------- | --------------------- | -------- |
| **Alarms**              | ❌       | Absolute + relative   | HIGH     |
| **Recurrence**          | ❌       | Full RRULE support    | HIGH     |
| **Text search**         | ❌       | searchText parameter  | HIGH     |
| **Date range filter**   | ❌       | dateFrom/dateTo       | MEDIUM   |
| **URL attachment**      | ❌       | url field             | MEDIUM   |
| **Batch create**        | ❌       | Multiple per call     | MEDIUM   |
| **Batch update**        | ❌       | Multiple per call     | LOW      |
| **Batch delete**        | ❌       | Multiple per call     | LOW      |
| **startDate**           | ❌       | Separate from dueDate | LOW      |
| **dueDateIncludesTime** | Inferred | Explicit boolean      | LOW      |
| **Priority enum**       | Int 0-9  | none/low/medium/high  | LOW      |
| **List search**         | ❌       | searchText filter     | LOW      |

---

## Claude iOS API Reference

The Claude iOS app provides these Reminders tools:

### `reminder_list_search_v0`

- `searchText`: Optional filter for list names

### `reminder_search_v0`

- `searchText`: Search in titles and notes
- `listId` / `listName`: Filter by list
- `status`: "incomplete" | "completed"
- `dateFrom` / `dateTo`: Date range (ISO 8601)
- `limit`: Max results (default 100)

### `reminder_create_v0`

- Groups reminders by `listId`
- Each reminder has:
  - `title` (required)
  - `notes`, `dueDate`, `dueDateIncludesTime`
  - `completionDate`, `priority` (none/low/medium/high)
  - `url`
  - `alarms[]`: `{type: "absolute"|"relative", date?, secondsBefore?}`
  - `recurrence`: `{rrule, frequency, interval, daysOfWeek, dayOfMonth, months, position, end}`

### `reminder_update_v0`

- Same fields as create, plus `id` (required)
- Can update multiple reminders at once

### `reminder_delete_v0`

- `reminderDeletions[]`: Array of `{id, title?}`

---

## Implementation Plan

### Phase 1: Alarms (HIGH PRIORITY)

**Why**: Alarms are core to reminders - users expect notifications.

**EventKit API**:

```swift
// Relative alarm (seconds before due date)
let alarm = EKAlarm(relativeOffset: -900) // 15 min before

// Absolute alarm (specific date/time)
let alarm = EKAlarm(absoluteDate: date)

reminder.addAlarm(alarm)
```

**Tasks**:

- [ ] Add `alarms` parameter to `create_reminder`
- [ ] Add `alarms` parameter to `update_reminder`
- [ ] Return alarms in reminder list responses
- [ ] Support both absolute and relative types

**Schema** (matching Claude iOS):

```json
{
  "alarms": [
    {"type": "absolute", "date": "2025-01-15T09:00:00-08:00"},
    {"type": "relative", "secondsBefore": 900}
  ]
}
```

---

### Phase 2: Recurrence (HIGH PRIORITY)

**Why**: Repeating reminders are essential for habits, recurring tasks.

**EventKit API**:

```swift
let rule = EKRecurrenceRule(
    recurrenceWith: .weekly,
    interval: 1,
    daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
    daysOfTheMonth: nil,
    monthsOfTheYear: nil,
    weeksOfTheYear: nil,
    daysOfTheYear: nil,
    setPositions: nil,
    end: nil
)
reminder.recurrenceRules = [rule]
```

**Tasks**:

- [ ] Add `recurrence` parameter to `create_reminder`
- [ ] Add `recurrence` parameter to `update_reminder`
- [ ] Return recurrence rules in responses
- [ ] Support frequency, interval, daysOfWeek, end conditions

**Schema** (matching Claude iOS):

```json
{
  "recurrence": {
    "frequency": "weekly",
    "interval": 1,
    "daysOfWeek": ["MO", "WE", "FR"],
    "end": {"type": "count", "count": 10}
  }
}
```

---

### Phase 3: Enhanced Search (HIGH PRIORITY)

**Why**: Finding specific reminders among thousands is critical.

**Tasks**:

- [ ] Add `query` parameter for text search in titles/notes
- [ ] Add `dateFrom` / `dateTo` for date range filtering
- [ ] Add `limit` parameter
- [ ] Add `listId` support (not just list name)

**Implementation Notes**:

- Use `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` for date filtering
- Post-filter with `title.localizedCaseInsensitiveContains(query)` for text search

---

### Phase 4: URL and Minor Fields (MEDIUM PRIORITY)

**Why**: URL attachments are useful for linking to related content.

**Tasks**:

- [ ] Add `url` field to create/update
- [ ] Return `url` in responses (already in EKReminder)
- [ ] Add `startDate` support (EKReminder.startDateComponents)
- [ ] Add explicit `dueDateIncludesTime` boolean

---

### Phase 5: Batch Operations (MEDIUM PRIORITY)

**Why**: Creating/updating multiple reminders efficiently.

**Tasks**:

- [ ] Redesign `create_reminder` to accept array of reminders grouped by list
- [ ] Redesign `update_reminder` to accept array of updates
- [ ] Redesign `delete_reminder` to accept array of IDs

**Note**: This changes the API significantly. Consider adding new tools (`create_reminders`, `update_reminders`) instead of breaking existing ones.

---

### Phase 6: API Alignment (LOW PRIORITY)

**Why**: Consistency with Claude iOS for familiarity.

**Tasks**:

- [ ] Consider renaming tools to match iOS (`reminder_create_v0` style)
- [ ] Use priority enum (none/low/medium/high) instead of 0-9
- [ ] Add list search filter to `list_reminder_lists`

---

## Code Organization

Current structure is a single 900-line `main.swift`. Consider refactoring:

```
Sources/
├── main.swift              # Entry point
├── MCPServer.swift         # MCP protocol handling
├── RemindersManager.swift  # EventKit operations
├── Models/
│   ├── MCPTypes.swift      # Request/Response types
│   └── ReminderTypes.swift # Reminder DTOs
└── Extensions/
    └── EventKit+Extensions.swift  # EKReminderPriority, etc.
```

**Note**: Swift Package Manager allows multiple files in Sources/ - just need to remove `@main` attribute approach or consolidate entry point.

---

## Reference: iMCP Patterns to Borrow

From [mattt/iMCP](https://github.com/mattt/iMCP):

### Alarm Implementation

```swift
if case let .array(alarmMinutes) = arguments["alarms"] {
    reminder.alarms = alarmMinutes.compactMap {
        guard case let .int(minutes) = $0 else { return nil }
        return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
    }
}
```

### Priority Enum

```swift
extension EKReminderPriority {
    static func from(string: String) -> EKReminderPriority {
        switch string.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .none
        }
    }

    var stringValue: String {
        switch self {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
}
```

### Flexible Date Parsing

```swift
// iMCP uses ISO8601DateFormatter.parseFlexibleISODate()
// Handles both full datetime and date-only formats
```

---

## Testing Strategy

### Manual Testing

- Use existing `test.sh` scripts for MCP protocol testing
- Test with Claude Desktop integration

### Automated Testing

- Add Swift tests for RemindersManager (mocking EKEventStore is tricky)
- Focus on unit tests for parsing/serialization logic

---

## Open Questions

1. **Breaking changes**: Should we maintain backward compatibility with existing tool names/schemas, or is a clean break acceptable?

2. **Batch operations**: Add new tools (`create_reminders`) or modify existing (`create_reminder` accepts array)?

3. **Recurrence complexity**: Full RRULE support is complex. Start with common cases (daily, weekly, monthly) or go all-in?

4. **Code organization**: Refactor to multiple files now, or keep single file for simplicity?

---

## Resources

- [EKReminder Documentation](https://developer.apple.com/documentation/eventkit/ekreminder)
- [EKAlarm Documentation](https://developer.apple.com/documentation/eventkit/ekalarm)
- [EKRecurrenceRule Documentation](https://developer.apple.com/documentation/eventkit/ekrecurrencerule)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [farmerajf/apple-reminders-mcp](https://github.com/farmerajf/apple-reminders-mcp) - Original repo
- [mattt/iMCP](https://github.com/mattt/iMCP) - Reference for patterns

---

## Progress Log

### 2025-12-29

- Added test mode (`AR_MCP_TEST_MODE=1`) to protect real reminders during testing
  - Write operations restricted to lists prefixed with `[AR-MCP TEST]`
  - Validation in `RemindersManager` for create/update/delete/complete operations
- Created TypeScript test suite using `bun test`:
  - `test/mcp-client.ts` - MCP client utility for spawning server
  - `test/readonly.test.ts` - Read-only operation tests (tools, lists)
  - `test/crud.test.ts` - CRUD tests isolated to test list
  - `test/test-mode.test.ts` - Verify test mode restrictions work
- Moved `test-interactive.sh` to `test/interactive.sh`
- Deleted old bash test scripts
- Tests are now completely safe - cannot modify real reminders

### 2025-12-26

- Forked farmerajf/apple-reminders-mcp to ~/Dev/apple-reminders-mcp
- Added project tooling (husky, prettier, .claude/, .vscode/, GitHub workflows)
- Created CLAUDE.md with project documentation
- Created this improvement scratchpad
