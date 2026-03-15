import Foundation

// MARK: - Help Content Registry

/// Static help content for each CLI command at each tier.
/// Concise help is ~10-20 lines. Verbose is cumulative (includes concise + detailed docs + examples).
/// Skill is strategic guidance on a separate axis.
public enum HelpContent {

    // MARK: - Top-level

    public static let topLevelConcise = """
    reminders — Apple Reminders CLI

    Commands:
      query         Search and filter reminders (default command)
      lists         Get all reminder lists
      create        Create a new reminder
      create-list   Create a new reminder list
      update        Update an existing reminder
      delete        Delete one or more reminders
      export        Export reminders to a JSON file
      snapshot      Git-backed snapshot of all reminders
      audit         View audit log of mutation operations
      mcp           Start MCP server on stdio

    Global Options:
      --pretty       Pretty-print JSON output
      --mock         Use in-memory mock store (no real reminders)
      --test-mode    Restrict writes to [AR-MCP TEST] prefixed lists
      --verbose      Show debug logging on stderr
      --version      Show version
      --help         Show help

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    Use `reminders schema <command>` to inspect input/output schemas.
    """

    public static let topLevelVerbose = """
    reminders — Apple Reminders CLI

    Commands:
      query         Search and filter reminders (default command)
      lists         Get all reminder lists
      create        Create a new reminder
      create-list   Create a new reminder list
      update        Update an existing reminder
      delete        Delete one or more reminders
      export        Export reminders to a JSON file
      snapshot      Git-backed snapshot of all reminders
      audit         View audit log of mutation operations
      mcp           Start MCP server on stdio

    Global Options:
      --pretty       Pretty-print JSON output
      --mock         Use in-memory mock store (no real reminders)
      --test-mode    Restrict writes to [AR-MCP TEST] prefixed lists
      --verbose      Show debug logging on stderr
      --version      Show version
      --help         Show help

    All commands output JSON to stdout. Logs and errors go to stderr.
    Exit code 0 on success, 1 on failure.

    List Selection (most commands):
      --list "Name"     Select by list name (case-insensitive)
      --list-id "..."   Select by list ID
      --all-lists       Query across all lists
      (omitted)         Uses the default list

    Priority Values: none, low, medium, high

    Date Format: ISO 8601 with timezone, e.g. 2026-03-07T09:00:00-08:00
      Date-only also works for --from/--to: 2026-03-07

    Output Detail Levels (query command):
      --detail minimal   id, title, listName, isCompleted
      --detail compact   (default) Adds notes, dueDate, priority, dates
      --detail full      All fields including alarms, recurrence, null values

    Environment Variables:
      AR_MCP_TEST_MODE=1            Enable test mode
      AR_MCP_MOCK_MODE=1            Use mock store
      AR_MCP_SNAPSHOT_ENABLED=1     Enable auto-snapshots in MCP server
      AR_MCP_SNAPSHOT_REPO=<path>   Snapshot repository path
      AR_SNAPSHOT_REPO=<path>       Snapshot repository path (CLI)

    Examples:
      reminders                                             # Incomplete reminders from default list
      reminders query --all-lists --status all --detail full # Everything, full detail
      reminders query --list "Work" --search "standup"       # Search within a list
      reminders query --sort dueDate --limit 10              # Upcoming due dates
      reminders create "Buy milk" --list "Shopping"          # Create a reminder
      reminders update <id> --complete                       # Mark done
      reminders delete <id1> <id2>                           # Batch delete

    Use --help=skill for best practices and strategic guidance.
    Use `reminders schema <command>` to inspect input/output schemas.
    """

