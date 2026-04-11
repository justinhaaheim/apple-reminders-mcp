# Swift Unit Tests for RemindersManager

**Epic**: apple-reminders-mcp-rw2
**Branch**: `claude/apple-reminders-mcp-rw2-9tBDf`
**Started**: 2026-04-11

## Goal

Add XCTest-based Swift unit tests that exercise `RemindersManager` directly
with `MockReminderStore`, eliminating the need for the `_seed_mock_data` MCP
tool hack. Once Swift covers test-mode guards, remove `_seed_mock_data` and
rewrite TS test-mode tests to only cover what they can without seeding.

## Sub-beads

- [x] apple-0ld: Add XCTest target to Package.swift and create test directory
- [x] apple-6md: Write test-mode guard tests (P1)
- [x] apple-bzg: Write CRUD lifecycle tests (P2)
- [x] apple-0y8: Write input validation tests (P2)
- [x] apple-753: Remove `_seed_mock_data` and rewrite TS test-mode tests (P1)

## Design Notes

### Target location

`Tests/AppleRemindersCoreTests/` with a `.testTarget` in Package.swift.

### Test-mode toggle

`TestModeConfig.isEnabled` reads `getenv("AR_MCP_TEST_MODE")`. Tests must use
`setenv`/`unsetenv` (not `ProcessInfo`) to toggle the flag at runtime.
A small helper that saves/restores prior env state + uses `defer` for
teardown keeps tests isolated.

### Seeding mocks

`MockReminderStore.calendars` and `.reminders` are public — tests populate
them directly (create `MockCalendar`/`MockReminder` and append to the arrays),
so no `_seed_mock_data` indirection needed.

### Gotchas discovered

- `RemindersManager.createReminders` is synchronous (returns tuple, not async).
- `updateReminders`/`deleteReminders` are async.
- `TestModeConfig.isTestList` matches prefix `[AR-MCP TEST]` (with trailing space).
- `MockCalendar` with custom id doesn't become default automatically — the
  `MockReminderStore` initializer always creates a "Reminders" list; tests
  can either use it or swap `defaultCalendarId`.

## Progress Log

### 2026-04-11

- Initialized beads DB, imported 20 issues
- Verified core library builds on Linux (Swift 6.1)
- Started scratchpad
- **apple-0ld**: Added `.testTarget(AppleRemindersCoreTests)` to Package.swift,
  created `Tests/AppleRemindersCoreTests/` with `TestHelpers.swift` (env
  toggle + fixture builders) and `SmokeTest.swift`. `swift test` green.
- **apple-6md**: Wrote `TestModeGuardTests.swift` — 8 tests covering all
  5 guard paths (createList, createReminders, updateReminders source,
  updateReminders move-target, deleteReminders) + 2 allow-path tests + 1
  disabled sanity test. All passing.
- **apple-bzg**: Wrote `CRUDLifecycleTests.swift` — 12 tests covering
  list creation, create-with-fields, batch create with partial failures,
  query (plain + searchText), update (title/priority, clear notes+due,
  completion toggle, move between lists), delete (single, batch with
  partial failures). All passing.
- **apple-0y8**: Wrote `InputValidationTests.swift` — 15 tests covering
  empty/whitespace titles, invalid priority on create+update, invalid
  date on create+update, unknown list name (with available lists) / id,
  nonexistent reminder id on update+delete, abbreviated id resolution
  (unique + ambiguous), dueDateIncludesTime guard, alarm offset/date
  validation. All passing.
- **apple-753**: Removed `_seed_mock_data` case from `MCPServer.swift`,
  removed `seedData` method from `MockStore.swift`, removed now-unused
  `store` property from `MCPServer`. Rewrote `test/test-mode.test.ts`
  to cover only what's testable without seeding: block non-test list
  create, block create in default list, allow test-prefixed list, and
  a full CRUD lifecycle inside a test-prefixed list. Deeper guard
  coverage lives in Swift now.

### Final state

- **Swift tests**: 37 passing (SmokeTest + TestModeGuardTests +
  CRUDLifecycleTests + InputValidationTests)
- **TS tests**: 89 passing (no regressions)
- `_seed_mock_data` hack fully removed from the MCP surface.
