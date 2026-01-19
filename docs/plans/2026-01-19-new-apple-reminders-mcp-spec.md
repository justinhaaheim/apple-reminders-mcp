# Apple Reminders MCP Server Specification

## Overview

A Model Context Protocol (MCP) server that provides access to Apple Reminders via stdio transport. Built in Swift, using JMESPath for flexible querying.

**Key design principles:**
- Sensible defaults that minimize required parameters for common queries
- Explicit disambiguation between list names and IDs
- JMESPath for advanced filtering and projection
- All dates in ISO 8601 format with timezone offset (`YYYY-MM-DDTHH:MM:SS+HH:MM`)

---

## Date Format

All dates throughout the API use ISO 8601 with timezone offset:

```
1997-07-16T19:20:30+01:00
2024-01-15T10:30:00-05:00
```

Use Swift's `ISO8601DateFormatter` with `.withInternetDateTime` and `.withTimeZone` options, or format manually to ensure the `+/-HH:MM` suffix (not `Z`).

---

## Data Models

### Reminder

```swift
struct Reminder {
    let id: String                    // Apple's internal identifier
    let title: String
    let notes: String?
    let listId: String                // ID of containing list
    let listName: String              // Name of containing list
    let isCompleted: Bool
    let priority: Int                 // 0 = none, 1 = high, 5 = medium, 9 = low
    let dueDate: String?              // ISO 8601 with timezone, or null
    let completionDate: String?       // ISO 8601 with timezone, or null
    let creationDate: String          // ISO 8601 with timezone
    let modificationDate: String      // ISO 8601 with timezone
}
```

**Priority mapping:**
| Value | Meaning |
|-------|---------|
| 0 | None |
| 1 | High |
| 5 | Medium |
| 9 | Low |

Note: Apple uses these specific values internally. Other values (2-4, 6-8) are technically valid but not used by the Reminders UI.

### ReminderList

```swift
struct ReminderList {
    let id: String                    // Apple's internal identifier
    let name: String
    let isDefault: Bool               // True if this is the user's default list
    let count: Int?                   // Number of incomplete reminders (optional, may be expensive to compute)
}
```

---

## Tools

The server exposes 5 tools:

| Tool | Purpose |
|------|---------|
| `query_reminders` | Query/search reminders with filtering and JMESPath |
| `get_lists` | Get all available reminder lists |
| `create_reminders` | Create one or more reminders |
| `update_reminders` | Update one or more reminders (including complete/uncomplete) |
| `delete_reminders` | Delete one or more reminders |

---

### 1. query_reminders

Query reminders with flexible filtering. This is the primary tool for retrieving reminders.

#### Default Behavior (when parameters are omitted)

| Aspect | Default |
|--------|---------|
| List | Default list only (not all lists) |
| Status | Incomplete only |
| Sort | Newest created first |
| Limit | 50 |

#### Input Schema

```json
{
  "type": "object",
  "properties": {
    "list": {
      "type": "object",
      "description": "Which list to search. Omit for default list only.",
      "properties": {
        "name": {
          "type": "string",
          "description": "List name (case-insensitive match)"
        },
        "id": {
          "type": "string",
          "description": "Exact list ID"
        },
        "all": {
          "type": "boolean",
          "description": "Set true to search all lists"
        }
      },
      "additionalProperties": false
    },
    "status": {
      "type": "string",
      "enum": ["incomplete", "completed", "all"],
      "default": "incomplete",
      "description": "Filter by completion status"
    },
    "sortBy": {
      "type": "string",
      "enum": ["newest", "oldest", "priority", "dueDate"],
      "default": "newest",
      "description": "Sort order. Ignored if 'query' includes sorting."
    },
    "query": {
      "type": "string",
      "description": "JMESPath expression for advanced filtering/projection. Applied after list and status filters."
    },
    "limit": {
      "type": "integer",
      "minimum": 1,
      "maximum": 200,
      "default": 50,
      "description": "Maximum results to return"
    }
  },
  "additionalProperties": false
}
```

#### List Selector Validation

The `list` object must have exactly one of: `name`, `id`, or `all`. If multiple are provided, return an error. If `list` is omitted entirely, use the default list.

