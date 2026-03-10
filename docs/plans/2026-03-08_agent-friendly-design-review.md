# Agent-Friendly Design Review & Adaptation Plan

**Date:** 2026-03-08 (updated 2026-03-09)
**Reference:** Agent-Friendly Tool Design skill doc v2 (provided by user)

---

## Current State Assessment

### What We Already Do Well

| Area                          | Status         | Details                                                                   |
| ----------------------------- | -------------- | ------------------------------------------------------------------------- |
| **CLI-first, MCP as surface** | ✅ Excellent   | Core logic in `AppleRemindersCore`, CLI + MCP both use it                 |
| **JSON output**               | ✅ Excellent   | All commands output JSON to stdout, logs to stderr                        |
| **Field selection**           | ✅ Good        | `--detail minimal/compact/full` — 3 levels of output verbosity            |
| **Batch operations**          | ✅ Excellent   | Create/update/delete all support batch with partial failure reporting     |
| **Input validation**          | ✅ Good        | Dates, priorities, URLs, list selectors all validated with clear errors   |
| **Test mode safety**          | ✅ Excellent   | `AR_MCP_TEST_MODE=1` restricts writes to test-prefixed lists              |
| **Auth**                      | ✅ Appropriate | Single macOS EventKit permission — nothing for agents to manage           |
| **MCP tool descriptions**     | ⚠️ Too verbose | 100+ lines of instructions dumped at connect time                         |
| **Skill file**                | ⚠️ Too heavy   | `skills/reminders/SKILL.md` is a full reference, not a bootstrap redirect |

### Gaps vs. the Spec

| Gap                                                      | Priority  | Rationale                                                                 |
| -------------------------------------------------------- | --------- | ------------------------------------------------------------------------- |
| **No tiered help system** (`--help --verbose`, `=skill`) | 🔴 High   | Core principle of the spec; currently only ArgumentParser's flat `--help` |
| **No audit logging**                                     | 🔴 High   | #2 priority in retrofitting order; essential for safety and debugging     |
| **MCP descriptions too verbose**                         | 🔴 High   | All tool schemas + 100+ lines of instructions dumped at connect time      |
| **No MCP meta-tools** (`help`, `schema`, `guidance`)     | 🔴 High   | No way for agent to query help on-demand; it's all-or-nothing             |
| **No `--dry-run`**                                       | 🟡 Medium | Agents can't preview mutations before executing                           |
| **No structured error codes**                            | 🟡 Medium | Errors are human-readable strings, not machine-parseable envelopes        |
| **Skill file is a full reference**                       | 🟡 Medium | Should be a bootstrap redirect, not documentation                         |
| **No TTY detection**                                     | 🟢 Low    | `--pretty` is explicit; agents prefer consistent output anyway            |
| **No JSONL streaming**                                   | 🟢 Low    | Datasets are small (personal reminders); not a real bottleneck            |
| **No control character rejection**                       | 🟢 Low    | Unlikely attack vector for a local-only tool                              |

---

## Proposed Changes

### Phase 1: Tiered Help System (CLI) 🔴

**Goal:** Implement `--help --verbose` and `--help=skill` across all commands.

**Design (updated to match spec v2):**

The spec uses two help levels (not three) plus skill guidance on a separate axis:

- `reminders query --help` → Concise: command signature, one-line description, flags with brief types/defaults. ~10-20 lines. Sufficient for most agent use.
- `reminders query --help --verbose` → Comprehensive (cumulative): everything from `--help` plus full parameter descriptions, examples, edge cases, environment variables, related commands. Equivalent of a documentation page.
- `reminders query --help=skill` → Separate axis: strategic guidance, best practices, invariants, gotchas. Not API docs — behavioral guidance.

Each help output ends with self-referencing pointers:

```
Use --help --verbose for detailed docs and examples.
Use --help=skill for best practices and strategic guidance.
Use `reminders schema <command>` to inspect input/output schemas.
```

