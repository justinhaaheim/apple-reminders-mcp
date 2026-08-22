# 2026-06-04 — Priority validation hardening (epic apple-reminders-mcp-wxd)

Source bug report: `~/Dropbox/.../drafts/2026-06-01 apple-reminders priority validation bug.md`

## Problem

MCP `create_reminders` / `update_reminders` silently drop `priority` when the
JSON value isn't a string (e.g. `priority: 1`). Root cause at the MCP boundary:

- create: `dict["priority"] as? String` → nil on non-string (MCPServer.swift:821)
- update: `parseClearable(dict["priority"])` → nil on non-String cast (MCPServer.swift:894, parseClearable:1046)
  Both collapse "present-but-wrong-type" into "absent" → silent no-op.

## Key fact

JSON is decoded via `JSONDecoder` (AnyCodable), so values are REAL Swift types
(Bool stays Bool, Int stays Int) — no NSNumber ambiguity. So `as? Int` accepts
`1` while `as? Bool` / `raw is Bool` cleanly rejects `true`.

## Plan (sub-beads)

- [x] wxd.1 accept Apple ints 0/1/5/9 (0→none, 1→high, 5→medium, 9→low)
- [x] wxd.2 reject everything else with RemindersError (no silent no-op)
- [x] wxd.3 schema → oneOf [string-enum, integer-enum 0/1/5/9, null] + new description

**Epic wxd CLOSED 2026-06-04.** Verified: tests (12 pass in crud) + live MCP binary
(`priority:1`→high, `priority:2`/`true`→loud error). Snapshot updated.

## Implementation

- Models.swift: `Priority.fromAppleInteger`, `enum NormalizedPriority {unset, level}`,
  `normalizePriorityValue(Any) throws`, `createPriorityString(from:)`,
  `updatePriorityClearable(from:)`. wxd.1+wxd.2 share this one parse-and-validate path.
- MCPServer.swift: call sites 821 / 894 → use the new helpers (with `try`).
- MCPServer.swift: schema blocks 387-391 (create) & 520-524 (update) → oneOf form.
- Decision: invalid priority THROWS → aborts batch (consistent w/ missing id/title).
  "HIGH" normalizes to high (fromString lowercases). CLI unaffected (string flag).

## Tests / verify

- Update `test/__snapshots__/schema-snapshot.test.ts.snap` (priority schema changed).
- Add crud tests: priority:1 → "high"; priority:0/null → cleared; priority:2/"urgent"/true → error.
- `swift build` then `bun run test` then `bun run signal`.

## Next

- Epic B (apple-reminders-mcp-9ei): delete_list tool.

---

# Epic apple-reminders-mcp-9ei — delete_list tool (started 2026-06-05)

- [x] 9ei.1 core: `ReminderStore.deleteCalendar` (EventKit `removeCalendar`;
      Mock removes calendar + its reminders). Manager `deleteList(selector:force:)`
      with ambiguity error, default-list protection, test-mode guard, non-empty
      refusal unless force (reports count), audit log.
- [x] 9ei.2 MCP `delete_list` tool: oneOf id/name + force; success →
      `{deleted:[id], failed:[]}`; all failures throw (isError).
- [x] 9ei.3 (P4) CLI `reminders delete-list` parity: name arg or --list-id,
      --force; output `{deleted:[id], failed:[]}`. Help content + toolToCommandMap
      wired. CLI fresh-mock-per-invocation only seeds default list, so CLI tests
      cover guard/validation paths; happy/force/ambiguity covered via shared
      manager in the MCP suite.

**Epic 9ei CLOSED 2026-06-06.** Tests: `test/delete-list.test.ts` (6, MCP) +
`test/cli-delete-list.test.ts` (4, CLI), readonly count 11→12, schema-snapshot
delete_list added. 161 pass. Verified live (MCP + CLI). Docs updated
(CLAUDE.md tools table + CLI usage, SKILL.md quick ref).

---

# Epic apple-reminders-mcp-wil — API hardening from PR review (2026-06-09)

From the PR review of this branch. Goals: unify priority (finding #1), dedup
(#5/#6), and eliminate silent failures (user mandate).

- [x] wil.1 `Priority.parse(token) -> Priority?` is the single shared validator
      (CLI + MCP). Accepts low/medium/high, **none**, and Apple ints 0/1/5/9
      (also as strings). Canonical output stays null|low|medium|high. Manager is
      the validation point; invalid → per-item failed (loud). Removed the old
      MCP-boundary normalizer family.
- [x] wil.2 shared `resolveSingleList(allowDefault:duplicateName:)` (create vs
      delete) + `prioritySchema(description:)` helper (create vs update).
- [x] wil.3 loud type validation at the boundary: `parseClearable` throws on
      present-but-wrong-type; new requireStringOrNil/requireBoolOrNil/
      parseListSelector. A bare-string `list` now errors instead of silently
      writing to the default list.
- [x] wil.4 `validatePriorityLiteralsInQuery`: a JMESPath like
      `[?priority == 'none']` now errors (would silently return []) with a hint
      to use `priority == null`.

**Epic wil CLOSED 2026-06-09.** Commits ba388a7 (wil.1), d0e18a7 (wil.2),
ab9274b (wil.3), + wil.4. 180 pass, signal clean. New tests: cli-priority,
input-validation; crud updated to per-item-failure semantics.

Key principle reinforced: silent no-ops are the worst failure mode (an LLM reads
a non-error response as success), so every present-but-invalid input now fails
loud — error, per-item failure, or validation — never a silent drop.