```swift
func resolveList(_ selector: ListSelector?) async throws -> [ReminderList] {
    let allLists = try await fetchAllLists()
    
    guard let selector else {
        // No selector → default list
        guard let defaultList = allLists.first(where: { $0.isDefault }) else {
            throw MCPError("No default list found")
        }
        return [defaultList]
    }
    
    // Validate exactly one key is set
    let setCount = [selector.id != nil, selector.name != nil, selector.all == true].filter { $0 }.count
    if setCount != 1 {
        throw MCPError("List selector must specify exactly one of: 'id', 'name', or 'all'")
    }
    
    if selector.all == true {
        return allLists
    }
    
    if let id = selector.id {
        guard let match = allLists.first(where: { $0.id == id }) else {
            throw MCPError("No list found with ID: '\(id)'")
        }
        return [match]
    }
    
    if let name = selector.name {
        guard let match = allLists.first(where: { 
            $0.name.caseInsensitiveCompare(name) == .orderedSame 
        }) else {
            throw MCPError("No list found with name: '\(name)'")
        }
        return [match]
    }
    
    throw MCPError("Invalid list selector")
}
```

#### Processing Order

1. **Resolve list(s)** from selector (or default)
2. **Fetch reminders** from resolved list(s) with status filter (push down to EventKit where possible)
3. **Apply JMESPath** if `query` is provided
4. **Apply sortBy** only if `query` is NOT provided (assume JMESPath handles its own sorting if present)
5. **Apply limit**

#### Sort Implementations

| sortBy | Behavior |
|--------|----------|
| `newest` | By `creationDate` descending (most recent first) |
| `oldest` | By `creationDate` ascending |
| `priority` | By `priority` ascending (1=high first, then 5=medium, then 9=low, then 0=none) |
| `dueDate` | By `dueDate` ascending (soonest first, nulls last) |

#### Tool Description (for LLM)

```
Query reminders from Apple Reminders.

**Default behavior (no parameters needed):**
- Searches DEFAULT LIST only
- Returns INCOMPLETE reminders only
- Sorted by NEWEST CREATED first
- Limited to 50 results

**Parameters (all optional):**

list — Which list to search. Omit for default list.
  • {"name": "Work"} → by exact name (case-insensitive)
  • {"id": "x-apple-..."} → by exact ID
  • {"all": true} → all lists

status — "incomplete" (default), "completed", or "all"

sortBy — "newest" (default), "oldest", "priority", "dueDate"

query — JMESPath expression for advanced filtering (overrides sortBy)

limit — Max results (default 50, max 200)

**Examples:**

Recent incomplete from default list:
  {}

From specific list:
  {"list": {"name": "Work"}}

All lists, completed:
  {"list": {"all": true}, "status": "completed"}

Has any priority set:
  {"query": "[?priority != `0`]"}

High priority only:
  {"query": "[?priority == `1`]"}

Title contains text:
  {"query": "[?contains(title, 'meeting')]"}

Last 10 created across all lists:
  {"list": {"all": true}, "query": "reverse(sort_by(@, &creationDate))[:10]"}

Last 5 modified:
  {"query": "reverse(sort_by(@, &modificationDate))[:5]"}

Just titles and due dates:
  {"query": "[*].{title: title, due: dueDate}"}

Created in 2024:
  {"query": "[?creationDate >= '2024-01-01' && creationDate < '2025-01-01']"}

**Reminder fields available in JMESPath:**
- id (string)
- title (string)
- notes (string or null)
- listId (string)
- listName (string)
- isCompleted (boolean)
- priority (integer: 0=none, 1=high, 5=medium, 9=low)
- dueDate (ISO 8601 string or null)
- completionDate (ISO 8601 string or null)
- creationDate (ISO 8601 string)
- modificationDate (ISO 8601 string)
```

#### Output

Returns an array of Reminder objects (or projected objects if JMESPath reshapes them).

```json
{
  "content": [
    {
      "type": "text",
      "text": "[{\"id\": \"...\", \"title\": \"Buy milk\", ...}, ...]"
    }
  ]
}
```

---

### 2. get_lists

Retrieve all reminder lists. Use this to discover available lists before querying.

#### Input Schema

```json
{
  "type": "object",
  "properties": {},
  "additionalProperties": false
}
```

No parameters required.

#### Tool Description (for LLM)

```
Get all available reminder lists.

Returns list names, IDs, and which one is the default. Call this if you need to know what lists exist before querying reminders.

**Parameters:** None

**Example:**
  {}
```

#### Output

Returns an array of ReminderList objects.

