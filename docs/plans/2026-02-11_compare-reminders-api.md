# Comparison: Apple Reminders MCP vs Claude iOS Reminders API

Comparing our Apple Reminders MCP server API (`v2.0.0`) against the Claude iOS Reminders API (`*_v0` tools) to identify gaps, differences, and opportunities for alignment.

---

## Tool Mapping

| Claude iOS Tool           | Our MCP Tool       | Notes                                                                               |
| ------------------------- | ------------------ | ----------------------------------------------------------------------------------- |
| `reminder_list_search_v0` | `get_lists`        | Ours has no search/filter; returns all lists                                        |
| `reminder_search_v0`      | `query_reminders`  | Different approach: we use JMESPath, they use dedicated params                      |
| `reminder_create_v0`      | `create_reminders` | Different structure (grouped by list vs flat array)                                 |
| `reminder_update_v0`      | `update_reminders` | Similar; key differences in completion handling                                     |
| `reminder_delete_v0`      | `delete_reminders` | Similar; ours takes `ids[]`, theirs takes `reminderDeletions[]` with optional title |
| —                         | `create_list`      | **We have this; iOS does not**                                                      |
| —                         | `export_reminders` | **We have this; iOS does not**                                                      |

---

## Feature Comparison

### List Search

| Feature              | Claude iOS         | Ours         | Gap?         |
| -------------------- | ------------------ | ------------ | ------------ |
| Get all lists        | Yes                | Yes          | —            |
| Search lists by text | Yes (`searchText`) | No           | **GAP**      |
| Returns `listId`     | Yes                | Yes (`id`)   | —            |
| Returns list name    | Yes                | Yes (`name`) | —            |
| Returns `isDefault`  | Not documented     | Yes          | We have more |

**Assessment:** Minor gap. List search by text is a convenience; with few lists, filtering on the client side is fine. Low priority.

---

### Reminder Search / Query

| Feature                                                                                 | Claude iOS                     | Ours                                           | Gap?               |
| --------------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------- | ------------------ |
| Text search (title/notes)                                                               | Yes (`searchText`)             | Via JMESPath `contains()`                      | Different approach |
| Filter by list ID                                                                       | Yes (`listId`)                 | Yes (`list.id`)                                | —                  |
| Filter by list name                                                                     | Yes (`listName`)               | Yes (`list.name`)                              | —                  |
| Search all lists                                                                        | Implicit (omit list params)    | Yes (`list.all`)                               | —                  |
| Status filter                                                                           | `"incomplete"` / `"completed"` | `"incomplete"` / `"completed"` / `"all"`       | **We have more**   |
| Date range: `dateFrom`                                                                  | Yes                            | No (use JMESPath)                              | **GAP**            |
| Date range: `dateTo`                                                                    | Yes                            | No (use JMESPath)                              | **GAP**            |
| Result limit                                                                            | Yes (`limit`, default 100)     | Yes (`limit`, default 50, max 200)             | —                  |
| Sort options                                                                            | Not documented                 | Yes (`sortBy`: newest/oldest/priority/dueDate) | **We have more**   |
| JMESPath queries                                                                        | No                             | Yes                                            | **We have more**   |
| Date filter semantic switching (due date for incomplete, completion date for completed) | Yes                            | No                                             | **GAP** (nice UX)  |

**Assessment:** Our JMESPath approach is more powerful but less discoverable. The iOS API's `searchText`, `dateFrom`, and `dateTo` parameters are simpler for common use cases. The semantic switching on date filters (filtering by due date for incomplete, completion date for completed) is a nice UX touch we lack.

**Recommendation:** Consider adding dedicated `searchText`, `dateFrom`, and `dateTo` parameters as convenient shortcuts (pre-JMESPath filters). JMESPath remains the power-user option.

---

### Reminder Creation

| Feature                         | Claude iOS                    | Ours                       | Gap?                |
| ------------------------------- | ----------------------------- | -------------------------- | ------------------- |
| Batch create                    | Yes                           | Yes                        | —                   |
| Title                           | Yes (required)                | Yes (required)             | —                   |
| Notes                           | Yes                           | Yes                        | —                   |
| Due date                        | Yes                           | Yes                        | —                   |
| `dueDateIncludesTime`           | Yes                           | No                         | **GAP**             |
| Priority (none/low/medium/high) | Yes                           | Yes                        | —                   |
| URL                             | Yes                           | No                         | **GAP**             |
| Completion date on create       | Yes                           | No                         | Minor               |
| **Alarms**                      | **Yes (absolute + relative)** | **No**                     | **MAJOR GAP**       |
| **Recurrence (RRULE)**          | **Yes (full iCal RRULE)**     | **No**                     | **MAJOR GAP**       |
| Grouping by list                | By `listId` in wrapper        | Per-reminder `list` object | Different structure |
| Partial failure reporting       | Not documented                | Yes (`created` + `failed`) | **We have more**    |

