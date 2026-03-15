# Pagination & Remove Limit

**Date**: 2026-03-15
**Branch**: `claude/pagination-remove-limit-Tr7zQ`

## Goal

Remove the artificial default limit (50) and hard max (200) on `query_reminders`, and add offset-based pagination support.

## Current State

- `queryReminders()` in RemindersManager.swift uses `min(limit ?? 50, 200)` — caps at 200
- No `offset` parameter exists
- MCP schema declares `minimum: 1, maximum: 200, default: 50`
- CLI help says "Maximum number of results (default: 50, max: 200)"

## Plan

### 1. RemindersManager.swift

- [x] Add `offset: Int?` parameter to `queryReminders()`
- [x] Remove `min(limit ?? 50, 200)` — if no limit, return all results
- [x] Apply offset before limit (skip N, then take limit)
- [x] Apply in both code paths (JMESPath and normal)

### 2. MCPServer.swift

- [x] Update `query_reminders` schema: remove `maximum`/`default` from limit, add `offset`
- [x] Extract `offset` from arguments and pass to `queryReminders()`

### 3. QueryCommand.swift (CLI)

- [x] Add `--offset` flag
- [x] Update `--limit` help text (remove "default: 50, max: 200")
- [x] Pass offset to `queryReminders()`

### 4. HelpContent.swift

- [x] Update references to limit defaults

### 5. Tests

- [x] Verify existing limit test still passes
- [x] Add offset test

### 6. Documentation

- [x] Update SKILL.md
- [x] Update CLAUDE.md

## Progress

- [ ] Implementation complete
- [ ] Tests pass
- [ ] Quality gates pass
- [ ] Committed and pushed
