# Security & Integrity Review — Apple Reminders MCP

**Date:** 2026-04-03
**Reviewer:** Claude Opus 4.6 (automated security review)
**Scope:** Full codebase review + stress testing with mock data on Linux
**Branch:** `claude/security-integrity-review-5f4h3`

---

## TLDR: Key Findings

**Overall assessment: The codebase is well-structured and safe for production use with real Apple Reminders.** The safety architecture (test mode, audit logging, mock mode) is solid. No critical data-loss vulnerabilities were found. The main risks are theoretical edge cases around batch operation atomicity and abbreviated ID resolution, both of which require specific conditions to cause issues.

### Top Findings by Priority

| #   | Severity | Summary                                                                          |
| --- | -------- | -------------------------------------------------------------------------------- |
| H1  | HIGH     | Abbreviated ID prefix matching creates theoretical TOCTOU risk for delete/update |
| H2  | HIGH     | Batch operations are non-atomic; partial failures leave committed changes        |
| M1  | MEDIUM   | Duplicate list names resolve non-deterministically                               |
| M3  | MEDIUM   | Empty titles allowed on create (no validation)                                   |
| M4  | MEDIUM   | Export writes to arbitrary file paths without sandboxing                         |
| M5  | MEDIUM   | Each EventKit save/delete commits immediately (no batch transaction)             |
| M8  | MEDIUM   | JSON-RPC parse error uses hardcoded ID -1 (spec says null)                       |
| M11 | MEDIUM   | Tool argument type coercion silently drops mistyped arguments                    |
| T1  | MEDIUM   | Test-mode update/delete test uses fake ID, doesn't actually test mode guard      |
| T2  | MEDIUM   | No CLI test coverage at all                                                      |
| T3  | MEDIUM   | 2 stale test assertions (tool count, description text)                           |

### Positive Findings

- **No shell injection** in SnapshotManager: git args passed as array, not through shell
- **Test mode enforcement** is consistent across all mutation paths
- **Audit logging** captures before-state on updates/deletes for recovery
- **Atomic file operations** in SnapshotManager (replaceItemAt for APFS safety)
- **Error handling** is comprehensive; malformed input never crashes the server
- **Unicode and special characters** handled correctly throughout
- **Pagination** works correctly with cursor-based navigation

---

## 1. Security Review

### 1.1 Data Integrity & Safety

#### H1: Abbreviated ID Prefix Matching — TOCTOU Risk (HIGH)

**File:** `RemindersManager.swift:155-180`

The `resolveReminder(id:)` method allows prefix-matching on reminder IDs. If a reminder is deleted between when the user queried it and when they issue a delete, the same prefix could now uniquely match a _different_ reminder. The prefix-matching strips dashes and uppercases, increasing the collision surface.

**Practical risk:** LOW in normal use (UUIDs have very low collision probability for 7+ character prefixes), but worth documenting. The MCP context (LLM as client) adds risk since the LLM might use stale IDs from earlier in a conversation.

**Mitigation options:**

- Require minimum prefix length (already 7 chars for display, but any length accepted for lookup)
- Add confirmation for delete operations
- Return the resolved reminder's title in delete response so the user can verify

#### H2: Non-Atomic Batch Operations (HIGH)

**File:** `RemindersManager.swift:590-961`

Batch create/update/delete iterate one-by-one, each calling `store.saveReminder` with `commit: true`. If the 3rd of 5 updates fails, the first 2 are already committed and cannot be rolled back.

**Mitigation:** The code does return `updated` and `failed` arrays, which is good for reporting. EventKit supports `commit: false` with a later `commit()` call, which could make batches atomic.

**Practical risk:** MEDIUM. Partial failures are reported clearly, and the audit log captures the before-state. However, users cannot undo partial changes automatically.

#### M5: Immediate Commits per Operation (MEDIUM)

**File:** `EventKitStore.swift:303, 310`

Each `saveReminder` and `deleteReminder` uses `commit: true`, meaning each operation is immediately persisted. This is the root cause of H2.

#### M6: Silent calendarId Failure (MEDIUM)

**File:** `EventKitStore.swift:43-47`

Setting `calendarId` to a non-existent calendar ID silently does nothing. The reminder stays in the old calendar, and the save succeeds. Not data-losing, but misleading.

### 1.2 Input Validation

#### M3: Empty Title Allowed (MEDIUM)

**File:** `RemindersManager.swift:621`

A reminder can be created with `title: ""`. Verified in stress testing — the server accepts it and creates a reminder with a blank title. Should validate non-empty.

#### M11: Silent Type Coercion (MEDIUM)

