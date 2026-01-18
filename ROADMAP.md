# Apple Reminders MCP Server - Roadmap

## Vision

A fully-featured MCP server that provides Claude iOS-level Reminders functionality on macOS, enabling rich task management with alarms, recurrence, search, and batch operations.

---

## Milestones

### M1: Safe Testing Infrastructure ✅

Establish a test suite that can't accidentally modify real reminders.

- [x] Test mode (`AR_MCP_TEST_MODE=1`) restricts writes to `[AR-MCP TEST]` lists
- [x] TypeScript test suite with bun test
- [x] Cleanup script for leftover test lists

### M2: Batch Operations ✅

Efficient bulk operations - critical for productivity workflows.

- [x] Create multiple reminders in one call (`create_reminders`)
- [x] Update multiple reminders in one call (`update_reminders`)
- [x] Delete multiple reminders in one call (`delete_reminders`)
- [x] Complete multiple reminders in one call (`complete_reminders`)

### M3: Audit Log & Data Safety ⬅️ NEXT

Paranoid-level logging and data protection. Never lose data, always know what happened.

- [ ] Detailed operation logging (what model requested, what server did)
- [ ] Capture before/after state for all modifications
- [ ] Persist audit log (file or database)
- [ ] Add `list_recent_operations` tool - let model review its own actions
- [ ] Add `undo_operation` tool - revert a specific change
- [ ] Consider: snapshot/backup before destructive operations

### M4: Enhanced Search ✅

Improve reminder discovery.

- [x] `search_reminders` tool with text search, date range, status, limit
- [x] `search_reminder_lists` tool with text search
- [x] Modeled after Claude iOS `reminder_search_v0` API

### M5: Recurrence Support

Add repeating reminder support.

- [ ] `recurrence` parameter on create/update
- [ ] Common patterns: daily, weekly, monthly
- [ ] Days of week, interval support
- [ ] End conditions (count, date)

### M6: Alarms Support

Add alarm/notification support to reminders.

- [ ] `alarms` parameter on create/update
- [ ] Absolute alarms (specific date/time)
- [ ] Relative alarms (X seconds before due date)
- [ ] Return alarms in list responses

### M7: URL & Minor Fields

Complete feature parity with Claude iOS.

- [ ] URL attachment support
- [ ] startDate (separate from dueDate)
- [ ] Explicit dueDateIncludesTime boolean

---

## In Progress

- [docs/plans/2025-12-26_mcp-server-improvements.md](docs/plans/2025-12-26_mcp-server-improvements.md) - Main improvement scratchpad

---

## Next Actions

1. **Implement recurrence support (M5)** - Add `recurrence` parameter to create/update. Start with common patterns: daily, weekly, monthly.

2. **Implement alarm support (M6)** - Add `alarms` parameter for notifications. Support absolute and relative alarms.

3. **Design audit log schema (M3)** - Define what gets logged: timestamps, operation type, input params, result, before/after state.

---

## Backlog

### Features

- [ ] Priority enum (none/low/medium/high) instead of 0-9 integers
- [ ] List search filter for `list_reminder_lists`
- [ ] Consider tool renaming to match Claude iOS (`reminder_create_v0` style)
- [ ] Code refactoring to multiple Swift files (if complexity warrants)
- [ ] Add `listId` support alongside `list_name` for more robust list identification

### Bugs / Issues

_(none currently tracked)_

### Ideas

- AppleScript fallback for operations EventKit can't do (like deleting lists)
- Explore Swift testing options (mocking EKEventStore is tricky)
- Export/import functionality for backup purposes

---

## Open Questions

1. **Audit log storage** - JSON file? SQLite? How long to retain?
2. **Undo granularity** - Undo individual operations or support "undo last N operations"?
3. **Recurrence complexity** - Start with common cases or implement full RRULE support?

---

## Progress Log

### 2026-01-18

- ✅ Completed M4: Enhanced Search
- Added `search_reminders` tool (text search, date range, status filter, limit)
- Added `search_reminder_lists` tool (text search)
- Modeled after Claude iOS `reminder_search_v0` API
- 38 tests passing
- Pushed to GitHub: https://github.com/justinhaaheim/apple-reminders-mcp

### 2026-01-10

- ✅ Completed M2: Batch Operations
- Added 4 batch tools: `create_reminders`, `update_reminders`, `delete_reminders`, `complete_reminders`
- Implemented input validation layer (Codable structs, like Zod pattern)
- Partial success support with per-item results + summary
- 24 tests passing (added batch.test.ts)

### 2025-12-29

- ✅ Completed M1: Safe Testing Infrastructure
- Added test mode with `AR_MCP_TEST_MODE=1`
- Created TypeScript test suite (15 tests)
- Added cleanup script for test lists
- Created ROADMAP.md
- Reprioritized: Batch ops → Audit/Safety → Search → Recurrence → Alarms → URL

### 2025-12-26

- Forked farmerajf/apple-reminders-mcp
- Set up project tooling (husky, prettier, .claude/, .vscode/)
- Created CLAUDE.md and improvement scratchpad
