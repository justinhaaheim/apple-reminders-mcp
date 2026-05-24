# API tweaks: status flag, priority null, scope hygiene

**Date:** 2026-05-24
**Branch:** `api-tweaks-status-priority`
**Beads epic:** `apple-reminders-mcp-ko3`
**Original plan:** `/Users/jhaa/.claude/plans/oh-and-same-thing-sprightly-shamir.md`

## Why

While dumping reminders matching a multi-criteria query, the assistant reached for `--status all` even though the user only asked for "reminders matching X" (which they consider implicitly incomplete). The same pattern shows up with `--all-lists`. The user's read is that the API itself encourages this — `--status {incomplete|completed|all}` makes "all" look like an innocuous fourth option, not a deliberate widening.

Goal: reshape the API so defaults are encoded in the flag names themselves. Drop the `"none"` priority string sentinel while we're in there.

## Decisions

1. **Status:** Replace `--status {incomplete|completed|all}` with two mutually exclusive booleans:
   - `--include-completed` — fetch incomplete + completed
   - `--completed-only` — fetch only completed
   - Default (neither flag) = incomplete only
2. **List scope:** Leave `--all-lists` as-is (the CLI default is already single-list). Tighten docs/examples that gratuitously showcase `--all-lists`.
3. **Priority null:**
   - Drop the `.none` case from `Priority`.
   - Query output: emit `priority: null` (or omit per Codable default) instead of `"none"`.
   - MCP `update_reminders`: `priority: null` = clear; absent = no change; string = set.
   - CLI: `--priority` accepts `low|medium|high` only; new `--clear-priority` flag.

## Breaking change

No deprecation aliases. The user is the only meaningful consumer today and this is a young project. Callers must update.

## Progress

- [x] Plan approved
- [x] Scratchpad created
- [x] Beads epic created (`apple-reminders-mcp-ko3`)
- [ ] Sub-beads created
- [ ] Core: Priority + ReminderOutput
- [ ] Core: UpdateReminderInput.priority → Clearable
- [ ] Core: RemindersManager (status handling, output, create/update priority, prioritySortOrder)
- [ ] MCP: schemas + arg parsing
- [ ] CLI: QueryCommand
- [ ] CLI: UpdateCommand (+ --clear-priority)
- [ ] CLI: CreateCommand
- [ ] HelpContent
- [ ] Tests: TS test fixes
- [ ] Tests: schema snapshot regen
- [ ] Docs: CLAUDE.md, SKILL.md, query-reference.md, skills/reminders/SKILL.md, ROADMAP.md
- [ ] Memory: feedback memory generalization
- [ ] Verify: build, signal, tests
- [ ] Smoke: CLI + MCP
- [ ] Commit + close beads

## Key file map

| File                                                                                        | Change                                                               |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `Sources/AppleRemindersCore/Models.swift`                                                   | Priority enum, ReminderOutput.priority, UpdateReminderInput.priority |
| `Sources/AppleRemindersCore/RemindersManager.swift:267-275, 702-709, 748, 820-825, 947-953` | status handling, output, create/update priority, sort helper         |
| `Sources/AppleRemindersCore/MCPServer.swift:223-238, 383-387, 516-520, 729-769, 837-895`    | schemas + parsing                                                    |
| `Sources/AppleRemindersCLI/QueryCommand.swift`                                              | status flag rewrite                                                  |
| `Sources/AppleRemindersCLI/UpdateCommand.swift`                                             | priority + --clear-priority                                          |
| `Sources/AppleRemindersCLI/CreateCommand.swift`                                             | priority restriction                                                 |
| `Sources/AppleRemindersCore/HelpContent.swift`                                              | all help strings mentioning status/priority/--all-lists              |
| `test/search.test.ts:114, 124, 158, 213, 275, 415, 421, 562`                                | API surface updates                                                  |
| `test/crud.test.ts:71`                                                                      | status: 'incomplete' usage                                           |
| `test/__snapshots__/schema-snapshot.test.ts.snap`                                           | regen after schema changes                                           |
| `CLAUDE.md, SKILL.md, skills/reminders/SKILL.md, docs/query-reference.md, ROADMAP.md`       | doc updates                                                          |
| `~/.claude/projects/.../memory/feedback_status_incomplete_default.md`                       | memory generalization                                                |

## Out of scope

- Renaming `--all-lists` (kept per Q2)
- Deprecation aliases for `--status`
- Historical `docs/plans/*` updates
- Version bump (let user decide)

## Notes during implementation

(append as we go)
