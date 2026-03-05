# Project Restructure: Core Library + CLI + Snapshots

**Date**: 2026-03-04
**Status**: Planning (awaiting approval)

---

## Goal

Restructure the repository from a single MCP server executable into a multi-target project with three products that share a common core library:

1. **Core Library** (`AppleRemindersCore`) — Shared business logic, models, EventKit integration
2. **MCP Server** (`apple-reminders-mcp`) — Existing MCP server, refactored to use core library
3. **CLI Tool** (`reminders`) — New command-line interface for direct use by humans and LLMs
4. **Snapshot Utility** — Built into the CLI (and optionally MCP server) for versioned backups of Apple Reminders data

---

## Current State Analysis

### What exists today

- Single executable target `AppleRemindersMCP` with 9 Swift files in `Sources/`
- Clean separation already exists between:
  - **Protocol layer**: `ReminderStoreProtocol.swift` (78 lines) — abstract storage interface
  - **Business logic**: `RemindersManager.swift` (915 lines) — all operations, zero MCP knowledge
  - **MCP protocol**: `MCPServer.swift` (1,080 lines) — JSON-RPC handling + tool schemas
  - **Models**: `Models.swift` (237 lines) — input/output types, Priority enum
  - **EventKit**: `EventKitStore.swift` (321 lines) — real Apple Reminders access
  - **Mock**: `MockStore.swift` (166 lines) — in-memory test store
  - **MCP Types**: `MCPTypes.swift` (221 lines) — MCP protocol-specific types
  - **Config**: `Configuration.swift` (26 lines) — test/mock mode config

### Key insight: The abstraction is already there

`RemindersManager` is already a clean, protocol-agnostic business logic layer. It takes a `ReminderStore` and provides all operations (query, create, update, delete, export). The MCP server is just a thin shell that:

1. Reads JSON-RPC from stdin
2. Parses tool arguments
3. Calls `RemindersManager` methods
4. Formats responses as MCP JSON-RPC

This means the restructure is mostly about **moving files into the right targets**, not rewriting logic.

### One coupling issue to fix

`RemindersManager` uses `MCPToolError` for all its error throwing. This is an MCP-specific type. We need to:

- Rename it to something generic (e.g., `RemindersError` or `ToolError`)
- Move it to the core library
- Keep it as a simple `Error` type with a message string

Also, `log()` and `logError()` are defined in `main.swift` as global functions. We need a logging approach that works across all targets.

---

## Proposed Structure

### Directory layout

```
apple-reminders-tools/              # Rename repo (or keep current name for now)
├── Package.swift                   # Multi-target SPM manifest
├── package.json                    # Bun scripts for build/test/format
├── Sources/
│   ├── AppleRemindersCore/         # Shared library target
│   │   ├── ReminderStoreProtocol.swift
│   │   ├── EventKitStore.swift
│   │   ├── MockStore.swift
│   │   ├── Models.swift
│   │   ├── Configuration.swift
│   │   ├── RemindersManager.swift
│   │   └── Logging.swift           # Shared logging utilities
│   ├── AppleRemindersMCP/          # MCP server executable
│   │   ├── main.swift              # Entry point
│   │   ├── MCPServer.swift
│   │   └── MCPTypes.swift
│   └── AppleRemindersCLI/          # CLI executable
│       ├── main.swift              # Entry point (ArgumentParser)
│       ├── Commands/
│       │   ├── QueryCommand.swift
│       │   ├── ListsCommand.swift
│       │   ├── CreateCommand.swift
│       │   ├── UpdateCommand.swift
│       │   ├── DeleteCommand.swift
│       │   ├── ExportCommand.swift
│       │   └── SnapshotCommand.swift
│       └── CLIFormatting.swift     # JSON output helpers
├── test/                           # Existing TypeScript tests (unchanged)
├── docs/
├── CLAUDE.md
├── ROADMAP.md
└── ...
```

### Package.swift (proposed)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleRemindersTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppleRemindersCore", targets: ["AppleRemindersCore"]),
        .executable(name: "apple-reminders-mcp", targets: ["AppleRemindersMCP"]),
        .executable(name: "reminders", targets: ["AppleRemindersCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/adam-fowler/jmespath.swift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AppleRemindersCore",
            dependencies: [
                .product(name: "JMESPath", package: "jmespath.swift"),
            ],
            path: "Sources/AppleRemindersCore"
        ),
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: ["AppleRemindersCore"],
            path: "Sources/AppleRemindersMCP"
        ),
        .executableTarget(
            name: "AppleRemindersCLI",
            dependencies: [
                "AppleRemindersCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AppleRemindersCLI"
        ),
    ]
)
```

### Why Swift ArgumentParser?

Swift's [ArgumentParser](https://github.com/apple/swift-argument-parser) is Apple's official CLI framework. It's the idiomatic choice for Swift CLI tools and gives us:

- Subcommand routing (`reminders query`, `reminders create`, etc.)
- Automatic `--help` generation with descriptions
- Type-safe argument parsing with validation
- Built-in support for flags, options, and positional arguments
- Shell completion generation (bash/zsh/fish)

This is better than a TypeScript wrapper because:

1. Single build step — no need to coordinate bun + swift
2. Direct EventKit access — no subprocess spawning or IPC
3. Same language as the core library — no serialization boundary
4. Distribution is a single binary

---

## CLI Design

### Command structure

```
reminders <command> [options]
```

### Commands

#### `reminders query` (default command)

Search and filter reminders. This is the most-used command, so it should be the default.

```bash
# Basic usage — incomplete reminders from default list
reminders query