**Graceful degradation:** `--verbose` on `--help` is silently ignored if unsupported, making it safe for agents to try on any CLI.

**Implementation approach:**

ArgumentParser intercepts `--help` before `run()` executes. To support `--help --verbose` and `--help=skill`, we need to handle these before ArgumentParser's built-in help fires.

Options:

- **Option A:** Add `--verbose` as a global flag. Override ArgumentParser's help rendering to include verbose content and the self-referencing footer. Detect `--help=skill` via custom argument parsing (since `=` syntax isn't standard ArgumentParser).
- **Option B:** Add custom `--docs` and `--skill` flags that print help and exit from within `run()`. Simpler but deviates from the spec's syntax.
- **Option C:** Custom pre-parse of `ProcessInfo.arguments` to detect `--help --verbose` and `--help=skill` before ArgumentParser runs. Print custom help and exit(0). Most flexible, avoids fighting the framework.

**Recommendation:** Option C. It gives us full control over help output without fighting ArgumentParser. We intercept early, print what we want, and exit. ArgumentParser's built-in `--help` continues to work as the concise level for cases we haven't customized yet.

**Content to write:**

Start with top commands: `query`, `create`, `update`, `delete`, `lists`. Then extend to all commands. For each:

- Concise help (replaces/augments ArgumentParser default)
- Verbose help (cumulative — includes concise + detailed docs + examples)
- Skill guidance (best practices for that command)

Also write top-level `reminders --help=skill` with cross-cutting guidance.

### Phase 2: Audit Logging 🔴

**Goal:** Log every mutation with timestamp, action, result, and before-state. JSONL format.

**This is the #2 priority in the retrofitting order** (right after JSON output, which we already have). Non-negotiable for agent safety.

**What to log:**

Every create, update, delete operation gets a JSONL entry:

```json
{
  "timestamp": "2026-03-09T14:30:00-08:00",
  "action": "update_reminder",
  "args": {"id": "abc123", "title": "New title", "priority": "high"},
  "result": "success",
  "response": {"id": "abc123", "title": "New title", "priority": "high"},
  "beforeState": {"id": "abc123", "title": "Old title", "priority": "none"},
  "context": {"source": "cli", "sessionId": "sess_abc"}
}
```

**Log location:** `~/.config/apple-reminders-tools/logs/` with one file per day (`2026-03-09.jsonl`).

**CLI command:** `reminders audit` (or `reminders logs`) to list recent sessions and view what happened.

**Shared core:** Both CLI and MCP surfaces write to the same audit log via a shared `AuditLogger` in `AppleRemindersCore`.

**Before-state capture:** For updates, query the reminder's current state before applying changes. For deletes, capture the full reminder before deletion. For creates, before-state is null.

**Retention:** Keep indefinitely during this alpha/beta phase. Add configurable retention later.

### Phase 3: MCP Progressive Disclosure 🔴

**Goal:** Slim down MCP tool descriptions. Add `help`, `schema`, and `guidance` meta-tools.

**Current problem:** The MCP server dumps ~800 lines of tool descriptions at connect time.

**Changes:**

1. **Slim tool descriptions to 2-3 sentences.** Keep enough for the agent to know what the tool does and when to use it, but move examples, field lists, and detailed parameter docs to the help meta-tool.

2. **Add `help` meta-tool:**

   ```
   help(tool_name: string, verbose?: boolean) → string
   ```

   Returns help text for the specified tool. Default is concise; `verbose=true` gives comprehensive docs with examples.

3. **Add `schema` meta-tool:**

   ```
   schema(tool_name: string) → JSON
   ```

   Returns the full JSON input schema for a tool.

4. **Add `guidance` meta-tool:**

   ```
   guidance(topic?: string) → string
   ```

   Returns strategic guidance (equivalent to `--help=skill`). Optional topic to scope to a specific area.