**Assessment:** Two major gaps: **alarms** and **recurrence**. These are significant features for a reminders app. The iOS API has a rich, well-designed schema for both.

---

### Reminder Update

| Feature                   | Claude iOS                         | Ours                                        | Gap?                  |
| ------------------------- | ---------------------------------- | ------------------------------------------- | --------------------- |
| Batch update              | Yes                                | Yes                                         | —                     |
| Update title              | Yes                                | Yes                                         | —                     |
| Update notes              | Yes (empty string clears)          | Yes (null clears)                           | Different convention  |
| Update due date           | Yes (null removes)                 | Yes (null removes)                          | —                     |
| `dueDateIncludesTime`     | Yes                                | No                                          | **GAP**               |
| Update priority           | Yes                                | Yes                                         | —                     |
| Update URL                | Yes                                | No                                          | **GAP**               |
| Move to different list    | Yes (`listId`)                     | Yes (`list.name` or `list.id`)              | Ours is more flexible |
| Mark complete             | `completionDate` = ISO string      | `completed: true` or `completedDate`        | —                     |
| Mark incomplete           | `completionDate: null`             | `completed: false` or `completedDate: null` | —                     |
| **Update alarms**         | **Yes (replace all; `[]` clears)** | **No**                                      | **MAJOR GAP**         |
| **Update recurrence**     | **Yes**                            | **No**                                      | **MAJOR GAP**         |
| Partial failure reporting | Not documented                     | Yes (`updated` + `failed`)                  | **We have more**      |

**Assessment:** Same major gaps as creation: alarms and recurrence. The `dueDateIncludesTime` and `url` fields are also missing.

---

### Reminder Deletion

| Feature                   | Claude iOS                     | Ours                       | Gap?                |
| ------------------------- | ------------------------------ | -------------------------- | ------------------- |
| Batch delete              | Yes                            | Yes                        | —                   |
| Identifier                | `id` (required)                | `ids[]` (array of strings) | Different structure |
| Title in request          | Yes (optional, for UI display) | No                         | Minor               |
| Partial failure reporting | Not documented                 | Yes (`deleted` + `failed`) | **We have more**    |

**Assessment:** Functionally equivalent. The iOS API includes an optional `title` field for confirmation display, which is a nice touch but not critical.

---

### Reminder Data Model

| Field                 | Claude iOS                                    | Ours | Gap?             |
| --------------------- | --------------------------------------------- | ---- | ---------------- |
| `id`                  | Yes                                           | Yes  | —                |
| `title`               | Yes                                           | Yes  | —                |
| `notes`               | Yes                                           | Yes  | —                |
| `listId`              | Yes                                           | Yes  | —                |
| `listName`            | Not returned (inferred)                       | Yes  | **We have more** |
| `isCompleted`         | Not returned (inferred from `completionDate`) | Yes  | **We have more** |
| `priority`            | Yes                                           | Yes  | —                |
| `dueDate`             | Yes                                           | Yes  | —                |
| `dueDateIncludesTime` | Yes                                           | No   | **GAP**          |
| `completionDate`      | Yes                                           | Yes  | —                |
| `creationDate`        | Not documented                                | Yes  | **We have more** |
| `modificationDate`    | Not documented                                | Yes  | **We have more** |
| `url`                 | Yes                                           | No   | **GAP**          |
| `alarms`              | Yes                                           | No   | **MAJOR GAP**    |
| `recurrence`          | Yes                                           | No   | **MAJOR GAP**    |

---

## Summary of Gaps

### Major Gaps (High Priority)

| Feature        | Description                                                                                                                                                                                                     | Effort      |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| **Alarms**     | Absolute (specific datetime) and relative (seconds before due) alarms. The iOS API supports an array of alarms per reminder.                                                                                    | Medium-High |
| **Recurrence** | Full iCalendar RRULE support with structured fields (`frequency`, `interval`, `daysOfWeek`, `dayOfMonth`, `months`, `position`) plus `humanReadableFrequency`. Supports `end` conditions (count or until date). | High        |

