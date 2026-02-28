# outputDetail: Compact/Minimal/Full Output Levels for query_reminders

**Date:** 2026-02-13
**Status:** Complete — built and tested on Linux (Swift 6.1.2, 78 tests passing)

---

## Goal

Add an `outputDetail` parameter to `query_reminders` that controls which fields are returned and how nulls are handled. This reduces token usage for common queries while preserving full access when needed.

Also renames `creationDate` → `createdDate` and `modificationDate` → `lastModifiedDate` at the output/serialization layer.

---

## Design

### Field Sets

| Preset                | Fields                                                                                                          | Null handling                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **minimal**           | `id`, `title`, `listName`\*, `isCompleted`\*                                                                    | Omit null fields                                 |
| **compact** (default) | `id`, `title`, `notes`, `listName`\*, `isCompleted`\*, `dueDate`, `priority`, `createdDate`, `lastModifiedDate` | Omit null fields                                 |
| **full**              | All 15 fields                                                                                                   | Always include all keys (nulls shown explicitly) |

\* = Conditionally omitted based on query context (see below)

### Conditional Field Omission (compact & minimal only)

- **`listName`**: Omit when the query targets a single list (explicit name, explicit ID, or default list — i.e. anything EXCEPT `{all: true}`)
- **`isCompleted`**: Omit when status is `"incomplete"` (default) or `"completed"` — the value is implied. Include only when status is `"all"`

### JMESPath Override

When `query` (JMESPath) is provided, `outputDetail` is ignored. JMESPath always receives all fields (full), and the expression itself controls output projection.

### Null Stripping

Implemented as a **final step** before outputting, applied uniformly:

1. Build full reminder dict (same logic for all outputDetail levels)
2. Select the appropriate field set for the outputDetail level
3. For compact/minimal: strip any keys whose value is null/nil
4. For full: keep all keys (nulls rendered as JSON `null`)

This keeps the core serialization logic identical across all levels — the only difference is field selection and null-stripping at the end.

### Field Rename

- `creationDate` → `createdDate`
- `modificationDate` → `lastModifiedDate`

Applied in `ReminderOutput` struct and `encodableArray`. This is a breaking change to the output format but aligns with the user's preferred naming.

---

## Implementation Plan

### Step 1: Rename fields in ReminderOutput + encodableArray

- Rename `creationDate` → `createdDate` in `ReminderOutput` struct
- Rename `modificationDate` → `lastModifiedDate` in `ReminderOutput` struct
- Update `encodableArray` to use new key names
- Update `convertToOutput` mapping
- Update tool description (JMESPath field list, examples)
- Update sorting code that references `creationDate`

### Step 2: Add `outputDetail` parameter

- Add `outputDetail` enum/string param to `queryReminders` function signature
- Add to tool definition (input schema + description)
- Parse in the dispatch/call site

### Step 3: Implement field filtering in encodableArray

- Refactor `encodableArray` to accept output detail level + query context (isSingleList, statusFilter)
- Build full dict first (current logic), then:
  - Select field subset based on outputDetail
  - For compact/minimal: conditionally omit `listName` and `isCompleted`
  - For compact/minimal: strip null-valued keys
  - For full: explicitly include all keys with null values

### Step 4: Wire JMESPath override

- In `queryReminders`, when `query` is provided, force outputDetail to "full" before passing to `applyJMESPath`

### Step 5: Update tests

- Update any tests that assert on field names (`creationDate` → `createdDate`, etc.)
- Add tests for outputDetail levels if possible

### Step 6: Build and verify

- `bun run build` to ensure Swift compiles
- `bun run test` to run test suite
- Manual verification of JSON output shapes

---

## Progress

- [x] Step 1: Rename fields (`creationDate` → `createdDate`, `modificationDate` → `lastModifiedDate`)
- [x] Step 2: Add `outputDetail` parameter to `queryReminders` signature, dispatch, tool schema
- [x] Step 3: Implement field filtering via `formatReminders` / `buildFullDict` (replaces returning `[ReminderOutput]` with `[[String: Any]]`)
- [x] Step 4: JMESPath always uses full fields (returns before `formatReminders` is called)
- [x] Step 5: Updated tests — fixed `listName`/`listId` assertions, added new tests for compact/minimal/full
- [x] Step 6: Build and test on Linux (Swift 6.1.2 installed, `#if canImport(EventKit)` added, 78/78 tests pass)

## Implementation Notes

- `formatReminders` is a new method that converts `[ReminderOutput]` → `[[String: Any]]` with field filtering
- `buildFullDict` creates a complete dict with `NSNull()` for nil optional fields
- Field filtering and null stripping happen as a final step (same logic flow for all detail levels)
- JMESPath path returns _before_ `formatReminders` is called, so it always gets full `ReminderOutput` via `JSONEncoder`
- Non-JMESPath path returns `[[String: Any]]` which goes through `JSONSerialization` (not `JSONEncoder`)
- `encodableArray` (used by create/update responses) is unchanged — those always return all fields
- Added `#if canImport(EventKit)` guards to enable Linux builds (falls back to mock store)
- Fixed 2 pre-existing test bugs: `toBeNull()` → `toBeUndefined()` for fields stripped by `encodableArray`
- Added 6 new outputDetail tests: conditional isCompleted/listName, JMESPath override, field renames, default=compact, full field presence
