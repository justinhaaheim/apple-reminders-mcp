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

### User preferences

- Always use `--pretty` when showing output to the user.
- Default to `--all-lists` unless the user specifies a particular list.
- Use `--detail compact` (default) for queries unless more detail is needed.
- When searching, prefer `--search` over `--jmespath` for simple text matches.
- To find a reminder's ID for update/delete, query first then extract the `id` field.
- Pipe to `jq` for advanced formatting: `reminders query --list "Work" | jq '.reminders[].title'`
