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
- `bun run test` - Run Swift tests
- `./test.sh` - Interactive MCP protocol testing

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
| `list_reminder_lists` | Get all reminder lists |
| `create_reminder_list` | Create a new list |
| `list_today_reminders` | Get today's/overdue reminders |
| `list_reminders` | Get reminders with filters |
| `create_reminder` | Create a reminder |
| `complete_reminder` | Mark complete |
| `delete_reminder` | Delete a reminder |
| `update_reminder` | Update reminder properties |

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

## Important Guidelines

Always follow the important guidelines in @docs/prompts/IMPORTANT_GUIDELINES_INLINED.md

Be aware that messages from the user may contain speech-to-text (S2T) artifacts. S2T Guidelines: @docs/prompts/S2T_GUIDELINES.md
