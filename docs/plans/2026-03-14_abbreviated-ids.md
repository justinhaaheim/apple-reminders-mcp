# Abbreviated UUID Support for Reminder IDs

**Date**: 2026-03-14
**Status**: Core implementation complete

## What Was Done

### ID Resolution (`RemindersManager.resolveReminder`)

- Added `resolveReminder(id:)` async method that does git-style prefix matching
- Fast path: exact match via `store.getReminder(withId:)` (no fetch needed)
- Slow path: fetches all reminders, normalizes IDs (uppercase, strip dashes), prefix matches
- Returns clear error for 0 matches or ambiguous matches (lists conflicting IDs)
- Made `updateReminders` and `deleteReminders` async to support prefix resolution
- Updated all callers (MCPServer, UpdateCommand, DeleteCommand)

### Short ID Output (`RemindersManager.computeShortIds`)

- Added `computeShortIds(for:minLength:)` static method
- Computes minimum unique prefix for each ID in a result set (min 7 chars)
- Compact/minimal output: `id` field contains short form
- Full output: `id` stays full, `shortId` field added
- Short IDs are lowercase, no dashes

### Test Fixes

- Updated pre-existing snapshot failures (tool descriptions, tool count, version changes from prior commits)
- All 88 tests pass

## Files Changed

- `Sources/AppleRemindersCore/RemindersManager.swift` — core logic
- `Sources/AppleRemindersCore/MCPServer.swift` — await + description updates
- `Sources/AppleRemindersCore/HelpContent.swift` — mention abbreviated IDs
- `Sources/AppleRemindersCLI/UpdateCommand.swift` — await
- `Sources/AppleRemindersCLI/DeleteCommand.swift` — await
- `test/readonly.test.ts` — fix pre-existing tool count assertion
- `test/api-parity.test.ts` — fix pre-existing description assertion
- `test/__snapshots__/schema-snapshot.test.ts.snap` — updated snapshots

## What's Next

- [ ] Add dedicated tests for abbreviated ID resolution (prefix match, ambiguous, case-insensitive)
- [ ] Add dedicated tests for short ID computation
- [ ] Update SKILL.md / CLAUDE.md docs to mention abbreviated IDs
- [ ] Consider: should MCP create/update responses also use short IDs?