    public static let topLevelSkill = """
    reminders — Strategic Guidance

    GENERAL PRINCIPLES:
    • Always query before updating or deleting. Get the reminder ID first.
    • Use --detail minimal to save tokens when you only need IDs and titles.
    • Use --all-lists unless the user specifies a particular list.
    • Use --pretty when showing output to the user, omit it when processing programmatically.

    EFFICIENT QUERYING:
    • Default query (no args) returns incomplete reminders from the default list — often sufficient.
    • Use --search for text matching before resorting to JMESPath.
    • Use --detail compact (default) for most work. Only use --detail full when you need alarms, recurrence, or URLs.
    • JMESPath queries operate on full fields regardless of --detail, so use them for complex filtering.
    • Use --from and --to for date ranges instead of fetching all and filtering client-side.

    SAFE MUTATIONS:
    • Always verify the list exists (via `reminders lists`) before creating reminders in a specific list.
    • When updating, only pass the fields you want to change. Omitted fields are preserved.
    • Use --clear-notes, --clear-due-date, --clear-url to explicitly remove values (not empty strings).
    • Batch operations (create, update, delete) report partial failures — always check the response.

    COMMON WORKFLOWS:
    • Daily review: `reminders query --all-lists --sort dueDate --from "$(date -I)" --pretty`
    • Bulk complete: Query IDs first, then update each with --complete
    • Move reminder: `reminders update <id> --list "New List"`

    GOTCHAS:
    • The --list flag is case-insensitive but must match the full list name.
    • Date-only format (2026-03-07) works for --from/--to but not for --due (which needs full ISO 8601 with time).
    • Completed reminders have a completionDate; date range filtering uses completionDate for completed, dueDate for incomplete.
    • JMESPath overrides --sort and --detail — it always operates on full data.

    Use `reminders <command> --help` for API documentation.
    Use `reminders <command> --help --verbose` for comprehensive docs with examples.
    """

    // MARK: - Query

    public static let queryConcise = """
    reminders query [options]

    Search and filter reminders. This is the default command.

    Options:
      --list <string>       Filter by list name (case-insensitive)
      --list-id <string>    Filter by list ID
      --all-lists           Search across all lists
      --status <string>     incomplete (default), completed, or all
      --search <string>     Text search in titles and notes
      --sort <string>       newest (default), oldest, priority, dueDate
      --limit <int>         Max results (returns all if omitted)
      --offset <int>        Skip N results (for pagination)
      --from <date>         Date range start (ISO 8601 or YYYY-MM-DD)
      --to <date>           Date range end (ISO 8601 or YYYY-MM-DD)
      --jmespath <expr>     JMESPath query expression
      --detail <level>      minimal, compact (default), full

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let queryVerbose = """
    reminders query [options]

    Search and filter reminders. This is the default command — running `reminders`
    with no subcommand is equivalent to `reminders query`.

    Options:
      --list <string>       Filter by list name (case-insensitive)
      --list-id <string>    Filter by list ID
      --all-lists           Search across all lists
      --status <string>     incomplete (default), completed, or all
      --search <string>     Text search in titles and notes
      --sort <string>       newest (default), oldest, priority, dueDate
      --limit <int>         Max results (returns all if omitted)
      --offset <int>        Skip N results (for pagination)
      --from <date>         Date range start (ISO 8601 or YYYY-MM-DD)
      --to <date>           Date range end (ISO 8601 or YYYY-MM-DD)
      --jmespath <expr>     JMESPath query expression
      --detail <level>      minimal, compact (default), full

    Default Behavior (no options):
      Returns incomplete reminders from the default list, sorted by newest
      created first, using compact output detail.

    Detail Levels:
      minimal   id, title only (plus listName if --all-lists, isCompleted if --status all)
      compact   id, title, notes, dueDate, priority, createdDate, lastModifiedDate
                (plus listName/isCompleted when contextually useful). Null fields omitted.
      full      All fields always included: id, title, notes, dueDate, priority,
                isCompleted, completionDate, createdDate, lastModifiedDate, listId,
                listName, url, alarms, recurrenceRule. Null values shown explicitly.

    Date Range Filtering:
      --from and --to filter by dueDate for incomplete reminders and by
      completionDate for completed reminders. Date-only format (YYYY-MM-DD) is accepted.

    JMESPath Queries:
      --jmespath provides server-side filtering using JMESPath expressions.
      When used, it overrides --sort and --detail — the query operates on full
      fields as input. See https://jmespath.org for syntax.

    Examples:
      reminders query                                          # Incomplete from default list
      reminders query --all-lists --status all --detail full   # Everything
      reminders query --list "Work" --search "standup"         # Search within a list
      reminders query --sort dueDate --limit 10                # Upcoming due dates
      reminders query --sort dueDate --limit 10 --offset 10    # Next page
      reminders query --status completed --from "2026-03-01"   # Recently completed
      reminders query --all-lists --jmespath "[?priority=='high'].title"

    Piping with jq:
      reminders query --list "Work" | jq -r '.[].id'
      reminders query --all-lists --sort dueDate | jq -r '.[] | [.title, .dueDate // "none"] | @tsv'

    Use --help=skill for best practices and strategic guidance.
    """

    public static let querySkill = """
    reminders query — Strategic Guidance

