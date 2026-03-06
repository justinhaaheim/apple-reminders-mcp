# Apple Reminders Tools - Roadmap

## Vision

A complete Apple Reminders toolkit: MCP server for Claude, CLI for humans and LLMs, and git-backed snapshot system for versioned backups. Full feature parity with Claude iOS Reminders tools.

---

## Milestones

### M1: Safe Testing Infrastructure ✅

Establish a test suite that can't accidentally modify real reminders.

- [x] Test mode (`AR_MCP_TEST_MODE=1`) restricts writes to `[AR-MCP TEST]` lists
- [x] TypeScript test suite with bun test
- [x] Cleanup script for leftover test lists

### M2: Batch Operations ✅

Efficient bulk operations - critical for productivity workflows.

- [x] Create multiple reminders in one call (`create_reminders`)
- [x] Update multiple reminders in one call (`update_reminders`)
- [x] Delete multiple reminders in one call (`delete_reminders`)
- [x] Complete multiple reminders in one call (`complete_reminders`)

### M3: Project Restructure + CLI + Snapshots ✅

Multi-target architecture, CLI tool, and git-backed snapshot system.

- [x] Restructure into AppleRemindersCore library + AppleRemindersMCP + AppleRemindersCLI
- [x] CLI tool (`reminders`) with ArgumentParser
- [x] Git-backed snapshot system (`reminders snapshot`)
- [x] MCP server auto-snapshot integration (disabled by default)
- [x] Single binary with `mcp` subcommand

### M4-next: Audit Log & Data Safety

Paranoid-level logging and data protection.

- [ ] Detailed operation logging (what model requested, what server did)
- [ ] Capture before/after state for all modifications
- [ ] Persist audit log (file or database)
- [ ] Add `list_recent_operations` tool - let model review its own actions
- [ ] Add `undo_operation` tool - revert a specific change

### M4: Enhanced Search ✅

Improve reminder discovery.

- [x] `search_reminders` tool with text search, date range, status, limit
- [x] `search_reminder_lists` tool with text search
- [x] Modeled after Claude iOS `reminder_search_v0` API

### M5: Recurrence Support ✅

- [x] Recurrence rules on create/update
- [x] All patterns: daily, weekly, monthly, yearly
- [x] Days of week, interval, end conditions

### M6: Alarms Support ✅

- [x] Absolute and relative alarms on create/update
- [x] Return alarms in query responses

### M7: URL & Minor Fields ✅

- [x] URL attachment support
- [x] Explicit dueDateIncludesTime boolean

---

## In Progress

- [docs/plans/2026-03-04_project-restructure-cli-snapshots.md](docs/plans/2026-03-04_project-restructure-cli-snapshots.md) - Restructure + CLI + Snapshots

---

## Next Actions

1. **Test CLI on macOS** — Build and verify `reminders` binary against real Apple Reminders. Confirm all commands work end-to-end.

2. **Test snapshot system on macOS** — Run `reminders snapshot` with real data, verify git commits, inspect JSON files.

3. **Rename repo to apple-reminders-tools** — Update GitHub repo name, remotes, and references.

4. **Wire up `reminders mcp` fully** — Ensure the unified binary can replace the standalone `apple-reminders-mcp` in Claude Desktop config.

5. **Add `--format markdown` option** — Human-readable output for CLI queries (alternative to JSON).

---

## Backlog

### Features

- [x] Priority enum (none/low/medium/high) instead of 0-9 integers
- [x] Code refactoring to multiple Swift files (completed 2026-02-28)
- [x] Multi-target restructure (core library + CLI + MCP) (completed 2026-03-05)
- [ ] `--format markdown` for human-readable CLI output
- [ ] Shell completion generation (bash/zsh/fish) via ArgumentParser
- [ ] Scheduled periodic snapshots via launchd
- [ ] Snapshot diff viewer (show what changed between two snapshots)

### Bugs / Issues

_(none currently tracked)_

### Ideas

- AppleScript fallback for operations EventKit can't do (like deleting lists)
- Swift testing for core library (unit tests against MockStore)
- Audit log with before/after state capture
- Undo support (revert specific operations)

---

## Progress Log

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