### Minor Gaps (Medium Priority)

| Feature                   | Description                                                                                                             | Effort |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------ |
| **`url` field**           | Attach a URL to a reminder. EventKit supports this natively via `EKReminder.url`.                                       | Low    |
| **`dueDateIncludesTime`** | Boolean indicating whether the due date has a specific time or is all-day. EventKit has `isAllDay` on `EKCalendarItem`. | Low    |
| **Date range filtering**  | Dedicated `dateFrom`/`dateTo` params on search, with semantic switching by status.                                      | Medium |
| **List search text**      | `searchText` parameter on list search.                                                                                  | Low    |

### Things We Have That iOS Doesn't

| Feature                                 | Description                                               |
| --------------------------------------- | --------------------------------------------------------- |
| **`create_list`**                       | Create new reminder lists (iOS only searches existing)    |
| **`export_reminders`**                  | Export reminders to JSON file for backup                  |
| **JMESPath queries**                    | Powerful query language for filtering/projecting results  |
| **`status: "all"`**                     | Search both complete and incomplete at once               |
| **Sort options**                        | `sortBy` parameter (newest/oldest/priority/dueDate)       |
| **`listName` in results**               | Returned alongside `listId` for convenience               |
| **`isCompleted` in results**            | Explicit boolean (iOS requires checking `completionDate`) |
| **`creationDate` / `modificationDate`** | Metadata timestamps in results                            |
| **`isDefault` on lists**                | Indicates which list is the default                       |
| **Partial failure reporting**           | Detailed `created`/`failed` arrays on batch operations    |

---

## Structural Differences

### Create: Grouping by List

**Claude iOS** groups reminders by list in a wrapper:

```json
{
  "reminderLists": [
    {"listId": "abc", "reminders": [{"title": "Buy milk"}]},
    {"listId": "xyz", "reminders": [{"title": "Call dentist"}]}
  ]
}
```

**Ours** uses a flat array with per-reminder list specification:

```json
{
  "reminders": [
    {"title": "Buy milk", "list": {"id": "abc"}},
    {"title": "Call dentist", "list": {"id": "xyz"}}
  ]
}
```

**Assessment:** Our flat structure is simpler and more flexible. The iOS grouped structure is slightly more efficient when creating many reminders in the same list, but the difference is negligible. Our approach also supports list lookup by name, not just ID.

### Delete: ID Array vs Object Array

**Claude iOS:** `{ "reminderDeletions": [{ "id": "abc", "title": "Buy milk" }] }`
**Ours:** `{ "ids": ["abc", "def"] }`

**Assessment:** Ours is simpler. The optional `title` in iOS is a nice-to-have for UI confirmation but not functionally necessary.

### Completion Handling

**Claude iOS:** Uses `completionDate` (set to ISO string to complete, `null` to uncomplete)
**Ours:** Supports both `completed: boolean` AND `completedDate: string | null`, with `completedDate` taking precedence

**Assessment:** Our approach is more flexible and ergonomic. `completed: true` is simpler than constructing an ISO date string.

### List Selection

**Claude iOS:** Uses `listId` string directly
**Ours:** Uses `list` object with `name`, `id`, or `all` options

**Assessment:** Our approach is more flexible (supports name-based lookup), though slightly more verbose for the common case.

---

## Recommendations

### Phase 1: Low-hanging fruit

1. **Add `url` field** to reminder creation, update, and output — EventKit supports this natively
2. **Add `dueDateIncludesTime` field** — Maps to EventKit's `isAllDay` property

### Phase 2: Core feature parity

3. **Add alarm support** — Absolute and relative alarms, stored as an array on each reminder
4. **Add recurrence support** — RRULE-based recurrence with structured helper fields

### Phase 3: Search UX improvements

5. **Add `searchText` parameter** to `query_reminders` — Simple text search before JMESPath
6. **Add `dateFrom`/`dateTo` parameters** to `query_reminders` — Convenient date range filtering
7. **Add `searchText` parameter** to `get_lists` — Low priority, minor convenience

### Not recommended to change

- Our flat array structure for create (simpler than iOS's grouped approach)
- Our `completed: boolean` shorthand for updates (more ergonomic than iOS's approach)
- Our `list` object with name/id/all options (more flexible than iOS's `listId`-only)
- Our JMESPath support (powerful, unique differentiator)
- Our `create_list` and `export_reminders` tools (useful additions beyond iOS)
