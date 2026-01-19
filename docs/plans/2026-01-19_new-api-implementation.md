# New Apple Reminders MCP API Implementation

## Goal

Replace the existing 14-tool MCP server with a new consolidated API, currently 7 tools.

## Key Changes Summary

| Current                       | New                                                   |
| ----------------------------- | ----------------------------------------------------- |
| 14 separate tools             | 7 consolidated tools                                  |
| `name`/`body` fields          | `title`/`notes` fields                                |
| Priority as integers (0-9)    | Priority as strings ("none", "low", "medium", "high") |
| `list_name` string parameter  | `list: {name, id, all}` object                        |
| Hardcoded "Reminders" default | Use `defaultCalendarForNewReminders()`                |
| ISO8601 with `Z` suffix       | ISO8601 with `+HH:MM` timezone                        |

## Implementation Checklist

- [x] Add JMESPath dependency to Package.swift
- [x] Implement `get_lists` - simplest tool
- [x] Implement `create_list` - simple, exercises test mode
- [x] Implement `query_reminders` - complex (JMESPath, list selector, sorting)
- [x] Implement `create_reminders` - batch create with partial failure
- [x] Implement `update_reminders` - includes completion logic
- [x] Implement `delete_reminders` - batch delete with partial failure
- [x] Implement `export_reminders` - export to JSON file for backup
- [x] Remove all old tools
- [x] Update tests in `test/*.test.ts`
- [ ] Final verification: `bun run build && bun run test && bun run signal` (requires macOS)

## Notes

- Must preserve `TestModeConfig` struct and validation methods
- All code in `Sources/main.swift`
- Date format uses `yyyy-MM-dd'T'HH:mm:ssXXX` for +HH:MM suffix

## Progress Log

### 2026-01-19: Full Implementation Complete

**Completed:**

1. Added JMESPath dependency (jmespath.swift) to Package.swift
2. Completely rewrote `Sources/main.swift` with the new 6-tool API:
   - `get_lists` - Returns all reminder lists with isDefault flag
   - `create_list` - Creates new list (with test mode validation)
   - `query_reminders` - Full JMESPath support, list selector, sorting, status filter
   - `create_reminders` - Batch create with partial failure handling
   - `update_reminders` - Batch update including completion logic
   - `delete_reminders` - Batch delete with partial failure handling
3. Preserved all TestModeConfig validation infrastructure
4. Updated all tests in `test/*.test.ts` to match new API
5. Formatting passes (`bun run signal` clean)

**Key implementation details:**

- Priority is now string-based ("none", "low", "medium", "high") everywhere
- Dates use `+HH:MM` timezone format via `yyyy-MM-dd'T'HH:mm:ssXXX`
- List selector uses `{name, id, all}` object pattern
- Default list resolved via `eventStore.defaultCalendarForNewReminders()`
- JMESPath integration uses adam-fowler/jmespath.swift library
- Errors returned via `isError: true` in MCP response

**Needs testing on macOS:**

- Build verification (`bun run build`)
- Test execution (`bun run test`)
- The Swift code can't be compiled in the web environment

### 2026-01-19: Added Mock Mode Support

**Completed:**

1. Implemented `ReminderStore` protocol to abstract storage operations
2. Created `EKReminderStore` wrapper for real EventKit
3. Created `MockReminderStore` with full in-memory storage
4. Added `AR_MCP_MOCK_MODE=1` environment variable toggle
5. Updated `MCPClient` test utility to use mock mode by default
6. Tests now run in mock mode (fast, deterministic, cross-platform)

**Key features:**

- Mock mode starts with a default "Reminders" list
- All reminder operations work identically in mock and real mode
- Test mode restrictions work in both modes
- Real mode can be enabled with `MCPClient.create({mockMode: false})`

**Usage:**

```typescript
// Default: mock mode (in-memory, fast, works everywhere)
const client = await MCPClient.create();

// Real EventKit testing (requires macOS)
const client = await MCPClient.createWithRealEventKit();

// Test mock mode with test restrictions
const client = await MCPClient.create({mockMode: true, testMode: true});
```

### 2026-01-19: Added export_reminders Tool

**Completed:**

1. Added `export_reminders` tool for bulk data export/backup
2. Writes to temp directory by default (user moves to permanent location)
3. Supports custom path with `~` expansion
4. Optional list filtering and `includeCompleted` flag
5. Returns small metadata (path, stats, size) - data stays in file

**Key features:**

- File goes to `NSTemporaryDirectory()` with timestamp filename
- Pretty-printed JSON with all lists and reminders
- Stats include: lists count, reminders count, completed/incomplete counts
- Export format includes version and source for future compatibility

**Tool parameters:**

```json
{
  "path": "~/Desktop/backup.json", // optional, default: temp
  "lists": [{"name": "Work"}], // optional, default: all
  "includeCompleted": true // optional, default: true
}
```

**Response example:**

```json
{
  "success": true,
  "path": "/var/folders/.../reminders-export-2026-01-19T103045.json",
  "exportDate": "2026-01-19T10:30:45-08:00",
  "stats": {"lists": 5, "reminders": 1523, "completed": 892, "incomplete": 631},
  "fileSizeBytes": 2048576,
  "note": "File is in temp directory. Move it to a permanent location to keep it."
}
```
