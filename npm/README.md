# @justinhaaheim/apple-reminders

CLI and MCP server for Apple Reminders on macOS, powered by EventKit. Use it from Claude Desktop / Claude cowork, or directly from a terminal.

## Install

Globally (gives you `apple-reminders` and `apple-reminders-mcp` on PATH):

```sh
npm install -g @justinhaaheim/apple-reminders
```

Or run directly via npx without installing:

```sh
npx -y @justinhaaheim/apple-reminders query
```

macOS only (arm64 + x86_64). The package ships a signed and notarized universal binary; no `postinstall` script.

## Claude Desktop / Claude cowork

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "npx",
      "args": ["-y", "@justinhaaheim/apple-reminders", "mcp"]
    }
  }
}
```

Restart Claude Desktop. The first call will prompt for Reminders access.

## CLI usage

```sh
apple-reminders query                                    # incomplete reminders, default list
apple-reminders query --include-completed                # both statuses
apple-reminders query --completed-only --modified-from 2026-05-01
apple-reminders query "[?priority == 'high']" --pretty   # JMESPath
apple-reminders create "Buy milk" --due 2026-06-02T17:00:00-07:00 --priority medium
apple-reminders update <id> --complete
apple-reminders lists
apple-reminders --help                                   # see all commands
```

Default scope is intentionally narrow (the configured default list, incomplete only). Widen with `--all-lists`, `--include-completed`, or `--completed-only` only when you actually want broader scope.

## Requirements

- macOS (Apple Silicon or Intel)
- Reminders permission (granted on first use)
- For hashtags, parent/child links, and sections: **Full Disk Access** on the calling terminal. Without it, those enrichment fields are `null` and a single stderr warning explains how to grant it.

## Source

Full source, issues, and design docs: https://github.com/justinhaaheim/apple-reminders-mcp