    • Use --detail minimal when you only need IDs/titles (saves tokens).
    • Use --search before JMESPath — it's simpler and sufficient for most text matching.
    • Use --from/--to for date ranges instead of fetching all and filtering client-side.
    • JMESPath overrides --sort and --detail. It always operates on full field data.
    • Default query (no args) is often sufficient — it returns incomplete reminders
      from the default list. Don't add flags unless you need to narrow or expand.
    • For completed reminders, date filtering uses completionDate, not dueDate.
    • All results are returned by default. Use --limit and --offset for pagination.
    """

    // MARK: - Create

    public static let createConcise = """
    reminders create <title> [options]

    Create a new reminder.

    Arguments:
      <title>                     Reminder title (required)

    Options:
      --list <string>             Target list name (default: default list)
      --list-id <string>          Target list ID
      --notes <string>            Body text
      --due <iso-8601>            Due date (e.g. 2026-03-07T09:00:00-08:00)
      --priority <string>         none (default), low, medium, high
      --url <string>              URL to attach
      --alarm-relative <seconds>  Alarm offset before due date (e.g. 900 = 15 min)
      --alarm-date <iso-8601>     Absolute alarm date
      --recurrence <freq>         daily, weekly, monthly, yearly
      --recurrence-interval <int> Interval for recurrence (default: 1)

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let createVerbose = """
    reminders create <title> [options]

    Create a new reminder. Returns the created reminder as JSON.

    Arguments:
      <title>                     Reminder title (required)

    Options:
      --list <string>             Target list name (case-insensitive, default: default list)
      --list-id <string>          Target list ID
      --notes <string>            Body text
      --due <iso-8601>            Due date (full ISO 8601 with time and timezone)
      --priority <string>         none (default), low, medium, high
      --url <string>              URL to attach
      --alarm-relative <seconds>  Alarm offset in seconds before due date (e.g. 900 = 15 min)
      --alarm-date <iso-8601>     Absolute alarm date/time
      --recurrence <freq>         daily, weekly, monthly, yearly
      --recurrence-interval <int> Interval for recurrence (default: 1)

    Notes:
      - Only one alarm can be set per reminder via CLI (relative OR absolute, not both).
        For multiple alarms, use the MCP server's batch create.
      - Recurrence requires a due date to be set.
      - The --due flag requires full ISO 8601 with time (not date-only).

    Examples:
      reminders create "Buy groceries"
      reminders create "Buy groceries" --list "Shopping" --priority medium
      reminders create "Team standup" --list "Work" \\
        --due "2026-03-07T09:00:00-08:00" --priority high
      reminders create "Take medication" \\
        --due "2026-03-07T08:00:00-08:00" --alarm-relative 0 --recurrence daily
      reminders create "Weekly review" \\
        --due "2026-03-10T10:00:00-08:00" --recurrence weekly

    Use --help=skill for best practices and strategic guidance.
    """

    public static let createSkill = """
    reminders create — Strategic Guidance

    • Always verify the target list exists first with `reminders lists`.
    • The --due flag needs full ISO 8601 with time and timezone, not date-only.
    • For reminders due today, construct the date string programmatically:
      --due "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
    • Set --alarm-relative 0 to alarm exactly at the due time.
    • Common alarm offsets: 300 (5 min), 900 (15 min), 3600 (1 hour), 86400 (1 day).
    • For batch creation, use the MCP server's create_reminders tool instead.
    """

    // MARK: - Update

    public static let updateConcise = """
    reminders update <id> [options]

    Update an existing reminder.

    Arguments:
      <id>                  Reminder ID (required)

    Options:
      --title <string>      New title
      --notes <string>      New notes
      --clear-notes         Remove notes
      --list <string>       Move to list by name
      --list-id <string>    Move to list by ID
      --due <iso-8601>      New due date
      --clear-due-date      Remove due date
      --priority <string>   none, low, medium, high
      --complete            Mark as complete
      --incomplete          Mark as incomplete
      --url <string>        New URL
      --clear-url           Remove URL

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let updateVerbose = """
    reminders update <id> [options]

    Update an existing reminder. Only the fields you specify are changed;
    omitted fields are preserved. Returns the updated reminder as JSON.

    Arguments:
      <id>                  Reminder ID (required — get via `reminders query`)

    Options:
      --title <string>      New title
      --notes <string>      New notes
      --clear-notes         Remove notes (set to null)
      --list <string>       Move to list by name (case-insensitive)
      --list-id <string>    Move to list by ID
      --due <iso-8601>      New due date (full ISO 8601 with time and timezone)
      --clear-due-date      Remove due date (set to null)
      --priority <string>   none, low, medium, high
      --complete            Mark as complete
      --incomplete          Mark as incomplete (uncomplete)
      --url <string>        New URL
      --clear-url           Remove URL (set to null)

