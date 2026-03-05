# CLAUDE.md

## Project Overview

Apple Reminders Tools — A multi-target Swift project providing access to Apple Reminders on macOS via EventKit:

1. **Core Library** (`AppleRemindersCore`) — Shared business logic, models, EventKit integration
2. **MCP Server** (`apple-reminders-mcp`) — Model Context Protocol server for Claude Desktop
3. **CLI Tool** (`reminders`) — Command-line interface for direct use by humans and LLMs
4. **Snapshot System** — Git-backed versioned backups of all Apple Reminders data

**Goal**: Provide an API similar to Claude iOS's Reminders tools, enabling reminder creation, search, update, deletion, and management with full feature support (alarms, recurrence, etc.).

## Development Commands

### Building
- `bun run build` - Build all release binaries
- `bun run build:debug` - Build debug binaries
- `swift build` - Direct Swift build (all targets)
- `swift build --product reminders` - Build only the CLI
- `swift build --product apple-reminders-mcp` - Build only the MCP server

### Running
- `.build/release/reminders` - Run the CLI tool
- `.build/release/reminders query` - Query reminders (default command)
- `.build/release/reminders mcp` - Start MCP server via CLI
- `.build/release/apple-reminders-mcp` - Run standalone MCP server

### Code Quality
- `bun run signal` - Check formatting with Prettier
- `bun run prettier` - Format all files
- `bun run prettier-check` - Check formatting without modifying

### Testing
- `bun run test` - Run TypeScript tests (isolated to test lists, safe)
- `bun run test:cleanup` - Delete leftover test lists (with confirmation prompt)
- `./test/interactive.sh` - Interactive MCP protocol debugging

**Test Safety**: Tests run with `AR_MCP_TEST_MODE=1` which restricts all write operations to lists prefixed with `[AR-MCP TEST]`. This prevents tests from modifying your real reminders.

## Architecture

### MCP Protocol
- Communicates via JSON-RPC 2.0 over stdio
- Implements `initialize`, `tools/list`, and `tools/call` methods

### EventKit Integration
- Uses `EKEventStore` for reminder access
- Requires Full Disk Access / Reminders permission on first run

### Source Structure
```
Sources/
├── AppleRemindersCore/          # Shared library target
│   ├── Logging.swift            # Shared log()/logError() utilities
│   ├── RemindersError.swift     # Generic error type (replaces MCPToolError)
│   ├── Configuration.swift      # TestModeConfig, MockModeConfig
│   ├── ReminderStoreProtocol.swift # ReminderStore protocol, model types
│   ├── EventKitStore.swift      # EKCalendarWrapper, EKReminderWrapper, EKReminderStore
│   ├── MockStore.swift          # MockCalendar, MockReminder, MockReminderStore
│   ├── Models.swift             # API data models, input/output types, Priority, Date ext
│   ├── RemindersManager.swift   # RemindersManager class (business logic)
│   ├── MCPServer.swift          # MCPServer class (protocol handling, tool definitions)
│   ├── MCPTypes.swift           # MCPRequest, MCPResponse, JSONValue, AnyCodable
│   └── SnapshotManager.swift    # Git-backed snapshot system
├── AppleRemindersMCP/           # Standalone MCP server executable
│   └── main.swift               # Entry point (delegates to MCPServer)
└── AppleRemindersCLI/           # CLI executable
    ├── Reminders.swift          # Root command + global options + helpers
    ├── QueryCommand.swift       # reminders query
    ├── ListsCommand.swift       # reminders lists
    ├── CreateCommand.swift      # reminders create
    ├── CreateListCommand.swift  # reminders create-list
    ├── UpdateCommand.swift      # reminders update
    ├── DeleteCommand.swift      # reminders delete
    ├── ExportCommand.swift      # reminders export
    ├── SnapshotCommand.swift    # reminders snapshot [take|status|diff]
    └── MCPCommand.swift         # reminders mcp
```

## Available Tools

| Tool | Description |
|------|-------------|
| `query_reminders` | Search and filter reminders with JMESPath support |
| `get_lists` | Get all reminder lists |
| `create_list` | Create a new list |
| `create_reminders` | Create one or more reminders (batch) |
| `update_reminders` | Update reminders including mark complete/incomplete (batch) |
| `delete_reminders` | Delete reminders (batch) |
| `export_reminders` | Export reminders to JSON file for backup |

## CLI Usage

```bash
# Query reminders (default command)
reminders query --list "Work" --search "meeting" --status incomplete

# List all reminder lists
reminders lists

# Create a reminder
reminders create "Buy groceries" --list "Personal" --due "2026-03-05T17:00:00-08:00"

# Update a reminder
reminders update <id> --complete
reminders update <id> --title "New title" --priority high

# Delete reminders
reminders delete <id1> <id2>

# Export reminders
reminders export --path ~/backup.json --include-completed

# Take a snapshot (git-backed backup)
reminders snapshot
reminders snapshot status

# Start MCP server
reminders mcp
```

All commands output JSON to stdout. Use `--pretty` for human-readable output. Use `--mock` for testing.

## Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/path/to/.build/release/reminders",
      "args": ["mcp"]
    }
  }
}
```

Or use the standalone binary (backward compatible):

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/path/to/.build/release/apple-reminders-mcp"
    }
  }
}
```

## Snapshot Configuration

For auto-snapshots via MCP server, set environment variables:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/path/to/.build/release/reminders",
      "args": ["mcp"],
      "env": {
        "AR_MCP_SNAPSHOT_ENABLED": "1",
        "AR_MCP_SNAPSHOT_REPO": "~/.config/apple-reminders-data"
      }
    }
  }
}
```

## Completed Enhancements

- [x] Add alarm support (absolute + relative)
- [x] Add recurrence/RRULE support
- [x] Add text search in reminder titles/notes
- [x] Add date range filtering
- [x] Add batch operations
- [x] Match Claude iOS API more closely
- [x] Multi-target restructure (core library + CLI + MCP)
- [x] CLI tool with ArgumentParser
- [x] Git-backed snapshot system
- [x] MCP server auto-snapshot integration

## Issue Tracking with Beads

@AGENTS.md

This project uses [beads](https://github.com/steveyegge/beads) (`bd`) for granular issue/task tracking alongside markdown scratchpads (which remain the primary tool for design notes, architecture decisions, and session planning).

### When to Use Beads vs Scratchpads

- **Beads**: Concrete tasks, bugs, TODOs, trackable work items with status and dependencies
- **Scratchpads**: Design exploration, architecture decisions, session context, work plans

### Installation (Local)

```bash
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
```

On Claude Code Web, `bd` is installed automatically via the SessionStart hook.

## Important Guidelines

Always follow the important guidelines in @docs/prompts/IMPORTANT_GUIDELINES_INLINED.md

Follow the protocol in @docs/prompts/PROJECT_STATE_PROTOCOLS.md

Be aware that messages from the user may contain speech-to-text (S2T) artifacts. S2T Guidelines: @docs/prompts/S2T_GUIDELINES.md

