# macOS Stress Test Plan — Apple Reminders MCP

**Date:** 2026-04-03
**Purpose:** Comprehensive test plan for validating apple-reminders-mcp against real Apple Reminders on macOS
**Prerequisite:** macOS 14+, Xcode/Swift installed, Reminders permission granted
**Safety:** All write tests use `--test-mode` which restricts writes to `[AR-MCP TEST]` prefixed lists

---

## Prerequisites & Setup

### 1. Build

```bash
swift build -c release
# Verify both binaries exist:
ls -la .build/release/reminders .build/release/apple-reminders-mcp
```

### 2. Grant Permissions

Run a read-only command first to trigger the Reminders permission prompt:

```bash
.build/release/reminders lists
# Click "OK" on the permission dialog
```

### 3. Create a Sacrificial Test List

Manually create a list named `[AR-MCP TEST] Stress` in the Apple Reminders app. This ensures test mode has a writable target.

### 4. Take a Snapshot (Backup)

Before any testing, take a full snapshot as a safety net:

```bash
.build/release/reminders snapshot --pretty
# Note the repo path — you can restore from here if needed
```

---

## Phase 1: Read-Only Safety Tests

These tests verify that read operations never modify data. Run these FIRST.

### 1.1 List All Lists

```bash
.build/release/reminders lists --pretty
```

**Verify:**

- [ ] All your real reminder lists appear
- [ ] Default list is marked `isDefault: true`
- [ ] List IDs are valid UUIDs
- [ ] No lists were created or modified (check Reminders app)

### 1.2 Query Default List

```bash
.build/release/reminders query --pretty
```

**Verify:**

- [ ] Returns incomplete reminders from default list
- [ ] Reminder data matches what you see in the Reminders app
- [ ] No reminders were modified (check last modified dates)

### 1.3 Query All Lists

```bash
.build/release/reminders query --all-lists --status all --detail full --pretty
```

**Verify:**

- [ ] Returns reminders from ALL lists
- [ ] Completed reminders have `completionDate` set
- [ ] `dueDate`, `priority`, `notes`, `url` match the app
- [ ] Alarms and recurrence rules appear for reminders that have them

### 1.4 Query with Filters

```bash
# Search text
.build/release/reminders query --all-lists --search "SOME_KNOWN_WORD" --pretty

# Date range
.build/release/reminders query --all-lists --from "2026-01-01" --to "2026-12-31" --pretty

# Status
.build/release/reminders query --all-lists --status completed --pretty

# Sort
.build/release/reminders query --all-lists --sort dueDate --pretty
.build/release/reminders query --all-lists --sort priority --pretty

# JMESPath
.build/release/reminders query --all-lists --detail full --jmespath "[?priority=='high'].title" --pretty
```

**Verify:**

- [ ] Search returns only matching reminders
- [ ] Date range filtering works correctly
- [ ] Completed/incomplete filtering is accurate
- [ ] Sort order is correct
- [ ] JMESPath returns expected results
- [ ] NO data was modified by any query

### 1.5 Pagination

```bash
.build/release/reminders query --all-lists --per-page 3 --pretty
# Note the endCursor value, then:
.build/release/reminders query --all-lists --per-page 3 --cursor "CURSOR_FROM_ABOVE" --pretty
```

**Verify:**

- [ ] First page returns exactly 3 results
- [ ] Second page returns the next 3 results
- [ ] No overlap between pages
- [ ] `hasNextPage` and `endCursor` are correct

### 1.6 Output Detail Levels

```bash
.build/release/reminders query --all-lists --detail minimal --pretty
.build/release/reminders query --all-lists --detail compact --pretty
.build/release/reminders query --all-lists --detail full --pretty
```

**Verify:**

- [ ] `minimal`: only id, title (plus contextual fields)
- [ ] `compact`: adds notes, dueDate, priority, dates; no nulls
- [ ] `full`: all fields including nulls, shortId added
- [ ] Abbreviated IDs in minimal/compact, full IDs in full

### 1.7 Export (Read-Only)

```bash
.build/release/reminders export --path /tmp/reminders-test-export.json --include-completed --pretty
```

**Verify:**

- [ ] File is created with valid JSON
- [ ] Contains all lists and reminders
- [ ] Stats (completed/incomplete counts) are accurate
- [ ] No data was modified in Reminders app
- [ ] Clean up: `rm /tmp/reminders-test-export.json`

---

## Phase 2: Test Mode Enforcement

These tests verify that test mode properly blocks writes to real lists.

### 2.1 Block Creation in Real List

