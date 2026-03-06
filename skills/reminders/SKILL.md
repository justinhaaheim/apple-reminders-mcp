---
name: reminders
description: >
  Manage Apple Reminders on macOS — query, create, update, delete reminders
  and lists. Use when the user asks about their reminders, wants to create
  tasks, check what's due, mark things complete, or manage their task lists.
  Also use for backup/export of reminder data.
allowed-tools: Bash(reminders *), Bash(${CLAUDE_PLUGIN_ROOT}/.build/release/reminders *)
---

# Apple Reminders CLI

Use the `reminders` CLI to interact with Apple Reminders on this macOS machine.
All commands output JSON to stdout. Errors go to stderr.

## When to Use This Skill

- User asks to create, update, complete, or delete reminders
- User wants to check what's due, search for reminders, or review tasks
- User wants to see their reminder lists or create new ones
- User asks about upcoming deadlines or overdue items
- User wants to export or back up their reminders
- User mentions Apple Reminders, task management, or to-do lists

## Commands

### Query reminders (default command)

```bash
reminders query                                          # Incomplete from default list
reminders query --list "Work" --search "standup"         # Search within a list
reminders query --all-lists --status all --detail full   # Everything, all detail
reminders query --sort dueDate --limit 10                # Upcoming due dates
reminders query --status completed --from "2026-03-01"   # Recently completed
reminders query --jmespath "[?priority=='high'].title"   # JMESPath filtering
```

### List all reminder lists

```bash
reminders lists
```

### Create a reminder

```bash
reminders create "Buy groceries"
reminders create "Standup" --list "Work" --due "2026-03-07T09:00:00-08:00" --priority high
reminders create "Weekly review" --due "2026-03-07T10:00:00" --recurrence weekly
reminders create "Meeting" --due "2026-03-07T14:00:00-08:00" --alarm-relative 900
```

### Create a list

```bash
reminders create-list "Project Alpha"
```

### Update a reminder

```bash
reminders update <id> --complete                         # Mark done
reminders update <id> --incomplete                       # Unmark
reminders update <id> --title "New title" --priority medium
reminders update <id> --due "2026-03-10T14:00:00-08:00"
reminders update <id> --clear-due-date                   # Remove due date
reminders update <id> --list "Personal"                  # Move to different list
reminders update <id> --notes "Add some notes"
reminders update <id> --clear-notes                      # Remove notes
```

### Delete reminders

```bash
reminders delete <id>
reminders delete <id1> <id2> <id3>                       # Batch delete
```

### Export

```bash
reminders export                                         # To temp file
reminders export --path ~/backup.json --include-completed
```

### Snapshot (git-backed backup)

```bash
reminders snapshot                                       # Take a snapshot
reminders snapshot status                                # Show repo info
reminders snapshot diff                                  # Changes since last snapshot
```

## Key Details

**List selection**: `--list "Name"`, `--list-id "x-apple-..."`, `--all-lists`, or omit for default list.

**Status**: `--status incomplete` (default), `--status completed`, `--status all`.

**Detail levels**: `--detail minimal` (id, title), `--detail compact` (default, adds dates/priority), `--detail full` (everything).

**Priority**: `none`, `low`, `medium`, `high`.

**Dates**: ISO 8601 with timezone, e.g. `2026-03-07T09:00:00-08:00`. Date-only works for `--from`/`--to`.

**Global flags**: `--pretty` (pretty JSON), `--mock` (test with fake data).

## Tips

- Always use `--pretty` when showing results to the user
- Use `--detail compact` or `--detail minimal` to reduce noise in large result sets
- When searching, prefer `--search` over `--jmespath` for simple text searches
- Pipe to `jq` for advanced formatting: `reminders query --list "Work" | jq '.[].title'`
- To find a reminder's ID for update/delete, query first then extract the `id` field