```json
{
  "content": [
    {
      "type": "text", 
      "text": "[{\"id\": \"...\", \"name\": \"Reminders\", \"isDefault\": true}, {\"id\": \"...\", \"name\": \"Work\", \"isDefault\": false}]"
    }
  ]
}
```

---

### 3. create_reminders

Create one or more reminders.

#### Input Schema

```json
{
  "type": "object",
  "required": ["reminders"],
  "properties": {
    "reminders": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["title"],
        "properties": {
          "title": {
            "type": "string",
            "description": "Reminder title"
          },
          "notes": {
            "type": "string",
            "description": "Reminder notes/body text"
          },
          "list": {
            "type": "object",
            "description": "Target list. Uses default list if omitted.",
            "properties": {
              "name": { "type": "string" },
              "id": { "type": "string" }
            },
            "additionalProperties": false
          },
          "dueDate": {
            "type": "string",
            "description": "Due date in ISO 8601 format"
          },
          "priority": {
            "type": "string",
            "enum": ["none", "low", "medium", "high"],
            "description": "Priority level"
          }
        },
        "additionalProperties": false
      }
    }
  },
  "additionalProperties": false
}
```

#### Priority Mapping (Input → Internal)

| Input | Internal Value |
|-------|----------------|
| `"none"` | 0 |
| `"low"` | 9 |
| `"medium"` | 5 |
| `"high"` | 1 |

#### List Selector

Same validation as `query_reminders`, but `all` is not valid (you can't create a reminder in "all lists"). Only `name` or `id` are accepted. If omitted, use the default list.

#### Tool Description (for LLM)

```
Create one or more reminders.

**Parameters:**

reminders — Array of reminder objects to create. Each object:
  • title (required) — Reminder title
  • notes — Body text
  • list — Target list as {"name": "..."} or {"id": "..."}. Default list if omitted.
  • dueDate — ISO 8601 datetime (e.g., "2024-01-15T10:00:00-05:00")
  • priority — "none", "low", "medium", or "high"

**Examples:**

Single reminder:
  {"reminders": [{"title": "Buy milk"}]}

With details:
  {"reminders": [{"title": "Call dentist", "list": {"name": "Personal"}, "dueDate": "2024-01-20T09:00:00-05:00", "priority": "high"}]}

Batch create:
  {"reminders": [
    {"title": "Buy milk"},
    {"title": "Buy eggs"},
    {"title": "Buy bread", "priority": "low"}
  ]}
```

#### Output

Returns array of created reminders in the same order as input.

```json
{
  "content": [
    {
      "type": "text",
      "text": "[{\"id\": \"...\", \"title\": \"Buy milk\", ...}, ...]"
    }
  ]
}
```

#### Partial Failure Handling

If some reminders fail to create (e.g., invalid list), the response includes both successes and failures:

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"created\": [{\"id\": \"...\", \"title\": \"Buy milk\", ...}], \"failed\": [{\"index\": 1, \"error\": \"List not found: 'InvalidList'\"}]}"
    }
  ]
}
```

The `index` refers to the position in the input array (0-based).

---

### 4. update_reminders

Update one or more reminders. Also used to complete/uncomplete reminders.

#### Input Schema

```json
{
  "type": "object",
  "required": ["reminders"],
  "properties": {
    "reminders": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id"],
        "properties": {
          "id": {
            "type": "string",
            "description": "Reminder ID to update"
          },
          "title": {
            "type": "string",
            "description": "New title"
          },
          "notes": {
            "type": "string",
            "description": "New notes. Set to null to clear."
          },
          "list": {
            "type": "object",
            "description": "Move to this list",
            "properties": {
              "name": { "type": "string" },
              "id": { "type": "string" }
            },
            "additionalProperties": false
          },
          "dueDate": {
            "type": "string",
            "description": "New due date in ISO 8601 format. Set to null to clear."
          },
          "priority": {
            "type": "string",
            "enum": ["none", "low", "medium", "high"],
            "description": "New priority level"
          },
          "completed": {
            "type": "boolean",
            "description": "Set true to complete, false to uncomplete"
          },
          "completedDate": {
            "type": "string",
            "description": "Completion date in ISO 8601 format. Set to null to uncomplete. Overrides 'completed' if both provided."
          }
        },
        "additionalProperties": false
      }
    }
  },
  "additionalProperties": false
}
```

#### Completion Logic

Two ways to handle completion:

1. **Simple boolean**: `"completed": true` or `"completed": false`
   - `true` → sets `completedDate` to current time
   - `false` → clears `completedDate`

2. **Explicit date**: `"completedDate": "2024-01-15T10:00:00-05:00"` or `"completedDate": null`
   - ISO 8601 string → sets that specific completion date
   - `null` → clears completion (uncompletes)

If both `completed` and `completedDate` are provided, `completedDate` takes precedence.

#### Tool Description (for LLM)

```
Update one or more reminders. Only specified fields are changed.

