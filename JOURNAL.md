# Journal

Dated observations, decisions and dead ends, newest first. Work items live in beads (`br`), not here.

## 2026-10-16 — Retired ROADMAP.md and the project-state protocol

ROADMAP.md, `docs/prompts/PROJECT_STATE_PROTOCOLS.md` and the "use bd plus markdown scratchpads" section of CLAUDE.md contradicted `.claude/rules/justin-sdk/critical-rules.md` (beads only, no ROADMAP, no `docs/plans` scratchpads), and every session got both instructions. Removed them, plus `.claude/hooks/session-start.sh`, which ran the deleted `scripts/setup-env.ts` on every session start and told web sessions to use `bd` (justin-sdk's own SessionStart hook does the environment setup). ROADMAP's still-open ideas became P4 beads; its progress log is copied verbatim below; its full text is at `git show 7f97640:ROADMAP.md`. The one project-memory note (don't widen query scope) was already in SKILL.md, CLAUDE.md and the MCP tool descriptions; its reasoning is the 2026-05-24 entry below.

## 2026-10-16 — Consumers run an installed copy, never `.build/`

Claude Desktop, `~/Dev/life` (its `.mcp.json`, `scripts/sync-beads-to-reminders.ts`, `scripts/daily-loop/runner-preflight.ts`) and the 09:00 daily-loop launchd job all ran `.build/release/reminders` from this checkout. From 2026-06-13 to 2026-10-16 that binary held the unmerged `api-tweaks-status-priority` branch (PR #18), because it was built while that branch was checked out and an automated justin-sdk sweep switched the checkout to main on 2026-09-12 without rebuilding. A rebuild on main in that window would have silently removed `delete_list`, the priority unification and the fail-loud input validation.

Decision: `bun run install:local` builds the committed sources into `.build-install/` and installs `~/.local/bin/reminders` (previous copy kept as `reminders.prev`; each install logged with its commit in `~/.local/share/apple-reminders-mcp/installs.jsonl`). Consumers point at `/Users/jhaa/.local/bin/reminders` (this repo's `.mcp.json` uses `${HOME}/.local/bin/reminders`, which Claude Code expands). The binary links only system libraries, so the copy is portable.

Unverified: whether macOS ties the Reminders / Full Disk Access grant to the `reminders` binary's own path in headless (launchd) runs. The life repo found the grant keyed to the resolved `claude` path, and that the broken mode hangs rather than errors (2026-09-11); verify any consumer you move before its next unattended run.

## 2026-05-24 — Query scope stays narrow unless the user asks

Defaults are incomplete reminders from the default list. Justin flagged widening twice in one session: `--status all` added unprompted to a "json dump of reminders created in the last 7 days OR with priority" request (about twice as noisy with archived items), then a gratuitous `--all-lists`. The API was reshaped in response (epic apple-reminders-mcp-ko3, PR #18): `--status all` was removed in favour of `--include-completed` / `--completed-only`, named so that widening reads as a deliberate opt-in. Ambiguous asks ("all reminders matching X", "a dump of X", and counts or summaries of X) mean the open ones in the default list; ask before widening. The rule itself lives in SKILL.md, CLAUDE.md and the `query_reminders` parameter descriptions.

## 2026-03-14 — Snapshots stay on git, not Dolt

A web session compared Dolt with the git-backed snapshot store (branch archived as `archive/claude/investigate-dolt-versioning-kHv3b`, note at `docs/plans/2026-03-14_dolt-vs-git-snapshot-investigation.md` there). Conclusion: stay with git. Dolt is a ~103 MB Go binary with no Swift integration, its advantages (O(diff) diffs, SQL over history) do not materialise at hundreds to low thousands of reminders, and file-per-reminder JSON gives readable diffs. If structured history queries are ever needed, add a SQLite index over the git history instead.

## Progress log moved verbatim from ROADMAP.md (2026-10-16)

### 2026-03-05

- ✅ Completed M3: Project Restructure + CLI + Snapshots
- Restructured into multi-target project: AppleRemindersCore (library) + AppleRemindersMCP (exe) + AppleRemindersCLI (exe)
- Built `reminders` CLI with ArgumentParser: query, lists, create, create-list, update, delete, export, snapshot, mcp
- Implemented git-backed snapshot system (delete-and-regenerate, individual JSON files per reminder)
- Wired auto-snapshot into MCP server (disabled by default, AR_MCP_SNAPSHOT_ENABLED=1)
- Single binary architecture: `reminders mcp` replaces standalone MCP server

### 2026-01-18

- ✅ Completed M4: Enhanced Search
- Added `search_reminders` tool (text search, date range, status filter, limit)
- Added `search_reminder_lists` tool (text search)
- Modeled after Claude iOS `reminder_search_v0` API
- 38 tests passing
- Pushed to GitHub: https://github.com/justinhaaheim/apple-reminders-mcp

### 2026-01-10

- ✅ Completed M2: Batch Operations
- Added 4 batch tools: `create_reminders`, `update_reminders`, `delete_reminders`, `complete_reminders`
- Implemented input validation layer (Codable structs, like Zod pattern)
- Partial success support with per-item results + summary
- 24 tests passing (added batch.test.ts)

### 2025-12-29

- ✅ Completed M1: Safe Testing Infrastructure
- Added test mode with `AR_MCP_TEST_MODE=1`
- Created TypeScript test suite (15 tests)
- Added cleanup script for test lists
- Created ROADMAP.md
- Reprioritized: Batch ops → Audit/Safety → Search → Recurrence → Alarms → URL

### 2025-12-26

- Forked farmerajf/apple-reminders-mcp
- Set up project tooling (husky, prettier, .claude/, .vscode/)
- Created CLAUDE.md and improvement scratchpad