5. **Slim the `initialize` response instructions.** Currently 106+ lines. Replace with brief overview + "call `help` for details on any tool, `guidance` for best practices."

6. **Keep `inputSchema` in tool listings** — agents need the schema to construct valid calls. But remove lengthy `description` fields from individual properties within the schema. Those details are available via `help(tool, verbose=true)`.

### Phase 4: `--dry-run` for Mutations 🟡

**Goal:** Let agents preview what a mutation would do before executing it.

**Affected commands:** `create`, `create-list`, `update`, `delete`

**Design:**

Add a `--dry-run` global flag. When set:

1. Run all input validation (dates, priorities, URLs, list resolution)
2. Return a JSON object describing what _would_ happen:
   ```json
   {
     "dryRun": true,
     "action": "create_reminder",
     "validated": {
       "title": "Buy groceries",
       "list": "Personal",
       "dueDate": "2026-03-10T17:00:00-08:00",
       "priority": "medium"
     },
     "warnings": []
   }
   ```
3. Do NOT call EventKit / actually create/update/delete

**For MCP:** Add an optional `dryRun` boolean parameter to `create_reminders`, `update_reminders`, `delete_reminders`, and `create_list`.

### Phase 5: Structured Error Envelope 🟡

**Goal:** Consistent, machine-parseable error responses.

**Current:** Errors are plain strings on stderr (CLI) or `isError: true` with text content (MCP).

**Proposed CLI error format** (when outputting JSON):

```json
{
  "error": {
    "code": "INVALID_DATE",
    "message": "Invalid date format: '2026-13-01'. Expected ISO 8601 format: YYYY-MM-DDTHH:MM:SS±HH:MM",
    "expected": "ISO 8601 date string",
    "received": "2026-13-01"
  }
}
```

**Error codes to define:**

- `INVALID_DATE`, `INVALID_PRIORITY`, `INVALID_URL`
- `LIST_NOT_FOUND`, `REMINDER_NOT_FOUND`
- `AMBIGUOUS_LIST_SELECTOR`, `ACCESS_DENIED`
- `TEST_MODE_VIOLATION`

**MCP:** Same error structure in the `content[0].text` field.

### Phase 6: Bootstrap Skill File 🟡

**Goal:** Convert `skills/reminders/SKILL.md` from a full reference into a minimal bootstrap redirect.

**Current:** ~150 lines of documentation, examples, and reference material.

**Proposed:**

```markdown
---
name: reminders
description: >
  Manage Apple Reminders on macOS — query, create, update, delete reminders and lists.
allowed-tools: Bash(reminders *), Bash(${CLAUDE_PLUGIN_ROOT}/.build/release/reminders *)
---

## Using reminders

`reminders` is a CLI for managing Apple Reminders. Before first use, run:

    reminders --help=skill

This returns best practices and strategic guidance for using the tool effectively.

For API docs, use `reminders <command> --help` (concise) or `--help --verbose` (comprehensive).
For input/output schemas, use `reminders schema <command>`.

### User preferences

- Default to `--detail compact` for queries unless more detail is needed.
- Use `--pretty` when showing output to the user.
- Always use `--all-lists` unless the user specifies a particular list.
```

The full reference content currently in SKILL.md moves into the `--help --verbose` / `--help=skill` system, versioned with the tool.

### Phase 7: Minor Hardening 🟢

Lower priority items that round out spec compliance:

1. **Schema introspection CLI command** — `reminders schema <command>` outputs the JSON input schema for a command (same data the MCP server exposes).
2. **Control character rejection** — Reject ASCII < 0x20 in reminder titles and notes.
3. **TTY detection** — Auto-enable `--pretty` when stdout is a TTY (with `--output json` override).

---

## Implementation Order