    Clearable Fields:
      Some fields can be explicitly removed using --clear-* flags. Setting
      --notes "" is different from --clear-notes: the former sets notes to an
      empty string, the latter removes them entirely (sets to null).

    Examples:
      reminders update ABC123 --complete                         # Mark done
      reminders update ABC123 --incomplete                       # Unmark
      reminders update ABC123 --title "Updated title"            # Change title
      reminders update ABC123 --priority high --due "2026-03-10T14:00:00-08:00"
      reminders update ABC123 --list "Personal"                  # Move to list
      reminders update ABC123 --clear-due-date --clear-notes     # Remove fields

    Use --help=skill for best practices and strategic guidance.
    """

    public static let updateSkill = """
    reminders update — Strategic Guidance

    • Always query first to get the reminder ID. Abbreviated ID prefixes are accepted
      (e.g., '550e840' instead of the full UUID). If ambiguous, you'll be told to use more characters.
    • Only pass the fields you want to change. Omitted fields are preserved as-is.
    • Use --clear-notes / --clear-due-date / --clear-url to explicitly remove values.
      Don't pass empty strings — use the clear flags.
    • --complete and --incomplete are mutually exclusive.
    • Moving a reminder to a different list (--list) preserves all other fields.
    • For batch updates, use the MCP server's update_reminders tool instead.
    """

    // MARK: - Delete

    public static let deleteConcise = """
    reminders delete <id> [<id> ...]

    Delete one or more reminders.

    Arguments:
      <id>    Reminder ID(s) to delete (at least one required)

    Returns JSON with deleted IDs and any failures. Exit code 1 if any deletion failed.

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let deleteVerbose = """
    reminders delete <id> [<id> ...]

    Delete one or more reminders by ID. Supports batch deletion.

    Arguments:
      <id>    Reminder ID(s) to delete (at least one required, space-separated)

    Output:
      Returns JSON with:
        deleted      — Array of successfully deleted IDs
        deletedCount — Number of deletions
        failed       — Array of {id, error} for failures (if any)
        failedCount  — Number of failures (if any)

      Exit code 0 if all deletions succeed, 1 if any fail.

    Examples:
      reminders delete ABC123
      reminders delete ABC123 DEF456 GHI789

    Batch Pattern:
      # Delete all completed reminders from a list
      reminders query --list "Work" --status completed --detail minimal | \\
        jq -r '.[].id' | xargs reminders delete

    Use --help=skill for best practices and strategic guidance.
    """

    public static let deleteSkill = """
    reminders delete — Strategic Guidance

    • Always query first to verify the IDs. Deletion is permanent and cannot be undone.
    • Prefer deleting one at a time unless you're confident about the IDs.
    • Batch delete reports partial failures — check the response for the "failed" array.
    • Consider marking reminders as complete (update --complete) instead of deleting.
    """

    // MARK: - Lists

    public static let listsConcise = """
    reminders lists

    Get all reminder lists. Returns JSON array of {id, title, count} objects.

    No additional options (only global options apply).

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let listsVerbose = """
    reminders lists

    Get all reminder lists. Returns a JSON array where each list has:
      id    — The list's unique identifier
      title — The display name
      count — Number of incomplete reminders in the list

    Examples:
      reminders lists
      reminders lists --pretty
      reminders lists | jq -r '.[].title'                  # Just list names
      reminders lists | jq '.[] | select(.count > 0)'     # Non-empty lists

    Use --help=skill for best practices and strategic guidance.
    """

    public static let listsSkill = """
    reminders lists — Strategic Guidance

    • Call this before creating reminders in a specific list to verify the list exists.
    • List names are case-insensitive when used with --list in other commands.
    • The count field shows incomplete reminders only.
    """

    // MARK: - Create List

    public static let createListConcise = """
    reminders create-list <name>

    Create a new reminder list.

    Arguments:
      <name>    Name for the new list (required)

    Returns the created list as JSON with id, title, and count.

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let createListVerbose = """
    reminders create-list <name>

    Create a new reminder list. Returns the created list as JSON.

    Arguments:
      <name>    Name for the new list (required)

    Output:
      Returns {id, title, count} where count will be 0 for a new list.

    Examples:
      reminders create-list "Project Alpha"
      reminders create-list "Shopping" --pretty

    Use --help=skill for best practices and strategic guidance.
    """