```bash
.build/release/reminders create "Should fail" --list "Reminders" --test-mode 2>&1
echo "Exit code: $?"
```

**Verify:**

- [ ] Error message: "TEST MODE: Cannot create reminder in list 'Reminders'"
- [ ] Exit code is 1
- [ ] NO reminder was created in the Reminders app

### 2.2 Block List Creation Without Prefix

```bash
.build/release/reminders create-list "Should Fail List" --test-mode 2>&1
echo "Exit code: $?"
```

**Verify:**

- [ ] Error message about test mode prefix requirement
- [ ] No list was created

### 2.3 Allow Test-Prefixed Operations

```bash
.build/release/reminders create-list "[AR-MCP TEST] Phase2" --test-mode --pretty
.build/release/reminders create "Test mode works" --list "[AR-MCP TEST] Phase2" --test-mode --pretty
```

**Verify:**

- [ ] Both succeed
- [ ] List and reminder appear in Reminders app with the test prefix

### 2.4 Block Update of Real Reminder

```bash
# Get a real reminder ID
REAL_ID=$(.build/release/reminders query --detail minimal | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['reminders'][0]['id'] if d['reminders'] else 'NONE')")
echo "Real ID: $REAL_ID"

# Try to update it in test mode
.build/release/reminders update "$REAL_ID" --title "Should fail" --test-mode 2>&1
echo "Exit code: $?"
```

**Verify:**

- [ ] Error mentions test mode restriction
- [ ] Original reminder is UNCHANGED in the app

### 2.5 Block Delete of Real Reminder

```bash
# Same real ID from above
.build/release/reminders delete "$REAL_ID" --test-mode 2>&1
echo "Exit code: $?"
```

**Verify:**

- [ ] Error mentions test mode restriction
- [ ] Reminder still exists in the app

---

## Phase 3: CRUD Lifecycle (Test Mode)

All operations use `--test-mode` for safety.

### 3.1 Create with Full Details

```bash
.build/release/reminders create "Stress Test Reminder" \
  --list "[AR-MCP TEST] Stress" \
  --notes "These are test notes with special chars: <>&\"'" \
  --due "2026-06-15T14:30:00-07:00" \
  --priority high \
  --url "https://example.com/test" \
  --test-mode --pretty
```

**Verify:**

- [ ] Reminder appears in Reminders app under "[AR-MCP TEST] Stress"
- [ ] Title, notes, due date, priority, URL all match
- [ ] Due date shows correct time in local timezone
- [ ] Priority shows as "!!! " in Reminders app (high = 1)

### 3.2 Create with Alarm

```bash
.build/release/reminders create "Alarm Test" \
  --list "[AR-MCP TEST] Stress" \
  --due "2026-06-15T14:30:00-07:00" \
  --alarm-relative 900 \
  --test-mode --pretty
```

**Verify:**

- [ ] Alarm shows "15 minutes before" in Reminders app
- [ ] Query with `--detail full` shows the alarm in output

### 3.3 Create with Recurrence

```bash
.build/release/reminders create "Weekly Review" \
  --list "[AR-MCP TEST] Stress" \
  --due "2026-06-15T10:00:00-07:00" \
  --recurrence weekly \
  --test-mode --pretty
```

**Verify:**

- [ ] Recurrence shows "Every Week" in Reminders app
- [ ] Query with `--detail full` shows recurrenceRules

### 3.4 Update Operations

```bash
# Get the ID of a test reminder
TEST_ID=$(.build/release/reminders query --list "[AR-MCP TEST] Stress" --detail minimal --test-mode | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['reminders'][0]['id'] if d['reminders'] else 'NONE')")

# Update title
.build/release/reminders update "$TEST_ID" --title "Updated Title" --test-mode --pretty

# Update notes
.build/release/reminders update "$TEST_ID" --notes "Updated notes" --test-mode --pretty

# Change priority
.build/release/reminders update "$TEST_ID" --priority medium --test-mode --pretty

# Clear notes
.build/release/reminders update "$TEST_ID" --clear-notes --test-mode --pretty

# Clear due date
.build/release/reminders update "$TEST_ID" --clear-due-date --test-mode --pretty
```

**Verify at each step:**

- [ ] Only the specified field changed
- [ ] Other fields remain intact
- [ ] Changes reflected in Reminders app
- [ ] `lastModifiedDate` updated
- [ ] Cleared fields show as null in `--detail full`

### 3.5 Complete/Incomplete Cycle