| Phase                               | Effort | Depends On                  | Notes                                       |
| ----------------------------------- | ------ | --------------------------- | ------------------------------------------- |
| Phase 1: Tiered Help                | Medium | Nothing                     | Foundation for everything else              |
| Phase 2: Audit Logging              | Medium | Nothing                     | #2 in retrofitting order; safety-critical   |
| Phase 3: MCP Progressive Disclosure | Medium | Phase 1 (shares HelpSystem) | Biggest token savings                       |
| Phase 6: Bootstrap Skill File       | Small  | Phase 1 (needs help=skill)  | Quick win once Phase 1 lands                |
| Phase 4: Dry-run                    | Medium | Nothing                     | Independent, high safety value              |
| Phase 5: Structured Errors          | Medium | Nothing                     | Independent, improves agent self-correction |
| Phase 7: Minor Hardening            | Small  | Phases 1-3                  | Polish                                      |

**Suggested order:** 1 → 2 → 3 → 6 → 4 → 5 → 7

**MVP (minimum to claim "agent-friendly"):** Phases 1 + 2 + 3 + 6

---

## Design Decisions (Resolved)

1. **MCP description aggressiveness:** Keep 2-3 sentences per tool. Focus on adding progressive disclosure pattern rather than minimizing aggressively. Can tune later.

2. **Help syntax:** Use `--help --verbose` (cumulative) and `--help=skill` (separate axis), per spec v2. Implement via pre-parsing `ProcessInfo.arguments` before ArgumentParser runs.

3. **Help content storage:** `HelpContent.swift` with static string constants per command. Pragmatic, keeps content close to code, easy to maintain.

4. **Scope:** Start with top 3-4 commands (query, create, update, delete), then extend to all. Commit regularly as each command is done.

---

## What This Does NOT Change

- The core architecture (CLI-first, MCP as surface) is already correct
- The existing `--detail minimal/compact/full` system stays as-is (it's the field-mask equivalent)
- Batch operation design stays as-is
- Auth model stays as-is (EventKit permission)
- Test mode stays as-is
- JSON-to-stdout / logs-to-stderr separation stays as-is

---

## Progress

- [x] Phase 1: Tiered Help System ✅ (2026-03-10)
  - [x] Pre-parse argument interception for `--help --verbose` and `--help=skill`
  - [x] HelpContent.swift with content for ALL commands (query, create, update, delete, lists, create-list, export, snapshot, audit, mcp)
  - [x] Self-referencing footer on all help output
  - [x] HelpSystem.swift pre-parser intercepts before ArgumentParser
- [x] Phase 2: Audit Logging ✅ (2026-03-10)
  - [x] AuditLogger in AppleRemindersCore (JSONL, per-day files in ~/.config/apple-reminders-tools/logs/)
  - [x] Wire into RemindersManager for all mutations (create, update, delete, create-list)
  - [x] Before-state capture for updates and deletes
  - [x] `reminders audit` CLI command (--days, --files flags)
  - [x] MCP surface writes to same log (source: "mcp")
- [x] Phase 3: MCP Progressive Disclosure ✅ (2026-03-10)
  - [x] Slim tool descriptions to 2-3 sentences (from ~600 lines to ~30)
  - [x] Add `help` meta-tool (with verbose flag)
  - [x] Add `schema` meta-tool
  - [x] Add `guidance` meta-tool
  - [x] Slim `initialize` instructions (from ~25 lines to ~6)
- [x] Phase 6: Bootstrap Skill File ✅ (2026-03-10)
  - [x] Converted from ~115 line reference to ~25 line bootstrap redirect
- [ ] Phase 4: Dry-run
- [ ] Phase 5: Structured Errors
- [ ] Phase 7: Minor Hardening

### New Files Created

- `Sources/AppleRemindersCore/HelpContent.swift` — Static help text at all tiers for all commands
- `Sources/AppleRemindersCore/HelpSystem.swift` — Pre-parse interception for --help flags
- `Sources/AppleRemindersCore/AuditLogger.swift` — JSONL audit logger
- `Sources/AppleRemindersCLI/AuditCommand.swift` — `reminders audit` CLI command
