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

### M2: Batch Operations ⬅️ NEXT

Efficient bulk operations - critical for productivity workflows.

- [ ] Create multiple reminders in one call
- [ ] Update multiple reminders in one call
- [ ] Delete multiple reminders in one call
- [ ] Complete multiple reminders in one call

### M3: Audit Log & Data Safety

Paranoid-level logging and data protection. Never lose data, always know what happened.

- [ ] Detailed operation logging (what model requested, what server did)
- [ ] Capture before/after state for all modifications
- [ ] Persist audit log (file or database)
- [ ] Add `list_recent_operations` tool - let model review its own actions
- [ ] Add `undo_operation` tool - revert a specific change
- [ ] Consider: snapshot/backup before destructive operations

### M4: Enhanced Search

Improve reminder discovery.

- [ ] Text search in titles/notes (`query` parameter)
- [ ] Date range filtering (dateFrom/dateTo)
- [ ] Result limiting (`limit` parameter)

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

1. **Design batch operations API** - Decide: new tools (`create_reminders`, `update_reminders`) vs. modifying existing tools to accept arrays. Consider Claude iOS API shape for reference.

2. **Implement batch create** - Add `create_reminders` tool that accepts an array of reminders grouped by list. Return array of results with IDs.

3. **Implement batch update/delete/complete** - Add remaining batch operations. Consider transaction semantics (all-or-nothing vs. partial success).

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

1. **Batch operations design** - New tools (`create_reminders`) or modify existing (`create_reminder` accepts array)? Leaning toward new tools for clarity.
2. **Audit log storage** - JSON file? SQLite? How long to retain?
3. **Undo granularity** - Undo individual operations or support "undo last N operations"?
4. **Recurrence complexity** - Start with common cases or implement full RRULE support?

---

## Progress Log

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
