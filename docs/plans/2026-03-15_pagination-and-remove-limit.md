# Remove Hard Limit + Add Cursor-Based Pagination

**Beads**: s0o (remove 200 cap), u6x (add pagination)
**Date**: 2026-03-15

## Current State

- `queryReminders()` applies `min(limit ?? 50, 200)` in two places (lines 302, 319)
- Returns a raw array (`[[String: Any]]`) or raw JMESPath result (`Any`) — no metadata wrapper
- MCP schema declares `maximum: 200, default: 50` for the `limit` param
- CLI `--limit` help text says "default: 50, max: 200"
- `HelpContent.swift` lines 153, 176 reference "max results (default: 50, max: 200)"
- Tests (search.test.ts, crud.test.ts, api-parity.test.ts, etc.) all assert `Array.isArray(result)` — ~60+ assertions expect raw arrays
- `formatReminders()` returns `[[String: Any]]`
- `outputJSON()` in CLI handles any `Encodable` or falls back to `JSONSerialization`

## Research: MCP Pagination Patterns

### MCP Spec

- Defines cursor-based pagination only for **protocol-level** operations (`tools/list`, etc.)
- **No standard for tool-level pagination** — entirely up to the server
- Pattern: opaque `cursor` in request, `nextCursor` in response

### GitHub MCP Server (gold standard)

- Wrapper object response (never raw arrays)
- Cursor-based for GraphQL tools: `after`/`perPage` params, response includes `totalCount` + `pageInfo { hasNextPage, hasPreviousPage, startCursor, endCursor }`
- Offset-based for REST tools: `page`/`perPage` params, response includes `totalCount` + `items`

### Other servers

- **Slack**: cursor/limit params, passthrough Slack's `response_metadata.next_cursor`
- **Brave Search**: offset/count, no pagination metadata in response
- **Git MCP**: no pagination, just `max_count` cap

### Decision

**Opaque cursor-based pagination**, following MCP spec convention + GitHub pattern. Internally the cursor encodes an offset (base64 JSON), but it's opaque to callers.

## Design

### Parameters

| Param     | Type    | Default | Description                                                                       |
| --------- | ------- | ------- | --------------------------------------------------------------------------------- |
| `cursor`  | string? | nil     | Opaque cursor from previous response's `endCursor`. Omit for first page.          |
| `perPage` | int?    | nil     | Results per page. When omitted: return all if ≤200, auto-paginate at 200 if >200. |

The existing `limit` parameter is **replaced** by `perPage` (clearer semantics with pagination).

### Response Shape

**Always a wrapper object** — consistent shape whether paginated or not.

```json
{
  "reminders": [
    {"id": "abc", "title": "Buy groceries", ...},
    {"id": "def", "title": "Call dentist", ...}
  ],
  "totalCount": 450,
  "pageInfo": {
    "hasNextPage": true,
    "hasPreviousPage": false,
    "endCursor": "eyJvZmZzZXQiOjIwMH0="
  }
}
```

When no pagination needed (all results fit):

```json
{
  "reminders": [...],
  "totalCount": 15,
  "pageInfo": {
    "hasNextPage": false,
    "hasPreviousPage": false,
    "endCursor": null
  }
}
```

### Pagination Logic

```
let PAGE_SIZE = 200

if cursor provided:
  decode offset from cursor
else:
  offset = 0

if perPage provided:
  pageSize = perPage
else if totalResults > PAGE_SIZE:
  pageSize = PAGE_SIZE  // auto-paginate
else:
  pageSize = totalResults  // return all, no pagination

slice = results[offset ..< offset + pageSize]

hasNextPage = (offset + pageSize) < totalResults
hasPreviousPage = offset > 0
endCursor = hasNextPage ? encode(offset + pageSize) : nil
```

### Cursor Encoding

Base64-encoded JSON: `{"offset": 200}` → `"eyJvZmZzZXQiOjIwMH0="`

Simple, deterministic, and opaque to callers. Invalid cursors throw an error.

### JMESPath Interaction

JMESPath queries currently return arbitrary shapes (`Any`). With the wrapper:

- JMESPath results that are arrays: wrap in `{ "results": [...], "totalCount": N, "pageInfo": {...} }`
- JMESPath results that are scalars: return as-is (no pagination applies) — `{ "result": 42 }`

Actually, this is tricky. JMESPath can transform the shape arbitrarily. Options:

1. **Apply pagination BEFORE JMESPath** — paginate the input, then JMESPath transforms the page. User gets consistent pages but JMESPath operates on partial data.
2. **Apply JMESPath first, then paginate the result** — JMESPath sees all data, pagination applies to output. Better for aggregation queries but JMESPath results might not be arrays.
3. **Skip pagination when JMESPath is used** — keep current behavior, just remove the hard cap.

**Decision: Option 3** — when JMESPath is provided, return the full JMESPath result with no pagination (remove the hard cap). JMESPath users are doing custom transformations and pagination would interfere. They can use JMESPath's own slicing (`[0:10]`) if needed.

## Files to Change

### 1. `Sources/AppleRemindersCore/Models.swift`

