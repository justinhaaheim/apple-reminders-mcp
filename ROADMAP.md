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

### M2: Alarms Support

Add alarm/notification support to reminders.

- [ ] `alarms` parameter on create/update
- [ ] Absolute alarms (specific date/time)
- [ ] Relative alarms (X seconds before due date)
- [ ] Return alarms in list responses

### M3: Recurrence Support

Add repeating reminder support.

- [ ] `recurrence` parameter on create/update
- [ ] Common patterns: daily, weekly, monthly
- [ ] Days of week, interval support
- [ ] End conditions (count, date)

### M4: Enhanced Search

Improve reminder discovery.

- [ ] Text search in titles/notes
- [ ] Date range filtering (dateFrom/dateTo)
- [ ] Result limiting

### M5: URL & Minor Fields

Complete feature parity with Claude iOS.

- [ ] URL attachment support
- [ ] startDate (separate from dueDate)
- [ ] Explicit dueDateIncludesTime boolean

### M6: Batch Operations

Efficient bulk operations.

- [ ] Create multiple reminders in one call
- [ ] Update multiple reminders in one call
- [ ] Delete multiple reminders in one call

---

## In Progress

- [docs/plans/2025-12-26_mcp-server-improvements.md](docs/plans/2025-12-26_mcp-server-improvements.md) - Main improvement scratchpad

---

## Next Actions

1. **Start Phase 1: Alarms** - Add `alarms` array parameter to `create_reminder` and `update_reminder`. This is high priority and self-contained. EventKit API is straightforward (`EKAlarm`).

2. **Add alarm response data** - Update `listReminders`, `getTodayReminders`, and response formatting to include alarm information for existing reminders.

3. **Research recurrence API** - Review EventKit's `EKRecurrenceRule` API to understand complexity before implementing. Consider starting with simple cases (daily, weekly, monthly) vs full RRULE.

---

## Backlog

### Features

- [ ] Priority enum (none/low/medium/high) instead of 0-9 integers
- [ ] List search filter for `list_reminder_lists`
- [ ] Consider tool renaming to match Claude iOS (`reminder_create_v0` style)
- [ ] Code refactoring to multiple Swift files (if complexity warrants)

### Bugs / Issues

_(none currently tracked)_

### Ideas

- Add `listId` support alongside `list_name` for more robust list identification
- Consider AppleScript fallback for operations EventKit can't do (like deleting lists)
- Explore Swift testing options (mocking EKEventStore is tricky)

---

## Open Questions

1. **Breaking changes** - Maintain backward compatibility with existing tool schemas, or clean break?
2. **Batch operations** - New tools (`create_reminders`) or modify existing (`create_reminder` accepts array)?
3. **Recurrence complexity** - Start with common cases or implement full RRULE support?

---

## Progress Log

### 2025-12-29

- ✅ Completed M1: Safe Testing Infrastructure
- Added test mode with `AR_MCP_TEST_MODE=1`
- Created TypeScript test suite (15 tests)
- Added cleanup script for test lists
- Created this ROADMAP.md

### 2025-12-26

- Forked farmerajf/apple-reminders-mcp
- Set up project tooling (husky, prettier, .claude/, .vscode/)
- Created CLAUDE.md and improvement scratchpad
