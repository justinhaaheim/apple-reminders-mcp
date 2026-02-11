# Testing Instructions for New Apple Reminders MCP API

This document provides detailed instructions for validating the new 6-tool API implementation and mock mode support.

## Prerequisites

- macOS (for building and real EventKit testing)
- Bun runtime installed (`brew install bun`)
- Reminders app permission granted to Terminal/IDE

## Quick Validation (5 minutes)

Run these commands to quickly verify everything works:

```bash
# 1. Build the Swift binary
bun run build

# 2. Run all tests in mock mode (default)
bun run test

# 3. Check code formatting
bun run signal
```

If all three pass, the implementation is working correctly.

---

## Detailed Test Plan

### Phase 1: Build Verification

```bash
# Clean build
rm -rf .build
bun run build
```

**Expected output:**

- Build completes without errors
- Binary created at `.build/release/apple-reminders-mcp`

**If build fails:**

- Check that Xcode command line tools are installed: `xcode-select --install`
- Verify Swift version: `swift --version` (should be 5.9+)
- Check Package.swift has JMESPath dependency

### Phase 2: Automated Tests (Mock Mode)

```bash
bun run test
```

**Expected output:**

- All tests pass
- Tests run quickly (mock mode uses in-memory storage)

**Test files being executed:**
| File | What it tests |
|------|---------------|
| `readonly.test.ts` | `get_lists`, `query_reminders`, tool listing |
| `crud.test.ts` | Create, read, update, delete operations |
| `batch.test.ts` | Batch operations, partial failure handling |
| `search.test.ts` | JMESPath queries, filtering, sorting |
| `test-mode.test.ts` | Test mode restrictions (blocks non-test lists) |

### Phase 3: Interactive Testing

Use the interactive test script to manually exercise the MCP protocol:

```bash
./test/interactive.sh
```

This starts the server and lets you send raw JSON-RPC requests.

**Test 1: Initialize and list tools**

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```

**Expected:** Should list exactly 6 tools:

- `query_reminders`
- `get_lists`
- `create_list`
- `create_reminders`
- `update_reminders`
- `delete_reminders`

**Test 2: Get lists**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {"name": "get_lists", "arguments": {}}
}
```

**Expected:** Returns array of lists, each with `id`, `name`, `isDefault`. Exactly one should have `isDefault: true`.

**Test 3: Query reminders**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {"name": "query_reminders", "arguments": {}}
}
```

**Expected:** Returns array of incomplete reminders from default list.

**Test 4: Create reminder**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "create_reminders",
    "arguments": {"reminders": [{"title": "Test from interactive"}]}
  }
}
```

**Expected:** Returns array with created reminder including `id`, `title`, `listName`, etc.

### Phase 4: Real EventKit Testing (Optional)

To test with actual Apple Reminders:

```bash
# Run tests against real EventKit (requires macOS + Reminders permission)
AR_MCP_TEST_MODE=1 bun test
```

Or modify a test file temporarily:

```typescript
// Change this:
client = await MCPClient.create();

// To this:
client = await MCPClient.create({mockMode: false});
```

**Important:** Real mode with test mode enabled will:

- Only allow writes to lists prefixed with `[AR-MCP TEST]`
- Create actual reminders in Apple Reminders app
- You can see created test lists in Reminders.app

**Cleanup after real testing:**

```bash
bun run test:cleanup
```

This will prompt to delete any leftover `[AR-MCP TEST]` lists.

---

## Specific Feature Validation

### 1. JMESPath Queries

Test that JMESPath filtering works:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "query_reminders",
    "arguments": {"query": "[?priority == 'high']"}
  }
}
```

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "query_reminders",
    "arguments": {"query": "[?contains(title, 'test')]"}
  }
}
```

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "query_reminders",
    "arguments": {"query": "[*].{name: title, due: dueDate}"}
  }
}
```

### 2. List Selector Patterns

Test all three list selector patterns:

```json
// By name (case-insensitive)
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"query_reminders","arguments":{"list":{"name":"Reminders"}}}}

// By ID
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"query_reminders","arguments":{"list":{"id":"x-apple-calendar://..."}}}}

// All lists
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_reminders","arguments":{"list":{"all":true}}}}
```

### 3. Priority Values

Verify priority is string-based:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_reminders",
    "arguments": {"reminders": [{"title": "High priority", "priority": "high"}]}
  }
}
```

**Expected:** Created reminder has `"priority": "high"` (not a number).

### 4. Date Format

