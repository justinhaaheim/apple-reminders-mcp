# PR Review Feedback Fixes

**Date**: 2026-03-12
**Branch**: `claude/swift-restructuring-feedback-uk0CU`

## Summary

Addressing feedback from the multi-target Swift restructure PR review. All actionable issues (bugs, medium, and select low-priority items) from the review have been fixed.

## Changes Made

### Bugs Fixed

- [x] **#1**: `ProcessInfo.processInfo.environment` caching - switched to `getenv()` in `Configuration.swift` so `--test-mode` and `--mock` CLI flags actually work
- [x] **#2**: Non-atomic snapshot directory replacement - writes to temp dir first, then atomically swaps with live dir; cleans up temp on failure

### Medium Issues Fixed

- [x] **#3**: Version inconsistency - MCPServer now uses `appVersion` instead of hardcoded `"2.0.0"`
- [x] **#4**: Duplicate `AnyEncodable` - made `MCPTypes.AnyEncodable` `public`, removed duplicate from `Reminders.swift`
- [x] **#5**: Duplicate error types - removed `MCPToolError`, replaced all usages with `RemindersError`
- [x] **#6**: Double JSON decode in `handleRequest()` - single decode with nested error handling
- [x] **#7**: Missing `defer` for file handle close in `AuditLogger.writeEntry()`
- [x] **#8**: Git config for initial commit in `SnapshotManager` - sets local `user.email` and `user.name`
- [x] **#9**: Hoisted `ISO8601DateFormatter` to file-level constant in `Logging.swift`

### Low-Priority Issues Fixed

- [x] **#11**: Removed unnecessary `ReminderStore` creation from `SnapshotStatusCommand` and `SnapshotDiffCommand` (made `store` optional in `SnapshotManager`)

### Not Addressed (Design Notes / Low Priority)

- **#10**: `getStatus()` swallowing git errors - acceptable behavior for status reporting
- **#12**: CLI create only supports one alarm - documented gap, would need CLI design work
- **#13**: npm `cpu` field - nice to have, not critical
- **#14**: npm-publish version sync fragility - low risk in practice
- **#15**: Snapshot default subcommand naming - current UX is fine