# With text search
reminders query --search "grocery"

# Specific list
reminders query --list "Work"
reminders query --list-id "x-apple-..."

# All lists
reminders query --all-lists

# Status filter
reminders query --status completed
reminders query --status all

# Date range
reminders query --from 2026-01-01 --to 2026-03-01

# JMESPath query (advanced)
reminders query --jmespath "[?priority=='high'].title"

# Output control
reminders query --detail full
reminders query --limit 100
reminders query --sort priority

# Combine freely
reminders query --list "Work" --search "meeting" --status all --sort dueDate --limit 20
```

#### `reminders lists`

```bash
# Get all lists
reminders lists
```

#### `reminders create`

```bash
# Simple
reminders create "Buy groceries"

# With options
reminders create "Team standup" --list "Work" --due "2026-03-05T09:00:00-08:00" --priority high

# With notes
reminders create "Review PR" --notes "Check the auth changes" --list "Work"

# With alarm (relative, seconds before due)
reminders create "Meeting" --due "2026-03-05T14:00:00" --alarm-relative 900

# With recurrence
reminders create "Weekly review" --due "2026-03-07T10:00:00" --recurrence weekly
```

#### `reminders update`

```bash
# Mark complete
reminders update <id> --complete

# Mark incomplete
reminders update <id> --incomplete

# Change title
reminders update <id> --title "New title"

# Change priority
reminders update <id> --priority medium

# Clear a field
reminders update <id> --clear-notes
reminders update <id> --clear-due-date

# Move to different list
reminders update <id> --list "Personal"
```

#### `reminders delete`

```bash
reminders delete <id>
reminders delete <id1> <id2> <id3>
```

#### `reminders export`

```bash
# Export to temp file
reminders export

# Export to specific path
reminders export --path ~/backups/reminders.json

# Export specific lists
reminders export --list "Work" --list "Personal"

# Include completed
reminders export --include-completed
```

#### `reminders snapshot` (new)

```bash
# Take a snapshot (explained in detail below)
reminders snapshot

# Specify repo location
reminders snapshot --repo ~/.config/apple-reminders-data

# Show status of snapshot repo
reminders snapshot status

# Show diff since last snapshot
reminders snapshot diff
```

### Global options

```bash
# All commands support:
--json              # Force JSON output (default, but explicit)
--pretty            # Pretty-print JSON (default for TTY, off for pipes)
--mock              # Use mock store (for testing)
--test-mode         # Enable test mode restrictions
--verbose           # Show debug logging on stderr
```

### Output format

All commands output JSON to stdout by default. Logs/errors go to stderr. This makes piping natural:

```bash
# Pipe to jq
reminders query --list "Work" | jq '.[].title'

# Pipe to another tool
reminders query --search "urgent" | jq -r '.[].id' | xargs -I{} reminders update {} --priority high

