# Agent-Friendly Design Review & Adaptation Plan

**Date:** 2026-03-08
**Reference:** Agent-Friendly Tool Design skill doc (provided by user)

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

| Gap                                                  | Priority  | Rationale                                                                 |
| ---------------------------------------------------- | --------- | ------------------------------------------------------------------------- |
| **No tiered help system** (`--help=1/2/3/skill`)     | 🔴 High   | Core principle of the spec; currently only ArgumentParser's flat `--help` |
| **MCP descriptions too verbose**                     | 🔴 High   | All tool schemas + 100+ lines of instructions dumped at connect time      |
| **No MCP meta-tools** (`help`, `schema`, `guidance`) | 🔴 High   | No way for agent to query help on-demand; it's all-or-nothing             |
| **No `--dry-run`**                                   | 🟡 Medium | Agents can't preview mutations before executing                           |
| **No structured error codes**                        | 🟡 Medium | Errors are human-readable strings, not machine-parseable envelopes        |
| **No TTY detection**                                 | 🟢 Low    | `--pretty` is explicit; agents prefer consistent output anyway            |
| **No JSONL streaming**                               | 🟢 Low    | Datasets are small (personal reminders); not a real bottleneck            |
| **No control character rejection**                   | 🟢 Low    | Unlikely attack vector for a local-only tool                              |
| **No path traversal hardening**                      | 🟢 Low    | Only affects `--path` in export; local tool on user's own machine         |
| **Skill file is a full reference**                   | 🟡 Medium | Should be a bootstrap redirect, not documentation                         |

---

## Proposed Changes

### Phase 1: Tiered Help System (CLI) 🔴

**Goal:** Implement `--help=1/2/3/skill` across all commands.

**Design:**

ArgumentParser doesn't natively support `--help=N`. We have two options:

#### Option A: Custom `--help-level` flag (Recommended)

Add a `--help-level <N>` or `--help-detail <N>` global option that, when provided, prints the appropriate help level and exits. Keep ArgumentParser's built-in `--help` as the level-1 default.

- `reminders query --help` → Level 1 (ArgumentParser default): command signature, one-line description, option list
- `reminders query --help-level 2` → Level 2: full parameter descriptions with types, defaults, 2-3 examples
- `reminders query --help-level 3` → Level 3: full JSON schema for complex inputs, edge cases, all field names, related commands
- `reminders query --help-level skill` → Strategic guidance: best practices, invariants, gotchas, common workflows

Each level's output includes a footer: `Use --help-level 2/3/skill for more detail.`

#### Option B: Override `--help` with custom levels

Intercept `--help` and support `--help=2` syntax. This is harder with ArgumentParser and might fight the framework.

**Recommendation:** Option A. It's additive, doesn't fight ArgumentParser, and is clear.

**Implementation:**

1. Add a `--help-level` global option to the root `Reminders` command (string, optional)
2. Create a `HelpSystem` module in `AppleRemindersCore` that stores help text at each level for each command
3. In each command's `run()`, check if `--help-level` is set; if so, print the appropriate help and exit
4. Write help content for all 8 commands × 4 levels (but start with just the top 3 most-used commands: `query`, `create`, `update`)

**Content strategy for help levels:**

| Level                | Content                                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 (default `--help`) | Already exists via ArgumentParser. Add footer referencing deeper levels.                                                                               |
| 2                    | Parameter details with types, defaults, enum values. 2-3 concrete examples.                                                                            |
| 3                    | Full JSON schema, all field names, edge cases, environment variables, related commands.                                                                |
| skill                | Best practices: "Always query before updating." "Use `--detail minimal` to save tokens." "Use JMESPath to filter server-side." Invariants and gotchas. |

### Phase 2: MCP Progressive Disclosure 🔴

**Goal:** Slim down MCP tool descriptions. Add `help`, `schema`, and `guidance` meta-tools.

**Current problem:** The MCP server dumps ~800 lines of tool descriptions at connect time. Every connection burns those tokens whether the agent needs them or not.

**Changes:**

1. **Slim tool descriptions to one-liners.** Each tool gets a brief description (1-2 sentences max). Remove the multi-paragraph explanations, examples, and field lists from the tool descriptions.

2. **Add `get_help` meta-tool:**

   ```
   get_help(tool_name: string, depth?: 1|2|3|"skill") → string
   ```

   Returns help text for the specified tool at the requested depth. Pulls from the same `HelpSystem` module as the CLI.