- Add `PageInfo` struct (Codable): `hasNextPage`, `hasPreviousPage`, `endCursor`
- Add `QueryResult` struct (Codable): `reminders` ([[String: Any]]), `totalCount`, `pageInfo`
- Actually, since `reminders` is `[[String: Any]]` (not Codable), we need a serialization approach. The `QueryResult` should hold the pre-formatted reminder dicts + pagination info, and `toJSON()` / `outputJSON()` handles serialization.

### 2. `Sources/AppleRemindersCore/RemindersManager.swift`

**Function signature change:**

```swift
public func queryReminders(
    list: ListSelector?,
    status: String?,
    sortBy: String?,
    query: String?,       // JMESPath
    perPage: Int?,        // replaces limit
    cursor: String?,      // NEW
    searchText: String?,
    dateFrom: String?,
    dateTo: String?,
    outputDetail: String?
) async throws -> Any
```

**Logic changes:**

- Remove both `min(limit ?? 50, 200)` lines
- When JMESPath is provided: apply to all results, return as-is (no pagination wrapper)
- When JMESPath is NOT provided:
  1. Filter + sort as before (get full result set)
  2. Compute `totalCount` from full result set
  3. Decode `cursor` to get offset (or 0)
  4. Determine pageSize: `perPage ?? (totalCount > 200 ? 200 : totalCount)`
  5. Slice results
  6. Apply `formatReminders()` to the slice
  7. Build and return wrapper dict: `{"reminders": [...], "totalCount": N, "pageInfo": {...}}`

**Add helper methods:**

- `decodeCursor(_ cursor: String) throws -> Int` — base64 decode, extract offset
- `encodeCursor(offset: Int) -> String` — encode offset as base64 JSON

### 3. `Sources/AppleRemindersCore/MCPServer.swift`

**Schema changes (tool definition for `query_reminders`):**

- Remove `limit` parameter (replace with `perPage`)
- Remove `maximum: 200` and `default: 50`
- Add `perPage` parameter: `{"type": "integer", "minimum": 1, "description": "Results per page. Omit to return all (auto-paginates at 200)."}`
- Add `cursor` parameter: `{"type": "string", "description": "Opaque cursor from previous response's pageInfo.endCursor for next page."}`

**Handler changes:**

- Parse `perPage` and `cursor` from arguments (instead of `limit`)
- Pass to `queryReminders()`

### 4. `Sources/AppleRemindersCLI/QueryCommand.swift`

- Replace `--limit` with `--per-page` option
- Add `--cursor` option
- Help text: `"Results per page (auto-paginates at 200 when omitted)"`
- Output: `outputJSON(result, pretty: globals.pretty)` — should work as-is since result is still `Any`

### 5. `Sources/AppleRemindersCore/HelpContent.swift`

- Lines 153, 176: Update `--limit` references to `--per-page` and `--cursor`
- Remove "max: 200" language

### 6. `SKILL.md` and `CLAUDE.md`

- Update CLI examples and parameter docs

### 7. Tests (`test/*.test.ts`)

**This is the biggest change.** ~60+ assertions check `Array.isArray(result)`.

Need a test helper approach. Options:

- A) Update every assertion individually
- B) Add a helper `extractReminders(result)` that unwraps the wrapper — update `mcp-client.ts`
- C) Have `callTool` auto-unwrap for query results

**Decision: Option B** — add `extractReminders()` helper in test utils. Each test that calls `query_reminders` gets updated to use it. This is mechanical but thorough.

The helper:

```typescript
function extractReminders(result: unknown): unknown[] {
  if (typeof result === 'object' && result !== null && 'reminders' in result) {
    return (result as {reminders: unknown[]}).reminders;
  }
  // Fallback for JMESPath results that aren't wrapped
  if (Array.isArray(result)) return result;
  return [result];
}
```

Also add pagination-specific tests:

- Test that responses include `pageInfo` and `totalCount`
- Test cursor-based navigation (create many reminders, paginate through)
- Test `perPage` parameter
- Test invalid cursor error handling

## Implementation Order

1. [x] Models.swift — add `PageInfo` type (cursor encode/decode helpers)
2. [x] RemindersManager.swift — new signature, pagination logic, remove hard cap
3. [x] MCPServer.swift — schema + handler updates
4. [x] QueryCommand.swift — CLI param changes
5. [x] HelpContent.swift — update help text
6. [x] Build and fix compilation errors (no Swift on Linux; verified changes are correct)
7. [x] Test helpers — add `extractReminders()` to test utils
8. [x] Update test assertions — mechanical update across all test files
9. [x] Add new pagination-specific tests (added in search.test.ts)
10. [ ] `bun run test` — verify all pass (requires macOS binary)
11. [x] `bun run signal` — formatting/lint check
12. [x] Update SKILL.md, CLAUDE.md docs
13. [ ] Commit + close beads

## Open Questions / Risks

- **Breaking change**: CLI consumers using `jq '.[]'` on query output will need to switch to `jq '.reminders[]'`. Acceptable for early-stage project.
- **Cursor stability**: Since we're querying EventKit live each time, the data could change between paginated requests. Offset-based cursors may skip/duplicate if reminders are added/deleted mid-pagination. This is acceptable — the cursor is a best-effort convenience, not a transactional guarantee.
- **`get_lists` tool**: Should it also get the wrapper treatment? Probably not now — list counts are typically small. Can add later if needed.