```bash
# Mark complete
.build/release/reminders update "$TEST_ID" --complete --test-mode --pretty

# Verify it shows as completed
.build/release/reminders query --list "[AR-MCP TEST] Stress" --status completed --test-mode --pretty

# Mark incomplete
.build/release/reminders update "$TEST_ID" --incomplete --test-mode --pretty

# Verify it's back
.build/release/reminders query --list "[AR-MCP TEST] Stress" --status incomplete --test-mode --pretty
```

**Verify:**

- [ ] Completing sets `completionDate` and `isCompleted: true`
- [ ] Uncompleting clears `completionDate` and sets `isCompleted: false`
- [ ] Status filters correctly reflect the change
- [ ] Reminders app shows/hides the checkmark accordingly

### 3.6 Move Between Lists

```bash
# Create a second test list
.build/release/reminders create-list "[AR-MCP TEST] Target" --test-mode --pretty

# Move reminder
.build/release/reminders update "$TEST_ID" --list "[AR-MCP TEST] Target" --test-mode --pretty

# Query both lists
.build/release/reminders query --list "[AR-MCP TEST] Stress" --test-mode --pretty
.build/release/reminders query --list "[AR-MCP TEST] Target" --test-mode --pretty
```

**Verify:**

- [ ] Reminder no longer appears in source list
- [ ] Reminder appears in target list
- [ ] All other fields preserved after move
- [ ] Reminders app shows the move

### 3.7 Delete Operations

```bash
# Create some reminders to delete
.build/release/reminders create "Delete Me 1" --list "[AR-MCP TEST] Stress" --test-mode --pretty
.build/release/reminders create "Delete Me 2" --list "[AR-MCP TEST] Stress" --test-mode --pretty

# Get their IDs
IDS=$(.build/release/reminders query --list "[AR-MCP TEST] Stress" --search "Delete Me" --detail minimal --test-mode | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(r['id'] for r in d['reminders']))")

# Batch delete
.build/release/reminders delete $IDS --test-mode --pretty

# Verify they're gone
.build/release/reminders query --list "[AR-MCP TEST] Stress" --search "Delete Me" --test-mode --pretty
```

**Verify:**

- [ ] Both reminders deleted
- [ ] No longer appear in queries
- [ ] No longer appear in Reminders app
- [ ] Other reminders in the list are unaffected

---

## Phase 4: MCP Server Tests (Real EventKit)

Test the MCP server with real data via JSON-RPC.

### 4.1 MCP Server Lifecycle

```bash
# Start MCP server in test mode (use Ctrl+C to stop)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_lists","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"query_reminders","arguments":{"list":{"all":true},"outputDetail":"minimal","perPage":5}}}' | .build/release/reminders mcp --test-mode 2>/tmp/mcp-test-stderr.log
```

**Verify:**

- [ ] Initialize returns server info
- [ ] tools/list returns all 10 tools
- [ ] get_lists returns real lists
- [ ] query_reminders returns real reminders with abbreviated IDs

### 4.2 MCP CRUD with Test Mode

```bash
cat <<'JSONRPC' | .build/release/reminders mcp --test-mode 2>/tmp/mcp-crud-stderr.log
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_reminders","arguments":{"reminders":[{"title":"MCP Test 1","list":{"name":"[AR-MCP TEST] Stress"}},{"title":"MCP Test 2","list":{"name":"[AR-MCP TEST] Stress"},"priority":"high","notes":"Test notes"}]}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_reminders","arguments":{"list":{"name":"[AR-MCP TEST] Stress"},"searchText":"MCP Test"}}}
JSONRPC
```

**Verify:**

- [ ] Both reminders created in test list
- [ ] Query returns them with correct details
- [ ] Reminders appear in the app

### 4.3 MCP Mutation Blocked in Real List

```bash
cat <<'JSONRPC' | .build/release/reminders mcp --test-mode 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_reminders","arguments":{"reminders":[{"title":"Should Fail","list":{"name":"Reminders"}}]}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_list","arguments":{"name":"Should Fail List"}}}
JSONRPC
```

**Verify:**

- [ ] Create reminder returns `failed` array with test mode error
- [ ] Create list returns `isError: true` with test mode error
- [ ] NO data changed in Reminders app

---

## Phase 5: Existing Test Suite (Real Mode)

Run the automated tests against real EventKit.

### 5.1 Run Tests in Mock Mode (Baseline)

```bash
bun test
```

**Expected:** 88+ pass (2 known stale assertions may fail)

### 5.2 Run Tests in Real Mode (Test Mode Enforced)

Edit `test/mcp-client.ts` to use real mode with test mode:

```bash
AR_MCP_TEST_MODE=1 bun test
```

**Verify:**

