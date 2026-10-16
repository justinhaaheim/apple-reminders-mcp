# Apple Reminders MCP Server and CLI

Native Swift access to Apple Reminders on macOS through EventKit, as both an MCP server (for Claude Desktop and Claude Code) and a `reminders` command-line tool for humans and LLMs. Forked from [farmerajf/apple-reminders-mcp](https://github.com/farmerajf/apple-reminders-mcp).

## Features

- Query reminders with structured filters (list, completion, text search, created / modified / due date ranges, hashtag, parent, section) plus JMESPath for filtering and projecting the result
- Create, update, complete and delete reminders in batches, with alarms, recurrence, URLs and priorities
- Create and delete lists
- Read-only enrichment from Apple's Reminders database: hashtags, subtasks (parent / child) and list sections, which EventKit does not expose
- Export to JSON, git-backed snapshots, and a JSONL audit log of every change
- Tiered help: `reminders --help`, `--help --verbose`, `--help=skill`

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 or later
- [Bun](https://bun.sh) for the build and install scripts

## Install

```bash
bun run install:local
```

This builds the committed sources and installs `~/.local/bin/reminders`, keeping the previous binary as `reminders.prev`. Point every tool at the installed copy, not at `.build/`, so that rebuilding the repo never changes what they run.

## Configure

Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`; use the absolute path):

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/Users/<you>/.local/bin/reminders",
      "args": ["mcp"]
    }
  }
}
```

Claude Code (`.mcp.json` in a project, which expands `${HOME}`):

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "${HOME}/.local/bin/reminders",
      "args": ["mcp"]
    }
  }
}
```

## Permissions

- **Reminders**: macOS asks the first time the tool reads or writes reminders. Click Allow.
- **Full Disk Access** for the app that runs the tool (Terminal, Claude Desktop, …): needed only for the hashtag, subtask and section fields. Without it those fields are `null` and one warning goes to stderr.

## Documentation

- [`SKILL.md`](SKILL.md) — CLI reference and common patterns
- [`docs/query-reference.md`](docs/query-reference.md) — query flags, JMESPath, recipes
- [`docs/sqlite-schema-notes.md`](docs/sqlite-schema-notes.md) — the Reminders database layout behind enrichment
- [`TESTING.md`](TESTING.md) — running the tests

## License

MIT
