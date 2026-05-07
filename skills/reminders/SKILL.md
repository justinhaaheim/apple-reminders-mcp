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

For the JMESPath fundamentals + recipe book (the foundation reference), see the project's
[`docs/query-reference.md`](../../docs/query-reference.md). Top-level CLI cheatsheet is in
[`SKILL.md`](../../SKILL.md).

### Query convention (governing rule)

CLI flags filter at fetch time. The optional positional JMESPath argument runs after.
Order on the command line doesn't matter — flags always run first.

### User preferences

- Always use `--pretty` when showing output to the user.
- Default to `--all-lists` unless the user specifies a particular list.
- Use `--detail compact` (default) for queries unless more detail is needed.
- For text matching, prefer `--search` (case-insensitive substring) over JMESPath.
- For date filtering, use the per-field date flags (`--created-from/-to`,
  `--modified-from/-to`, `--due-from/-to`) rather than expressing dates inside JMESPath.
- For case-insensitive comparisons inside JMESPath, use the project's
  `lower()` / `upper()` extensions: `[?contains(lower(title), 'meeting')]`.
- The JMESPath query is a positional argument: `reminders query "[?priority == 'high']"`.
- To find a reminder's ID for update/delete, query first then extract the `id` field.
- Pipe to `jq` for advanced formatting: `reminders query --list "Work" | jq '.reminders[].title'`