- [ ] Tests pass (they create `[AR-MCP TEST]` prefixed lists)
- [ ] Test lists appear in Reminders app during test
- [ ] Run cleanup after: `bun run test:cleanup`
- [ ] Test lists are removed

---

## Phase 6: Edge Cases & Stress Tests

### 6.1 Unicode and Special Characters

```bash
.build/release/reminders create "日本語テスト 🎉 émojis" \
  --list "[AR-MCP TEST] Stress" \
  --notes "Notes with <html> & \"quotes\" and 'apostrophes'" \
  --test-mode --pretty
```

**Verify:**

- [ ] Title and notes display correctly in Reminders app
- [ ] Query returns them correctly
- [ ] Round-trip preserves all characters

### 6.2 Very Long Content

```bash
LONG_TITLE=$(python3 -c "print('A' * 500)")
.build/release/reminders create "$LONG_TITLE" \
  --list "[AR-MCP TEST] Stress" \
  --notes "$(python3 -c "print('B' * 5000)")" \
  --test-mode --pretty
```

**Verify:**

- [ ] Creates successfully (or EventKit truncates gracefully)
- [ ] No crash or data corruption

### 6.3 Rapid Successive Operations

```bash
for i in $(seq 1 50); do
  .build/release/reminders create "Rapid $i" --list "[AR-MCP TEST] Stress" --test-mode 2>/dev/null &
done
wait
.build/release/reminders query --list "[AR-MCP TEST] Stress" --search "Rapid" --test-mode --pretty | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Created: {d[\"totalCount\"]} of 50 expected')"
```

**Verify:**

- [ ] All 50 reminders created (or partial with clear error messages)
- [ ] No crashes or hangs
- [ ] No duplicate or corrupted reminders
- [ ] Reminders app shows all created reminders

### 6.4 Abbreviated ID Resolution

```bash
# Get a full ID
FULL_ID=$(.build/release/reminders query --list "[AR-MCP TEST] Stress" --detail full --test-mode | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['reminders'][0]['id'] if d['reminders'] else 'NONE')")
SHORT_ID=${FULL_ID:0:7}

echo "Full ID: $FULL_ID"
echo "Short ID: $SHORT_ID"

# Update using abbreviated ID
.build/release/reminders update "$SHORT_ID" --title "Updated via short ID" --test-mode --pretty
```

**Verify:**

- [ ] Abbreviated ID resolves correctly
- [ ] Update succeeds
- [ ] Correct reminder was updated (not a different one)

### 6.5 Batch Partial Failure

```bash
cat <<'JSONRPC' | .build/release/reminders mcp --test-mode 2>/dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"update_reminders","arguments":{"reminders":[{"id":"nonexistent-id","title":"Should Fail"},{"id":"also-nonexistent","completed":true}]}}}
JSONRPC
```

**Verify:**

- [ ] Response contains `failed` array with both IDs
- [ ] `updated` array is empty
- [ ] No data was modified

### 6.6 Concurrent MCP Sessions

Open two terminals and run:

**Terminal 1:**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"session1","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_reminders","arguments":{"reminders":[{"title":"Session 1 Reminder","list":{"name":"[AR-MCP TEST] Stress"}}]}}}' | .build/release/reminders mcp --test-mode
```

**Terminal 2 (simultaneously):**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"session2","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_reminders","arguments":{"reminders":[{"title":"Session 2 Reminder","list":{"name":"[AR-MCP TEST] Stress"}}]}}}' | .build/release/reminders mcp --test-mode
```

**Verify:**

- [ ] Both reminders created successfully
- [ ] No data corruption
- [ ] Both sessions return correct responses

---

## Phase 7: Snapshot System

### 7.1 Take Snapshot

```bash
.build/release/reminders snapshot --pretty
```

**Verify:**

- [ ] Snapshot completes successfully
- [ ] Reports reminder and list counts
- [ ] Git repo created at `~/.config/apple-reminders-data/`

### 7.2 Snapshot Status

```bash
.build/release/reminders snapshot status --pretty
```

**Verify:**

- [ ] Shows correct repo path, commit count, last snapshot date
- [ ] Reminder file count matches your actual reminder count

### 7.3 Snapshot Diff After Changes

```bash
# Make a change
.build/release/reminders create "Diff Test" --list "[AR-MCP TEST] Stress" --test-mode

# Take another snapshot
.build/release/reminders snapshot --pretty

# Check diff
.build/release/reminders snapshot diff --pretty
```

**Verify:**

- [ ] Diff shows the new reminder file added
- [ ] Commit message includes timestamp and counts

### 7.4 Snapshot Data Integrity

