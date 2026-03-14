# PR Review Round 2 Fixes

**Date**: 2026-03-14
**Branch**: `claude/swift-restructuring-feedback-uk0CU`

## Changes Made

### 1. `Logging.swift` — ISO8601DateFormatter thread-safety fix

- Reverted from file-level singleton back to per-call instantiation
- `ISO8601DateFormatter` inherits from `Formatter` (not thread-safe), and `log()`/`logError()` are called from async contexts
- Per-call instantiation is cheap and eliminates the race condition entirely
- Extracted to a `logTimestamp()` helper for DRY

### 2. `SnapshotManager.swift` — True atomic directory swap

- Replaced `removeItem` + `moveItem` pattern with `replaceItemAt(_:withItemAt:)`
- `replaceItemAt` handles the swap atomically on APFS/HFS+, eliminating the window where `dataDir` doesn't exist
- Falls back to `moveItem` when the target doesn't exist yet (first snapshot)

### 3. `SnapshotManager.swift` — `lists.json` included in atomic operation

- Previously `lists.json` was written after the data directory swap, creating a gap where a crash could leave stale list metadata
- Now `lists.json` is written to a temp file first, then atomically swapped into place alongside the data directory

### Not Changed (Acknowledged)

- **Optional `store` in SnapshotManager** — Accepted tradeoff. The guard + clear error message is sufficient. Restructuring the init would add complexity without meaningful benefit.

## Status

- [x] Fix ISO8601DateFormatter thread-safety
- [x] Use replaceItemAt for atomic swap
- [x] Include lists.json in atomic operation
- [x] Build passes
- [x] Tests pass (88/88)
- [x] Committed and pushed
