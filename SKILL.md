# Apple Reminders CLI — Skill Reference

This file is a standalone reference for the `reminders` CLI. For the Claude Code
plugin skill (with frontmatter), see [`skills/reminders/SKILL.md`](skills/reminders/SKILL.md).

---

> **For**: Claude Code, Claude Desktop, and LLMs with shell access on macOS
> **Binary**: `reminders` (built from this repo)
> **Output**: All commands output JSON to stdout. Logs go to stderr.

## Quick Reference

```bash
# Query (default command — just running `reminders` is the same as `reminders query`)
reminders query                                          # Incomplete reminders from default list
reminders query --list "Work" --search "standup"         # Search within a list
reminders query --all-lists --status all --detail full   # Everything, full detail
reminders query --sort dueDate --limit 10                # Upcoming due dates

# Lists
reminders lists                                          # All reminder lists

# Create
reminders create "Buy groceries"                         # In default list
reminders create "Team standup" --list "Work" --due "2026-03-07T09:00:00-08:00" --priority high
reminders create "Weekly review" --due "2026-03-07T10:00:00" --recurrence weekly

# Update
reminders update <id> --complete                         # Mark done
reminders update <id> --incomplete                       # Unmark
reminders update <id> --title "New title" --priority medium
reminders update <id> --due "2026-03-10T14:00:00-08:00"
reminders update <id> --clear-due-date                   # Remove due date
reminders update <id> --list "Personal"                  # Move to different list

# Delete
reminders delete <id>
reminders delete <id1> <id2> <id3>                       # Batch delete

# Create list
reminders create-list "Project Alpha"

# Export
reminders export                                         # To temp file
reminders export --path ~/backup.json --include-completed

# Snapshot (git-backed backup)
reminders snapshot                                       # Take a snapshot
reminders snapshot status                                # Show repo info
reminders snapshot diff                                  # Changes since last snapshot

# MCP server
reminders mcp                                            # Start JSON-RPC server on stdio
```

## Key Concepts

### List Selection

Most commands accept list selectors:

- `--list "Name"` — Select by list name (case-insensitive)
- `--list-id "x-apple-..."` — Select by list ID
- `--all-lists` — Query across all lists
- _(omitted)_ — Uses the default list

### Status Filtering

The `query` command filters by status:

- `--status incomplete` — (default) Only incomplete reminders
- `--status completed` — Only completed reminders
- `--status all` — Both

### Output Detail Levels

Control how much data is returned:

- `--detail minimal` — id, title, listName, isCompleted
- `--detail compact` — (default) Adds notes, dueDate, priority, dates
- `--detail full` — All fields including alarms, recurrence, URLs, null values shown

### Priority Values

`none`, `low`, `medium`, `high`

### Date Format

All dates use ISO 8601 with timezone: `2026-03-07T09:00:00-08:00`

Date-only format also works for `--from`/`--to`: `2026-03-07`

### Clearable Fields

On update, some fields can be cleared (set to null) with `--clear-*` flags:

- `--clear-notes`
- `--clear-due-date`
- `--clear-url`

### JMESPath Queries

Advanced filtering with `--jmespath`:

```bash
# Get just titles of high-priority reminders
reminders query --all-lists --detail full --jmespath "[?priority=='high'].title"

# Count by list
reminders query --all-lists --jmespath "length([?listName=='Work'])"
```

## Global Options

All commands support:

| Flag          | Description                                       |
| ------------- | ------------------------------------------------- |
| `--pretty`    | Pretty-print JSON output                          |
| `--mock`      | Use in-memory mock store (no real reminders)      |
| `--test-mode` | Restrict writes to `[AR-MCP TEST]` prefixed lists |
| `--verbose`   | Show debug logging on stderr                      |

## Common Patterns

### Daily Review

```bash
# What's due today or overdue?
reminders query --all-lists --status incomplete --from "$(date -I)" --sort dueDate --pretty

# What did I complete recently?
reminders query --all-lists --status completed --from "$(date -v-7d -I)" --sort newest --pretty
```

### Task Management

```bash
# Create a task with alarm (15 min before)
reminders create "Meeting with Alex" --list "Work" \
  --due "2026-03-07T14:00:00-08:00" --alarm-relative 900

# Batch complete
for id in id1 id2 id3; do reminders update "$id" --complete; done
```

### Piping with jq

```bash
# Get IDs of all incomplete Work reminders
reminders query --list "Work" --detail minimal | jq -r '.[].id'

# Pretty table of upcoming due dates
reminders query --all-lists --sort dueDate --detail compact | \
  jq -r '.[] | [.title, .dueDate // "no date", .priority] | @tsv'
```

### Backup Workflow

```bash
# Take a git-backed snapshot
reminders snapshot --pretty

# Export to a file
reminders export --path ~/reminders-backup.json --include-completed --pretty
```

## Error Handling

- Exit code 0 on success
- Exit code 1 on failure (with error message on stderr)
- Partial failures (batch operations) return both `created`/`updated`/`deleted` and `failed` arrays

## Environment Variables

| Variable                      | Description                                      |
| ----------------------------- | ------------------------------------------------ |
| `AR_MCP_TEST_MODE=1`          | Enable test mode (restrict writes to test lists) |
| `AR_MCP_MOCK_MODE=1`          | Use mock store                                   |
| `AR_MCP_SNAPSHOT_ENABLED=1`   | Enable auto-snapshots in MCP server              |
| `AR_MCP_SNAPSHOT_REPO=<path>` | Snapshot repository path                         |
| `AR_SNAPSHOT_REPO=<path>`     | Snapshot repository path (CLI)                   |