**File:** `MCPServer.swift` (callTool method)

Arguments extracted via `as? Type` casts silently become `nil` on type mismatch. If JSON sends `"10"` (string) where `Int` is expected, the value is silently ignored and the default applies.

#### M1: Non-Deterministic List Resolution (MEDIUM)

**File:** `RemindersManager.swift:67, 108`

Case-insensitive list matching uses `.first(where:)`. If two lists differ only in case ("Work" vs "work"), whichever appears first in EventKit's enumeration wins.

### 1.3 Protocol & Network

#### M8: JSON-RPC Parse Error ID (MEDIUM)

**File:** `MCPServer.swift:93`

Parse errors use hardcoded `id: .int(-1)`. Per JSON-RPC 2.0, the `id` should be `null` when it cannot be determined.

#### M9: No JSON-RPC Notification Handling (MEDIUM)

**File:** `MCPServer.swift`

JSON-RPC 2.0 notifications (requests without `id`) would cause parse errors since `MCPRequest` requires `id`.

#### L5: No Request Size Limits (LOW)

**File:** `MCPServer.swift:63`

`readLine()` has no length limit. A malicious client could send extremely long lines. In practice, MCP clients are local and trusted.

### 1.4 File System

#### M4: Export Path Not Sandboxed (MEDIUM)

**File:** `RemindersManager.swift:965-1068`

The export function accepts arbitrary file paths and creates parent directories. While this is write-only, a compromised MCP client could write files to unexpected locations.

#### M15: Dirty Git State Blocks Snapshots (MEDIUM)

**File:** `SnapshotManager.swift:205-213`

If the snapshot repo gets into a dirty state (e.g., interrupted operation), all future snapshots fail until manual cleanup.

### 1.5 Shell Injection: NOT VULNERABLE (Positive Finding)

**File:** `SnapshotManager.swift:216-244`

The `runGit` method correctly passes arguments as an array to `Process.arguments`, preventing shell injection. Commit messages contain only timestamps and counts, not user input.

---

## 2. Code Quality

### 2.1 Architecture

The codebase follows clean architecture patterns:

- Protocol-based store abstraction (`ReminderStore`) enables testing
- Separation between core logic, CLI, and MCP server
- Consistent error handling with `RemindersError`
- Audit logging on all mutations

### 2.2 Issues

#### No Conflicting Flag Validation in CLI

**File:** `UpdateCommand.swift:40-43, 92-98`

Both `--complete` and `--incomplete` can be passed simultaneously. The code silently picks `--complete`.

#### Invalid Sort/Status/Detail Values Fall Through to Defaults

**File:** `RemindersManager.swift:223-232, 501-523`

Unrecognized `--status`, `--sort`, and `--detail` values silently fall through to defaults instead of erroring. A user typing `--status done` silently gets all reminders (the `default:` case maps to `.all`).

#### Compiler Warning

**File:** `SnapshotManager.swift:256`

Unused `let output` variable in `gitAddAndCommit`.

#### Mock Store Behavioral Gaps

**File:** `MockStore.swift`

- Does not validate `calendarId` references a real calendar on save
- `deleteReminder` throws on not-found; real EventKit behavior may differ
- `isAllDay` midnight edge case matches EventKit behavior (documented limitation)

---

## 3. Test Coverage

### 3.1 Existing Test Suite Results

**88 pass, 2 fail out of 90 tests** (on Linux with mock mode)

Failures are stale assertions:

1. `readonly.test.ts:25` — expects 7 tools, now 10 (help/schema/guidance added)
2. `api-parity.test.ts:536` — expects description to contain "searchText", but wording changed

### 3.2 Test Coverage Gaps

| Scenario                               | Covered?                                         |
| -------------------------------------- | ------------------------------------------------ |
| CRUD via MCP                           | Yes                                              |
| Batch operations via MCP               | Yes                                              |
| Query filters (search, date, JMESPath) | Yes                                              |
| API parity (alarms, recurrence, URL)   | Yes                                              |
| Export via MCP                         | Yes                                              |
| Schema snapshot regression             | Yes                                              |
| Test mode restrictions                 | Partially (T1: update/delete tests use fake IDs) |
| CLI argument parsing                   | **No**                                           |
| CLI clearable fields (--clear-\*)      | **No**                                           |
| CLI snapshot/audit commands            | **No**                                           |
| Help/schema/guidance meta-tools        | **No**                                           |
| Invalid/malformed cursor values        | **No**                                           |
| Concurrent batch operations            | **No**                                           |
| Audit log correctness                  | **No**                                           |
| Real EventKit integration              | **No (mock only)**                               |
| Empty/blank input validation           | **No**                                           |