**Parameters:**

reminders — Array of update objects. Each object:
  • id (required) — Reminder ID to update
  • title — New title
  • notes — New notes (null to clear)
  • list — Move to list as {"name": "..."} or {"id": "..."}
  • dueDate — New due date as ISO 8601 (null to clear)
  • priority — "none", "low", "medium", or "high"
  • completed — true to complete, false to uncomplete
  • completedDate — ISO 8601 completion date (null to uncomplete)

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

Batch update (complete multiple):
  {"reminders": [
    {"id": "abc", "completed": true},
    {"id": "def", "completed": true},
    {"id": "ghi", "completed": true}
  ]}
```

#### Output

Returns array of updated reminders in the same order as input.

```json
{
  "content": [
    {
      "type": "text",
      "text": "[{\"id\": \"...\", \"title\": \"Buy oat milk\", ...}, ...]"
    }
  ]
}
```

#### Partial Failure Handling

If some reminders fail to update (e.g., ID not found), the response includes both successes and failures:

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"updated\": [{\"id\": \"abc\", ...}], \"failed\": [{\"id\": \"xyz\", \"error\": \"Reminder not found\"}]}"
    }
  ]
}
```

---

### 5. delete_reminders

Delete one or more reminders.

#### Input Schema

```json
{
  "type": "object",
  "required": ["ids"],
  "properties": {
    "ids": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "string"
      },
      "description": "Array of reminder IDs to delete"
    }
  },
  "additionalProperties": false
}
```

#### Tool Description (for LLM)

```
Delete one or more reminders permanently.

**Parameters:**

ids — Array of reminder IDs to delete

**Examples:**

Single delete:
  {"ids": ["abc123"]}

Batch delete:
  {"ids": ["abc123", "def456", "ghi789"]}
```

#### Output

Returns confirmation with deleted IDs.

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"deleted\": [\"abc123\", \"def456\"], \"failed\": []}"
    }
  ]
}
```

If some deletions fail (e.g., ID not found), they appear in `failed` with reasons:

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"deleted\": [\"abc123\"], \"failed\": [{\"id\": \"xyz\", \"error\": \"Reminder not found\"}]}"
    }
  ]
}

---

## JMESPath Integration

### Package

Use [jmespath.swift](https://github.com/adam-fowler/jmespath.swift) by Adam Fowler:

```swift
// Package.swift
.package(url: "https://github.com/adam-fowler/jmespath.swift", from: "1.0.0")
```

### Usage

```swift
import JMESPath