3. **Add `get_schema` meta-tool:**

   ```
   get_schema(tool_name: string) → JSON
   ```

   Returns the full JSON input schema for a tool. This is what currently gets dumped in `inputSchema` — but now it's on-demand.

4. **Slim the `initialize` response instructions.** Currently 106+ lines. Replace with a brief overview + "call `get_help` for details on any tool."

5. **Keep the `inputSchema` in tool listings** but make it minimal (required params only, no descriptions in the schema itself). The full schema with descriptions is available via `get_schema`.

**Open question:** How aggressively to slim the tool descriptions. The current descriptions are genuinely excellent and agents benefit from them. We could take a middle ground: keep 2-3 sentence descriptions (not one-liners) but move examples and field lists to the help meta-tool. This balances token efficiency with initial usability.

### Phase 3: `--dry-run` for Mutations 🟡

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

### Phase 4: Structured Error Envelope 🟡

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

### Phase 5: Bootstrap Skill File 🟡

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

    reminders --help-level skill

This returns best practices and strategic guidance for using the tool effectively.

For API docs, use `reminders <command> --help` (brief) through `--help-level 3` (comprehensive).

### User preferences

- Default to `--detail compact` for queries unless more detail is needed.
- Use `--pretty` when showing output to the user.
- Always use `--all-lists` unless the user specifies a particular list.
```

The full reference content currently in SKILL.md moves into the `--help-level 2/3/skill` system, where it's versioned with the tool itself.

### Phase 6: Minor Hardening 🟢

Lower priority items that round out the spec compliance:

1. **Self-referencing help footer** — Every `--help` output includes "Use `--help-level 2` for detailed docs, `--help-level 3` for schemas, `--help-level skill` for best practices."
2. **Schema introspection CLI command** — `reminders schema <command>` outputs the JSON input schema for a command (same data the MCP server exposes).
3. **Control character rejection** — Reject ASCII < 0x20 in reminder titles and notes.
4. **TTY detection** — Auto-enable `--pretty` when stdout is a TTY (with `--output json` override).

---

## Implementation Order

| Phase                               | Effort | Depends On                                    | Notes                                       |
| ----------------------------------- | ------ | --------------------------------------------- | ------------------------------------------- |
| Phase 1: Tiered Help                | Medium | Nothing                                       | Foundation for everything else              |
| Phase 2: MCP Progressive Disclosure | Medium | Phase 1 (shares HelpSystem)                   | Biggest token savings                       |
| Phase 5: Bootstrap Skill File       | Small  | Phase 1 (needs `--help-level skill` to exist) | Quick win once Phase 1 lands                |
| Phase 3: Dry-run                    | Medium | Nothing                                       | Independent, high safety value              |
| Phase 4: Structured Errors          | Medium | Nothing                                       | Independent, improves agent self-correction |
| Phase 6: Minor Hardening            | Small  | Phases 1-2                                    | Polish                                      |

**Suggested order:** 1 → 2 → 5 → 3 → 4 → 6

**MVP (minimum to claim "agent-friendly"):** Phases 1 + 2 + 5

---

## Design Decisions to Discuss

1. **How aggressively to slim MCP descriptions?** The current descriptions are genuinely excellent. A middle ground (2-3 sentences + "call `get_help` for more") might be better than strict one-liners. What's your preference?

2. **`--help-level` vs `--help=N` syntax?** ArgumentParser makes `--help=N` hard. `--help-level` is straightforward but slightly more verbose. Alternative: `--guide` or `--docs` as the flag name?

3. **Where to store help content?** Options:
   - Inline in Swift source (easy, but clutters code)
   - Separate `.txt` or `.md` resource files (clean, but Swift Package Manager resource bundling has quirks)
   - A `HelpContent.swift` file with static string constants (pragmatic middle ground)

4. **Should `get_schema` return the full JSON Schema or a simplified version?** The full schema is already in the MCP tool definitions. A simplified version (just param names + types + required) might be more useful.

5. **Scope of Phase 1:** Start with all 8 commands, or just the top 3 (query, create, update) and iterate?

---

## What This Does NOT Change

- The core architecture (CLI-first, MCP as surface) is already correct
- The existing `--detail minimal/compact/full` system stays as-is (it's the field-mask equivalent)
- Batch operation design stays as-is
- Auth model stays as-is (EventKit permission)
- Test mode stays as-is
- JSON-to-stdout / logs-to-stderr separation stays as-is