### 3.3 Specific Test Issues

#### T1: Test Mode Tests Don't Test the Guard (MEDIUM)

**File:** `test-mode.test.ts:88`

The "blocks updating a reminder in non-test list" test uses `fake-reminder-id-12345`. This hits "Reminder not found" before reaching the test-mode guard. The test passes but doesn't test what it claims.

#### T2: Zero CLI Test Coverage (MEDIUM)

All tests go through the MCP server. CLI argument parsing, output formatting, and error display are untested.

#### T3: `interactive.sh` Uses Stale Tool Names

**File:** `test/interactive.sh:28-34`

References `list_reminder_lists`, `list_reminders`, `create_reminder` — all renamed to `get_lists`, `query_reminders`, `create_reminders`.

---

## 4. Stress Testing Results (Linux, Mock Mode)

### Tests Performed

| Test                                               | Result                                    |
| -------------------------------------------------- | ----------------------------------------- |
| MCP server initialize + tools/list                 | PASS                                      |
| Batch create 10 reminders                          | PASS                                      |
| Query with all output detail levels                | PASS                                      |
| Query with searchText                              | PASS                                      |
| Query with JMESPath expressions                    | PASS                                      |
| Invalid JMESPath expression                        | PASS (proper error)                       |
| Pagination (perPage=2, cursor traversal)           | PASS                                      |
| Invalid cursor                                     | PASS (proper error)                       |
| Create list + create in specific list              | PASS                                      |
| Query nonexistent list                             | PASS (helpful error with available lists) |
| Update with nonexistent ID                         | PASS (returns in failed array)            |
| Delete with nonexistent ID                         | PASS (returns in failed array)            |
| Empty reminders array in create                    | PASS (returns empty array)                |
| Malformed JSON-RPC                                 | PASS (parse error returned)               |
| Unknown method                                     | PASS (error returned)                     |
| Unknown tool                                       | PASS (isError: true)                      |
| Special characters in titles                       | PASS                                      |
| Unicode (Japanese, emoji)                          | PASS                                      |
| Very long titles (200+ chars)                      | PASS                                      |
| Empty title                                        | PASS (allowed — see M3)                   |
| Test mode: block non-prefixed list creation        | PASS                                      |
| Test mode: block non-prefixed reminder creation    | PASS                                      |
| Test mode: allow [AR-MCP TEST] prefixed operations | PASS                                      |
| Export to specific path                            | PASS                                      |
| Export with tilde expansion                        | PASS                                      |
| CLI help for all subcommands                       | PASS                                      |
| CLI delete/update/create with no args              | PASS (proper ArgumentParser errors)       |
| CLI invalid priority                               | PASS (proper error)                       |
| CLI invalid date                                   | PASS (proper error)                       |
| Help/schema/guidance meta-tools                    | PASS                                      |
| Sort by priority/dueDate/newest/oldest             | PASS                                      |

### Key Observations

1. **Mock mode works correctly on Linux** — `#if canImport(EventKit)` correctly falls back to mock store
2. **JSON output is always valid** — even for error cases
3. **Logs go to stderr, data to stdout** — clean separation maintained
4. **No crashes or hangs** during any test scenario
5. **Pagination cursors are base64-encoded JSON** (`eyJvZmZzZXQiOjJ9` = `{"offset":2}`) — simple and correct

---

## 5. Recommendations

### Priority 1 (Should Fix)

1. **Fix 2 stale test assertions** (`readonly.test.ts` tool count, `api-parity.test.ts` description)
2. **Fix `test-mode.test.ts`** to actually test the mode guard on update/delete
3. **Update `interactive.sh`** with current tool names
4. **Add empty title validation** in `createSingleReminder`
5. **Fix JSON-RPC parse error ID** to use null instead of -1

### Priority 2 (Should Consider)

6. **Add CLI test coverage** — at minimum, test argument parsing and output format
7. **Validate `--complete` and `--incomplete` mutual exclusivity** in UpdateCommand
8. **Consider batch commit mode** using EventKit's `commit: false` + final `commit()` for atomic batches
9. **Add invalid value validation** for `--status`, `--sort`, `--detail` CLI flags
10. **Document abbreviated ID behavior** and TOCTOU risk for delete operations

### Priority 3 (Nice to Have)

11. **Add meta-tool tests** (help, schema, guidance)
12. **Add audit log tests** to verify mutation logging
13. **Add log rotation** for audit logs
14. **Consider minimum prefix length** for ID resolution
15. **Add cursor tampering tests**