func applyJMESPath(_ reminders: [Reminder], query: String) throws -> Any {
    let expression = try JMESExpression.compile(query)
    return try expression.search(reminders)
}
```

The library uses Swift's `Mirror` for reflection, so it can query your `Reminder` struct directly without JSON serialization. All properties must be accessible (not private).

### Error Handling

If JMESPath compilation or evaluation fails, return a clear error:

```json
{
  "isError": true,
  "content": [
    {
      "type": "text",
      "text": "Invalid JMESPath expression: Unexpected token at position 5. Expression: '[?priority = 1]'. Hint: Use '==' for equality, not '='."
    }
  ]
}
```

---

## Error Handling

### Error Response Format

```json
{
  "isError": true,
  "content": [
    {
      "type": "text",
      "text": "Human-readable error message with actionable guidance"
    }
  ]
}
```

### Common Errors

| Situation | Message |
|-----------|---------|
| List not found by name | `No list found with name: 'Xyz'. Available lists: Reminders, Work, Personal.` |
| List not found by ID | `No list found with ID: 'abc123'.` |
| Invalid list selector | `List selector must specify exactly one of: 'id', 'name', or 'all'.` |
| Reminder not found | `No reminder found with ID: 'abc123'.` |
| Missing required field | `Action 'create' requires 'title' to be specified.` |
| Invalid JMESPath | `Invalid JMESPath expression: <parser error>. Expression: '<query>'.` |
| Invalid priority | `Invalid priority: 'urgent'. Must be one of: none, low, medium, high.` |
| Invalid date format | `Invalid date format: '01-15-2024'. Expected ISO 8601 format like '2024-01-15T10:00:00-05:00'.` |

---

## Implementation Notes

### EventKit Limitations

EventKit's predicate support for reminders is limited. These filters can be pushed down:

- List selection ✅
- Completion status (incomplete vs completed) ✅
- Due date range (for incomplete reminders only) ✅

Everything else requires in-memory filtering after fetch:

- Priority filtering
- Text search (title, notes)
- Creation date filtering
- Modification date filtering

### Performance Considerations

1. **Limit before JMESPath**: Apply the `limit` parameter after JMESPath, but consider fetching more than `limit` if JMESPath might filter down results.

2. **Default list optimization**: When querying just the default list, only fetch from that calendar—don't fetch all and filter.

3. **JMESPath compilation**: If the same query might be used repeatedly, compile the `JMESExpression` once and reuse it.

### Date Formatting

```swift
extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // This gives: 2024-01-15T10:30:00Z
        
        // For +HH:MM timezone format, use DateFormatter instead:
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"  // XXX gives +HH:MM
        df.timeZone = TimeZone.current
        return df.string(from: self)
    }
}
```

### MCP Protocol Notes

- Transport: stdio
- All tool responses use the standard MCP content format with `type: "text"` containing JSON
- Set `isError: true` on error responses
- Tool names use snake_case: `query_reminders`, `get_lists`, `manage_reminder`

---

## Testing Checklist

### query_reminders

- [ ] Empty params returns incomplete reminders from default list, sorted newest first
- [ ] `{"list": {"name": "Work"}}` filters to that list
- [ ] `{"list": {"id": "..."}}` filters by ID
- [ ] `{"list": {"all": true}}` searches all lists
- [ ] `{"status": "completed"}` returns only completed
- [ ] `{"status": "all"}` returns both
- [ ] `{"sortBy": "priority"}` sorts correctly (1, 5, 9, 0)
- [ ] `{"sortBy": "dueDate"}` sorts correctly (nulls last)
- [ ] `{"query": "[?priority != 0]"}` filters to items with priority
- [ ] `{"query": "[?contains(title, 'test')]"}` text search works
- [ ] `{"query": "reverse(sort_by(@, &creationDate))[:5]"}` sorting in JMESPath works
- [ ] `{"limit": 5}` limits results
- [ ] Invalid list name returns helpful error with available lists
- [ ] Invalid JMESPath returns helpful error

### get_lists

- [ ] Returns all lists with names, IDs, and isDefault flag
- [ ] Exactly one list has `isDefault: true`

### create_reminders

- [ ] Single reminder with just title works, uses default list
- [ ] Single reminder with all fields works
- [ ] Batch create works (multiple reminders)
- [ ] List by name works
- [ ] List by ID works
- [ ] Returns created reminders in same order as input
- [ ] Missing title returns helpful error
- [ ] Invalid list returns helpful error
- [ ] Partial failure: valid and invalid reminders in same batch handled correctly

### update_reminders

- [ ] Update single field preserves other fields
- [ ] Update multiple fields at once works
- [ ] Move to different list by name works
- [ ] Move to different list by ID works
- [ ] `completed: true` sets completion with current timestamp
- [ ] `completed: false` clears completion
- [ ] `completedDate: "<timestamp>"` sets specific completion date
- [ ] `completedDate: null` clears completion
- [ ] `dueDate: null` clears due date
- [ ] `notes: null` clears notes
- [ ] Batch update works (multiple reminders)
- [ ] Returns updated reminders in same order as input
- [ ] Invalid ID returns helpful error
- [ ] Partial failure: valid and invalid IDs in same batch handled correctly

### delete_reminders

- [ ] Single delete works
- [ ] Batch delete works
- [ ] Returns deleted IDs in response
- [ ] Invalid ID appears in `failed` array with error message
- [ ] Partial failure (some valid, some invalid) handled correctly

---

## Open Questions / Future Considerations

1. **List management**: Should there be tools to create/rename/delete lists? (EventKit limitation: lists cannot be deleted programmatically)

2. **Recurrence**: Reminders can have recurrence rules. Not exposed in this spec—add later if needed.

3. **Location-based reminders**: Not exposed in this spec. Complex to handle via MCP.

4. **Tags**: Apple Reminders supports tags (iOS 15+). Could be added to the Reminder model and exposed for filtering.

5. **Subtasks**: Reminders can have subtasks. Not exposed in v1.