    public static let createListSkill = """
    reminders create-list — Strategic Guidance

    • Check `reminders lists` first to avoid creating duplicate list names.
    • Apple Reminders allows duplicate list names, but it causes confusion.
    • List names cannot be empty strings.
    """

    // MARK: - Export

    public static let exportConcise = """
    reminders export [options]

    Export reminders to a JSON file for backup.

    Options:
      --path <string>           Output file path (default: temp directory)
      --list <string>           Export specific list(s) (repeatable)
      --include-completed       Include completed reminders

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let exportVerbose = """
    reminders export [options]

    Export reminders to a JSON file for backup. By default exports incomplete
    reminders from all lists to a temporary file.

    Options:
      --path <string>           Output file path (default: auto-generated in temp dir)
      --list <string>           Export specific list(s) by name. Can be repeated:
                                --list "Work" --list "Personal"
      --include-completed       Include completed reminders (default: incomplete only)

    Output:
      Returns JSON with:
        path            — Path to the exported file
        reminderCount   — Number of reminders exported
        listCount       — Number of lists included

    Examples:
      reminders export                                            # All lists, incomplete only
      reminders export --path ~/backup.json --include-completed   # Full backup
      reminders export --list "Work" --pretty                     # Work list only

    Use --help=skill for best practices and strategic guidance.
    """

    public static let exportSkill = """
    reminders export — Strategic Guidance

    • For regular backups, prefer `reminders snapshot` which uses git versioning.
    • Export is useful for one-time backups or sharing data.
    • Use --include-completed for a complete backup.
    • The default temp directory path changes each run — specify --path for predictable output.
    """

    // MARK: - Snapshot

    public static let snapshotConcise = """
    reminders snapshot [subcommand]

    Git-backed snapshot of all reminders data.

    Subcommands:
      take     Take a snapshot (default)
      status   Show snapshot repository info
      diff     Show changes since last snapshot

    Options:
      --repo <path>    Snapshot repository path (default: ~/.config/apple-reminders-data)

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let snapshotVerbose = """
    reminders snapshot [subcommand]

    Git-backed snapshot of all reminders data. Each snapshot is a git commit,
    giving you full version history of your reminders.

    Subcommands:
      take     Take a snapshot (default if no subcommand given)
      status   Show snapshot repository info (path, commit count, last snapshot time)
      diff     Show changes since last snapshot (git diff output)

    Options (all subcommands):
      --repo <path>    Snapshot repository path
                       Default: ~/.config/apple-reminders-data
                       Can also be set via AR_SNAPSHOT_REPO environment variable

    Output (take):
      Returns {reminderCount, listCount, commitHash, timestamp}

    Output (status):
      Returns {repoPath, commitCount, lastSnapshotDate, ...}

    Examples:
      reminders snapshot                    # Take a snapshot
      reminders snapshot take --pretty      # Take with pretty output
      reminders snapshot status --pretty    # Show repo info
      reminders snapshot diff              # Changes since last snapshot

    Use --help=skill for best practices and strategic guidance.
    """

    public static let snapshotSkill = """
    reminders snapshot — Strategic Guidance

    • Take snapshots before and after bulk operations as a safety net.
    • Use `snapshot diff` to verify what changed before committing to more changes.
    • Snapshots are lightweight git commits — take them frequently.
    • For MCP server auto-snapshots, set AR_MCP_SNAPSHOT_ENABLED=1.
    """

    // MARK: - MCP

    public static let mcpConcise = """
    reminders mcp

    Start the MCP (Model Context Protocol) server on stdio.
    Communicates via JSON-RPC 2.0. For use with Claude Desktop and other MCP clients.

    No additional options (only global options apply).

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let mcpVerbose = """
    reminders mcp

    Start the MCP (Model Context Protocol) server on stdio.
    Communicates via JSON-RPC 2.0 over stdin/stdout.

    This exposes the same tools as the CLI (query, create, update, delete, etc.)
    via the MCP protocol, for use with Claude Desktop and other MCP clients.

    Configuration (Claude Desktop):
      Add to ~/Library/Application Support/Claude/claude_desktop_config.json:
      {
        "mcpServers": {
          "apple-reminders": {
            "command": "/path/to/reminders",
            "args": ["mcp"]
          }
        }
      }

    Environment Variables:
      AR_MCP_SNAPSHOT_ENABLED=1     Enable auto-snapshots after write operations
      AR_MCP_SNAPSHOT_REPO=<path>   Snapshot repository path
      AR_MCP_TEST_MODE=1            Enable test mode
      AR_MCP_MOCK_MODE=1            Use mock store