Verify dates use timezone offset:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_reminders",
    "arguments": {
      "reminders": [
        {"title": "With due date", "dueDate": "2026-01-20T10:00:00-05:00"}
      ]
    }
  }
}
```

**Expected:** Returned reminder has `dueDate` like `"2026-01-20T10:00:00-05:00"` (with timezone offset, not `Z`).

### 5. Batch Operations with Partial Failure

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_reminders",
    "arguments": {
      "reminders": [
        {"title": "Good one", "list": {"name": "Reminders"}},
        {"title": "Bad one", "list": {"name": "NonexistentList"}}
      ]
    }
  }
}
```

**Expected:** Response has both `created` (1 item) and `failed` (1 item with error).

### 6. Completion Logic

```json
// Complete a reminder
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"update_reminders","arguments":{"reminders":[{"id":"<reminder-id>","completed":true}]}}}

// Uncomplete a reminder
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"update_reminders","arguments":{"reminders":[{"id":"<reminder-id>","completed":false}]}}}
```

---

## Test Mode Validation

### Verify test mode blocks non-test operations

Start server with test mode:

```bash
AR_MCP_TEST_MODE=1 .build/release/apple-reminders-mcp
```

Then try to create a list without the test prefix:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {"name": "create_list", "arguments": {"name": "Regular List"}}
}
```

**Expected:** Error containing "TEST MODE" and "[AR-MCP TEST]".

Try with test prefix:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "create_list",
    "arguments": {"name": "[AR-MCP TEST] Allowed List"}
  }
}
```

**Expected:** Success - list created.

---

## Mock Mode Validation

### Verify mock mode isolation

```bash
# Start server in mock mode
AR_MCP_MOCK_MODE=1 .build/release/apple-reminders-mcp
```

1. Create some reminders
2. Restart the server
3. Query reminders

**Expected:** After restart, only the default "Reminders" list exists (mock data doesn't persist).

### Verify mock mode has default list

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {"name": "get_lists", "arguments": {}}
}
```

**Expected:** Returns one list named "Reminders" with `isDefault: true`.

---

## Error Handling Validation

### Invalid JMESPath

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "query_reminders",
    "arguments": {"query": "[?invalid syntax"}
  }
}
```

**Expected:** Error with `isError: true` mentioning "Invalid JMESPath".

### Missing required fields

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {"name": "create_reminders", "arguments": {"reminders": [{}]}}
}
```

**Expected:** Error mentioning "title".

### Invalid list selector

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "query_reminders",
    "arguments": {"list": {"name": "X", "id": "Y"}}
  }
}
```

**Expected:** Error about specifying exactly one of name/id/all.

---

## Checklist Summary

- [ ] `bun run build` succeeds
- [ ] `bun run test` all tests pass
- [ ] `bun run signal` formatting clean
- [ ] `tools/list` returns exactly 6 tools
- [ ] `get_lists` returns lists with `isDefault` flag
- [ ] `query_reminders` works with no arguments (default list, incomplete)
- [ ] `query_reminders` works with list selector (name, id, all)
- [ ] `query_reminders` works with JMESPath queries
- [ ] `query_reminders` works with status filter (incomplete, completed, all)
- [ ] `query_reminders` works with sortBy (newest, oldest, priority, dueDate)
- [ ] `create_reminders` creates single reminder
- [ ] `create_reminders` creates batch of reminders
- [ ] `create_reminders` handles partial failures correctly
- [ ] `update_reminders` updates reminder properties
- [ ] `update_reminders` marks reminders complete/incomplete
- [ ] `update_reminders` handles non-existent IDs
- [ ] `delete_reminders` deletes reminders
- [ ] `delete_reminders` handles non-existent IDs
- [ ] Priority values are strings ("none", "low", "medium", "high")
- [ ] Dates have timezone offset format (+HH:MM)
- [ ] Test mode blocks writes to non-test lists
- [ ] Mock mode uses in-memory storage
- [ ] Mock mode starts with default "Reminders" list

---

## Troubleshooting

### Build fails with "no such module 'JMESPath'"

```bash
swift package resolve
swift build
```

### Tests timeout

Increase timeout in test or check if server is hanging:

```bash
# Check stderr for server logs
AR_MCP_MOCK_MODE=1 .build/release/apple-reminders-mcp 2>&1
```

### Permission denied for Reminders

1. Open System Preferences → Privacy & Security → Reminders
2. Add Terminal (or your IDE) to the allowed list
3. Restart Terminal

### Test lists not being cleaned up

```bash
bun run test:cleanup
```

Or manually delete `[AR-MCP TEST]` lists in Reminders.app.