```bash
# Check that individual reminder files are valid JSON
REPO=$(python3 -c "import os; print(os.path.expanduser('~/.config/apple-reminders-data'))")
for f in "$REPO"/data/id/*.json; do
  python3 -c "import json; json.load(open('$f'))" 2>&1 && echo "OK: $f" || echo "FAIL: $f"
done | tail -5
echo "Total files: $(ls "$REPO"/data/id/*.json 2>/dev/null | wc -l)"
```

**Verify:**

- [ ] All JSON files are valid
- [ ] Each file represents one reminder
- [ ] `lists.json` contains all lists

---

## Phase 8: Audit Logging

### 8.1 Verify Audit Log Exists

```bash
.build/release/reminders audit --pretty
```

**Verify:**

- [ ] Shows recent mutation entries
- [ ] Each entry has timestamp, action, args, result, context
- [ ] Updates/deletes include beforeState

### 8.2 Verify Audit Log Files

```bash
.build/release/reminders audit --files --pretty
```

**Verify:**

- [ ] Log files exist in `~/.config/apple-reminders-tools/logs/`
- [ ] Today's file contains entries from this testing session

### 8.3 Audit Log Content Accuracy

```bash
# Create a reminder and check the audit log
.build/release/reminders create "Audit Check" --list "[AR-MCP TEST] Stress" --test-mode

# Check the last audit entry
.build/release/reminders audit --days 1 --pretty | python3 -c "
import json, sys
lines = json.load(sys.stdin)
if lines:
    last = json.loads(lines[-1]) if isinstance(lines[-1], str) else lines[-1]
    print(json.dumps(last, indent=2))
"
```

**Verify:**

- [ ] Audit entry matches the create operation
- [ ] `action` is "create_reminder"
- [ ] `args` contain the title
- [ ] `result` is "success"
- [ ] `context.source` is "cli"

---

## Phase 9: Auto-Snapshot via MCP

### 9.1 MCP with Snapshot Enabled

```bash
export AR_MCP_SNAPSHOT_ENABLED=1
export AR_MCP_SNAPSHOT_REPO=~/.config/apple-reminders-data

cat <<'JSONRPC' | .build/release/reminders mcp --test-mode 2>/tmp/mcp-snapshot.log
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"snapshot-test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_reminders","arguments":{"reminders":[{"title":"Snapshot Trigger","list":{"name":"[AR-MCP TEST] Stress"}}]}}}
JSONRPC

echo "=== Stderr (auto-snapshot logs) ==="
cat /tmp/mcp-snapshot.log
```

**Verify:**

- [ ] Stderr shows "Auto-snapshot (session start)" message
- [ ] Stderr shows auto-snapshot after the create operation
- [ ] Snapshot repo has new commits

---

## Phase 10: Cleanup

### 10.1 Remove Test Lists

```bash
# Use the cleanup utility
bun run test:cleanup
```

Or manually delete `[AR-MCP TEST]` prefixed lists in the Reminders app.

### 10.2 Verify No Side Effects

```bash
# Compare current state to the initial snapshot
.build/release/reminders snapshot diff --pretty
```

**Verify:**

- [ ] Only test-list-related changes appear
- [ ] No changes to your real reminders
- [ ] Take a final snapshot to confirm clean state

---

## Checklist Summary

| Phase                    | Tests         | Priority |
| ------------------------ | ------------- | -------- |
| 1. Read-Only Safety      | 7 test groups | CRITICAL |
| 2. Test Mode Enforcement | 5 test groups | CRITICAL |
| 3. CRUD Lifecycle        | 7 test groups | HIGH     |
| 4. MCP Server            | 3 test groups | HIGH     |
| 5. Existing Test Suite   | 2 test groups | HIGH     |
| 6. Edge Cases & Stress   | 6 test groups | MEDIUM   |
| 7. Snapshot System       | 4 test groups | MEDIUM   |
| 8. Audit Logging         | 3 test groups | LOW      |
| 9. Auto-Snapshot         | 1 test group  | LOW      |
| 10. Cleanup              | 2 test groups | CRITICAL |

**Total estimated time:** 60-90 minutes for thorough execution

---

## Known Issues to Watch For

1. **Abbreviated ID collisions**: If you have thousands of reminders, short IDs might be ambiguous
2. **Midnight due dates**: Reminders at exactly midnight may report `dueDateIncludesTime` incorrectly
3. **iCloud sync delays**: Changes made via the tool may take a moment to appear in Reminders on other devices
4. **EventKit access**: First run requires Full Disk Access or Reminders permission
5. **Batch partial failures**: If one item in a batch fails, earlier items are already committed
