# CLAUDE.md

## Project Overview

Apple Reminders MCP Server - A Model Context Protocol server that provides Claude with access to Apple Reminders on macOS via EventKit.

**Goal**: Provide an API similar to Claude iOS's Reminders tools, enabling reminder creation, search, update, deletion, and management with full feature support (alarms, recurrence, etc.).

## Development Commands

### Building
- `bun run build` - Build release binary (`.build/release/apple-reminders-mcp`)
- `bun run build:debug` - Build debug binary
- `swift build` - Direct Swift build

### Running
- `bun run run` - Run the built release binary
- `.build/release/apple-reminders-mcp` - Direct execution

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
└── main.swift    # All MCP server and EventKit code
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

## Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/path/to/apple-reminders-mcp/.build/release/apple-reminders-mcp"
    }
  }
}
```

## Future Enhancements

- [ ] Add alarm support (absolute + relative)
- [ ] Add recurrence/RRULE support
- [ ] Add text search in reminder titles/notes
- [ ] Add date range filtering
- [ ] Add batch operations
- [ ] Match Claude iOS API more closely

## Issue Tracking with Beads @AGENTS.md

This project uses [beads](https://github.com/steveyegge/beads) (`bd`) for granular issue/task tracking alongside markdown scratchpads (which remain the primary tool for design notes, architecture decisions, and session planning).

### Quick Reference

```bash
bd ready              # Find available work (no blockers, highest priority)
bd list               # List all issues
bd show <id>          # View issue details
bd create "title" -p 1  # Create a new issue (priority 1-4)
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

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

