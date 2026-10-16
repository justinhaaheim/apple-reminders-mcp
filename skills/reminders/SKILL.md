---
name: reminders
description: >
  Manage Apple Reminders on macOS — query, create, update, delete reminders
  and lists. Use when the user asks about their reminders, wants to create
  tasks, check what's due, mark things complete, or manage their task lists.
  Also use for backup/export of reminder data.
allowed-tools: Bash(reminders *), Bash(${CLAUDE_PLUGIN_ROOT}/.build/release/reminders *)
---

## Using reminders

`reminders` is a CLI for managing Apple Reminders on macOS. Before first use, run:

    reminders --help=skill

This returns the tool author's guidance on best practices and strategic usage patterns.

For API documentation, use `reminders --help` (concise) or `--help --verbose` (comprehensive).
For subcommand help, use `reminders <command> --help` or `--help --verbose`.

### Query convention

Structured CLI flags filter at fetch time. The JMESPath positional `[QUERY]`
argument filters and projects on the result. Order on the command line never
changes the result — flags always run first.

```bash
# Identical results:
reminders query --list "Work" "[?priority == 'high']" --pretty
reminders query "[?priority == 'high']" --list "Work" --pretty
```

Foundation reference: see `docs/query-reference.md` (recipes, JMESPath
fundamentals, project-specific extensions).

### User preferences

- Always use `--pretty` when showing output to the user.
- Default scope is the user's default list and incomplete reminders only.
  Don't widen with `--all-lists`, `--include-completed`, or `--completed-only`
  unless the user explicitly asks for that broader scope. Treat ambiguous
  phrases like "my reminders matching X" or "json dump of X" as "the open
  ones matching X", not "everything ever matching X".
- Use `--detail compact` (default) for queries unless more detail is needed.
- When searching, prefer `--search` over JMESPath for simple text matches.
  For case-insensitive JMESPath matching, use `lower()` / `upper()`:
  `reminders query "[?contains(lower(title), 'meeting')]"`.
- For date ranges, use the per-field flags: `--created-from` / `--created-to`,
  `--modified-from` / `--modified-to`, `--due-from` / `--due-to`.
- To find a reminder's ID for update/delete, query first then extract the `id` field.
- Pipe to `jq` for advanced formatting: `reminders query --list "Work" | jq '.reminders[].title'`