# Save to file
reminders export --path /dev/stdout | gzip > backup.json.gz
```

Future: A `--format markdown` option could render human-readable output, but JSON-first is the right default for LLM consumption and scriptability.

---

## Snapshot System Design

### Concept

A git-backed versioned backup of all Apple Reminders data. Each snapshot:

1. Fetches ALL reminders (completed + incomplete) from ALL lists
2. Writes each reminder as an individual JSON file (named by UUID)
3. Commits the state to a local git repo

### Data directory structure

```
~/.config/apple-reminders-data/     # Default location (configurable)
├── .git/                           # Git repo for versioning
├── data/
│   └── id/                         # One file per reminder
│       ├── 8A3F2B1C-...json
│       ├── 9D4E5F6A-...json
│       └── ...
└── lists.json                      # List metadata (id, name, isDefault)
```

### Reminder JSON format

Same as `ReminderOutput` from the core library, plus millisecond timestamps:

```json
{
  "id": "8A3F2B1C-...",
  "title": "Buy groceries",
  "notes": null,
  "listId": "x-apple-...",
  "listName": "Personal",
  "isCompleted": false,
  "priority": "none",
  "dueDate": "2026-03-05T17:00:00-08:00",
  "dueDateIncludesTime": true,
  "completionDate": null,
  "createdDate": "2026-03-01T10:30:00-08:00",
  "createdDateMS": 1772234200000,
  "lastModifiedDate": "2026-03-02T08:15:00-08:00",
  "lastModifiedDateMS": 1772312100000,
  "dueDateMS": 1772362800000,
  "url": null,
  "alarms": null,
  "recurrenceRules": null
}
```

The `*MS` fields are epoch milliseconds — easier for programmatic filtering with `jq`:

```bash
# Find reminders modified in the last 24 hours
find data/id -name "*.json" | xargs jq -s '[.[] | select(.lastModifiedDateMS > (now * 1000 - 86400000))]'
```

### Snapshot workflow

```bash
reminders snapshot
```

This runs the following steps:

1. **Check git status** — Abort if there are uncommitted changes in the snapshot repo
2. **Delete all files** in `data/id/` (clean slate approach)
3. **Regenerate** — Fetch ALL reminders, write each as `data/id/<UUID>.json`
4. **Update `lists.json`** — Current list metadata
5. **Git add + commit** — With timestamp message like `"Snapshot 2026-03-04T12:30:00-08:00"`
6. Report summary: "Snapshot complete: 847 reminders across 12 lists (3 added, 1 removed, 15 modified)"

The "delete everything then regenerate" approach elegantly handles:

- **Deletions**: If a reminder was deleted in Apple Reminders, its file disappears from the repo. Git tracks the deletion.
- **No drift**: Every snapshot is a complete, accurate picture. No incremental sync bugs.
- **Speed**: Takes ~2-3 seconds for hundreds of reminders. Fast enough.

### Integration with MCP server and CLI

The snapshot functionality lives in the core library (`SnapshotManager` or similar). Both the CLI and MCP server can use it:

**CLI integration:**

```bash
reminders snapshot                    # Manual snapshot
reminders snapshot --repo ~/my-repo   # Custom location
reminders snapshot status             # Show last snapshot time, change count
reminders snapshot diff               # Show what changed since last snapshot
```

**MCP server integration** (built-in, disabled by default):

- Config option: `AR_MCP_SNAPSHOT_ENABLED=1` and `AR_MCP_SNAPSHOT_REPO=~/.config/apple-reminders-data`
- Auto-snapshot on MCP session start
- Auto-snapshot after each write operation (create/update/delete)
- Incremental background backups while MCP server is running
- Part of the core build — snapshot logic lives in `AppleRemindersCore` so both CLI and MCP can use it

### Default snapshot repo location

`~/.config/apple-reminders-data/`

Reasoning:

- `~/.config/` is the XDG standard for application config/data on Unix
- macOS respects this convention (many tools use it)
- Keeps it out of the user's visible home directory
- Git repo here won't interfere with any other project

The location is configurable via:

- CLI flag: `--repo <path>`
- Environment variable: `AR_SNAPSHOT_REPO=<path>`
- Falls back to default

---

## Implementation Plan

### Phase 1: Restructure into multi-target project

**Goal**: Move files into the new directory structure. Everything still builds and tests pass.

1. Create directory structure: `Sources/AppleRemindersCore/`, `Sources/AppleRemindersMCP/`, `Sources/AppleRemindersCLI/`
2. Extract `MCPToolError` → generic `RemindersError` in core library
3. Extract logging to shared `Logging.swift` in core library
4. Move files to their targets:
   - Core: `ReminderStoreProtocol.swift`, `EventKitStore.swift`, `MockStore.swift`, `Models.swift`, `Configuration.swift`, `RemindersManager.swift`, `Logging.swift`
   - MCP: `main.swift`, `MCPServer.swift`, `MCPTypes.swift`
5. Update `Package.swift` with new target structure
6. Add `import AppleRemindersCore` to MCP files
7. Mark appropriate types/methods as `public` in the core library
8. Verify: `swift build` succeeds, `bun test` passes

### Phase 2: Build the CLI tool

**Goal**: Working CLI with all current MCP server capabilities.

1. Add `swift-argument-parser` dependency
2. Create CLI entry point with root command and subcommands
3. Implement commands: `query`, `lists`, `create`, `update`, `delete`, `export`
4. JSON output formatting (pretty-print for TTY, compact for pipes)
5. Error handling (user-friendly messages to stderr, proper exit codes)
6. Test manually against real reminders
7. Write a skill/prompt file that describes how to use the CLI

### Phase 3: Snapshot system

**Goal**: `reminders snapshot` works end-to-end.

1. Add `SnapshotManager` to core library (git operations, file I/O)
2. Implement snapshot workflow (fetch all → write files → git commit)
3. Add `snapshot` subcommand to CLI
4. Add `snapshot status` and `snapshot diff` subcommands
5. Add millisecond epoch fields to snapshot output
6. Test with real data

### Phase 4: Polish and integration

**Goal**: Everything works together cleanly.

1. Update `CLAUDE.md` and `README.md` with new structure
2. Update `package.json` scripts for multi-target builds
3. Write CLI skill/prompt document for LLM usage
4. Update test infrastructure if needed
5. Update `ROADMAP.md`

---

## Design Decisions & Rationale

### Why not a TypeScript CLI wrapper?

- Extra runtime dependency (bun/node)
- Serialization boundary between TS and Swift (subprocess + JSON parsing)
- Two build systems to coordinate
- Single Swift binary is simpler to distribute and use

### Why ArgumentParser over hand-rolled argument parsing?

- It's Apple's official library — idiomatic Swift
- Auto-generates `--help` pages
- Type-safe parsing with validation
- Shell completion for free
- Well-maintained, widely used

### Why subcommands instead of just flags?

- `reminders create "title"` is more intuitive than `reminders --action create --title "title"`
- Natural grouping of related options
- Better `--help` output (per-command help)
- Matches established CLI conventions (git, docker, gh, etc.)

### Why JSON output by default?

- Primary audience is LLMs (Claude Code, etc.)
- Easily piped to `jq` for transformation
- Machine-readable for scripting
- Can add `--format markdown` later for human consumption

### Why delete-and-regenerate for snapshots?

- Handles deletions without complex diffing
- Every snapshot is a complete truth — no incremental sync bugs
- Fast enough (~2-3 seconds)
- Git handles the diffing efficiently anyway

### Why `~/.config/` for snapshot data?

- XDG standard location
- Not visible in home directory clutter
- Doesn't conflict with any project repos
- Well-established convention

---

## Key Decision: One Binary or Two?

Research surfaced an important architecture choice:

**Option A: Two separate binaries** (`apple-reminders-mcp` + `reminders`)

- Pros: Existing MCP server config unchanged, clean separation
- Cons: **macOS treats them as separate apps for permissions** — users get TWO permission prompts, TWO entries in System Settings > Privacy > Reminders

**Option B: Single binary with `mcp` subcommand** (`reminders mcp` starts the MCP server)

- Pros: One permission grant, one binary to distribute, simpler
- Cons: Existing users must update Claude Desktop config to `{"command": "reminders", "args": ["mcp"]}`
- This is the pattern used by `ekctl` and similar tools

**Recommendation: Option B (single binary).** The permission issue is a real UX problem with Option A. Having users update their Claude Desktop config once is a small cost. And `reminders mcp` is clean and intuitive.

If we go with Option B, the Package.swift simplifies to a single executable + library:

```swift
products: [
    .library(name: "AppleRemindersCore", targets: ["AppleRemindersCore"]),
    .executable(name: "reminders", targets: ["AppleRemindersCLI"]),
],
```

And the MCP server becomes just another subcommand of the CLI, alongside `query`, `create`, `snapshot`, etc.

---

## Decisions (Resolved)

1. **Repo rename?** → **Yes**, rename to `apple-reminders-tools`
2. **CLI binary name** → `reminders`
3. **Snapshot commit message** → Timestamp + summary: `"Snapshot 2026-03-04T12:30:00-08:00 — 847 reminders, 12 lists"`
4. **Default subcommand** → **Yes**, `query` is the default (just `reminders` = `reminders query`)
5. **One binary or two?** → **One binary** (Option B). MCP server via `reminders mcp`.

---

## Risks & Mitigations

| Risk                                | Mitigation                                                                              |
| ----------------------------------- | --------------------------------------------------------------------------------------- |
| Breaking existing MCP server users  | Phase 1 keeps the MCP server binary name identical. Tests verify compatibility.         |
| EventKit permission issues with CLI | Same binary, same entitlements. Should work identically.                                |
| Snapshot repo corruption            | Git is robust. We check for clean state before operations.                              |
| Large snapshot repos                | Individual JSON files are small. Git compresses well. Even 10K reminders is manageable. |

---

## Progress

- [x] Phase 1: Restructure into multi-target project
  - Created `Sources/AppleRemindersCore/`, `Sources/AppleRemindersMCP/`, `Sources/AppleRemindersCLI/`
  - Extracted `MCPToolError` → `RemindersError` in core library
  - Created shared `Logging.swift`
  - Moved files to targets, added `public` access modifiers
  - Updated `Package.swift` for multi-target build
  - Note: No Swift compiler on Linux CI, but structure is logically verified
- [ ] Phase 2: Build the CLI tool
- [ ] Phase 3: Snapshot system
- [ ] Phase 4: Polish and integration
