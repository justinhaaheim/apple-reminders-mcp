# Apple Reminders MCP Server

A Model Context Protocol (MCP) server that integrates Apple Reminders with Claude Desktop, enabling **comprehensive task management and reminders** directly through conversations with Claude.

**Built entirely in Swift** using EventKit for native, fast, and reliable access to Apple Reminders.

## Why Use This?

Apple Reminders is a full-featured **task management system**, not just for simple reminders. This MCP server unlocks the full power of Apple Reminders for:

- **Task Management**: Create, organize, and track tasks and todo items
- **Project Organization**: Manage projects with separate lists and due dates
- **Daily Planning**: Review what's due today or overdue with `list_today_reminders`
- **Flexible Scheduling**: Set reminders with specific times or just dates
- **Priority Management**: Organize tasks by priority levels (high/medium/low)

## Features

- **List Management**: Create and list reminder lists (task categories)
- **Task Operations**: Create, update, complete, and delete reminders
- **Smart Filtering**: View today's tasks, filter by list or completion status
- **Flexible Dates**: Support for both date-only and datetime formats
- **Priority Levels**: Set task priority (0=none, 1-4=high, 5=medium, 6-9=low)
- **Native Swift**: EventKit integration for maximum performance and reliability

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 5.9 or later
- Claude Desktop app

## Installation

1. Clone this repository
2. Build the Swift package:
```bash
swift build -c release
```

3. The executable will be built at `.build/release/apple-reminders-mcp`

## Configuration

Add this server to your Claude Desktop configuration file at `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/absolute/path/to/apple-reminders-mcp/.build/release/apple-reminders-mcp"
    }
  }
}
```

## Permissions

The first time you run this, macOS will prompt you to grant Reminders access. Click "Allow".

## License

MIT
