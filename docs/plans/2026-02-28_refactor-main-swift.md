# Refactor main.swift into separate files

**Date:** 2026-02-28
**Status:** In Progress

## Goal

Break the monolithic 3063-line `Sources/main.swift` into 9 logical files. Pure cut-and-paste — no logic changes.

## File Plan

| File                          | Contents                            | Status |
| ----------------------------- | ----------------------------------- | ------ |
| `main.swift`                  | Top-level entry point + logging     | [x]    |
| `Configuration.swift`         | `TestModeConfig`, `MockModeConfig`  | [x]    |
| `ReminderStoreProtocol.swift` | Protocol layer + model types        | [x]    |
| `EventKitStore.swift`         | EK wrappers + EKReminderStore       | [x]    |
| `MockStore.swift`             | Mock implementations                | [x]    |
| `MCPTypes.swift`              | MCP protocol types + JSON helpers   | [x]    |
| `Models.swift`                | API data models, input/output types | [x]    |
| `RemindersManager.swift`      | RemindersManager class              | [x]    |
| `MCPServer.swift`             | MCPServer class                     | [x]    |

## Verification

- [x] `bun run build` succeeds
- [x] `bun run test` passes (88 tests, 300 assertions)
- [x] `bun run signal` clean

## Notes

- Used top-level code style in `main.swift` (not `@main`) because Swift treats `main.swift` as the top-level entry point file — `@main` conflicts with this.
- No `Package.swift` changes needed — `path: "Sources"` picks up all `.swift` files automatically.