    Use --help=skill for best practices and strategic guidance.
    """

    public static let mcpSkill = """
    reminders mcp — Strategic Guidance

    • The MCP server exposes help, schema, and guidance meta-tools.
      Call help("tool_name") for documentation on any tool.
    • Auto-snapshots (AR_MCP_SNAPSHOT_ENABLED=1) provide a safety net for all mutations.
    • Use test mode (AR_MCP_TEST_MODE=1) during development to prevent modifying real data.
    """

    // MARK: - Audit

    public static let auditConcise = """
    reminders audit [options]

    View audit log of mutation operations (create, update, delete).

    Options:
      --days <int>       Number of days to show (default: 7)
      --files            Show log file paths and sizes

    Use --help --verbose for detailed docs and examples.
    Use --help=skill for best practices and strategic guidance.
    """

    public static let auditVerbose = """
    reminders audit [options]

    View the audit log of all mutation operations. Every create, update, and
    delete operation is logged with timestamp, action, arguments, result,
    and before-state (for updates and deletes).

    Options:
      --days <int>       Number of days to look back (default: 7)
      --files            Show log file paths and sizes instead of entries

    Log Format:
      Logs are stored as JSONL (one JSON object per line) in:
        ~/.config/apple-reminders-tools/logs/YYYY-MM-DD.jsonl

    Each entry contains:
      timestamp    — ISO 8601 timestamp
      action       — The operation (create_reminder, update_reminder, etc.)
      args         — Full arguments passed to the operation
      result       — "success" or "failure"
      response     — The operation's response (for creates and updates)
      beforeState  — The resource state before mutation (for updates and deletes)
      context      — Session ID and source (cli or mcp)

    Examples:
      reminders audit --pretty                    # Recent mutations
      reminders audit --days 1 --pretty           # Today's mutations
      reminders audit --files --pretty            # List log files

    Piping with jq:
      reminders audit | jq '.[] | select(.action == "delete_reminder")'
      reminders audit | jq '.[] | select(.context.source == "mcp")'

    Use --help=skill for best practices and strategic guidance.
    """

    public static let auditSkill = """
    reminders audit — Strategic Guidance

    • Check the audit log after agent sessions to verify what was changed.
    • Use beforeState to understand what a reminder looked like before modification.
    • Filter by context.source to separate CLI vs MCP mutations.
    • Log files are kept indefinitely during alpha/beta. Plan to add retention later.
    • Both CLI and MCP surfaces write to the same audit log.
    """

    // MARK: - Lookup

    /// All command names that have custom help content.
    public static let supportedCommands: Set<String> = [
        "query", "create", "update", "delete", "lists",
        "create-list", "export", "snapshot", "audit", "mcp",
    ]

    /// Get concise help for a command (or top-level if nil).
    public static func concise(for command: String?) -> String? {
        guard let command = command else { return topLevelConcise }
        switch command {
        case "query": return queryConcise
        case "create": return createConcise
        case "update": return updateConcise
        case "delete": return deleteConcise
        case "lists": return listsConcise
        case "create-list": return createListConcise
        case "export": return exportConcise
        case "snapshot": return snapshotConcise
        case "audit": return auditConcise
        case "mcp": return mcpConcise
        default: return nil
        }
    }

    /// Get verbose help for a command (or top-level if nil). Cumulative — includes concise content.
    public static func verbose(for command: String?) -> String? {
        guard let command = command else { return topLevelVerbose }
        switch command {
        case "query": return queryVerbose
        case "create": return createVerbose
        case "update": return updateVerbose
        case "delete": return deleteVerbose
        case "lists": return listsVerbose
        case "create-list": return createListVerbose
        case "export": return exportVerbose
        case "snapshot": return snapshotVerbose
        case "audit": return auditVerbose
        case "mcp": return mcpVerbose
        default: return nil
        }
    }

    /// Get skill guidance for a command (or top-level if nil).
    public static func skill(for command: String?) -> String? {
        guard let command = command else { return topLevelSkill }
        switch command {
        case "query": return querySkill
        case "create": return createSkill
        case "update": return updateSkill
        case "delete": return deleteSkill
        case "lists": return listsSkill
        case "create-list": return createListSkill
        case "export": return exportSkill
        case "snapshot": return snapshotSkill
        case "audit": return auditSkill
        case "mcp": return mcpSkill
        default: return nil
        }
    }
}
