# Dolt vs Git for Versioned Snapshotting — Investigation

**Date:** 2026-03-14
**Status:** Investigation complete

## Context

The current snapshot system uses **git** to version reminder data:

- Each reminder is a separate JSON file in `data/id/{reminder_id}.json`
- List metadata in `lists.json`
- `git add -A && git commit` on each snapshot
- Diff via `git diff --stat` / `git show --stat`
- Repository at `~/.config/apple-reminders-data`

The question: would **Dolt** (a version-controlled SQL database) be a better fit?

---

## What is Dolt?

Dolt is "Git for Data" — a MySQL-compatible SQL database with built-in version control (branch, merge, diff, commit, push, pull). Data is stored in Prolly Trees (a content-addressed Merkle DAG) with structural sharing across versions.

- Written in Go, ~103 MB binary
- Embedded mode available (Go only, via `dolthub/driver`)
- No Swift SDK or library exists
- MySQL wire protocol for client connections

---

## Comparison

### Benefits of Dolt over Git

| Benefit                           | Detail                                                                                                                       |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Structured queries on history** | `SELECT * FROM dolt_diff('main~1', 'main', 'reminders')` — query diffs as SQL tables, filter by column, join with other data |
| **Efficient diff**                | Prolly Tree diffs scale with diff size, not table size (O(diff) vs O(n) for git's file-level approach)                       |
| **Schema-aware diffs**            | Diffs are column-level ("priority changed from 'low' to 'high'"), not line-level text diffs                                  |
| **SQL query interface**           | `SELECT * FROM reminders AS OF 'main~5'` — time-travel queries with standard SQL                                             |
| **Branch/merge for data**         | Could maintain separate branches for different data views (e.g., "before bulk cleanup")                                      |
| **Conflict resolution**           | Built-in 3-way merge for data conflicts                                                                                      |
| **Storage efficiency**            | Content-addressed storage with structural sharing — unchanged rows are deduplicated across commits                           |
| **No file-per-record overhead**   | Single database vs thousands of tiny JSON files (filesystem overhead, inode usage)                                           |

### Drawbacks of Dolt vs Git

| Drawback                        | Detail                                                                                                                                                                                                      |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **~103 MB binary**              | Massive dependency for a reminder backup tool. Git is already installed on macOS. The current MCP binary is likely <10 MB.                                                                                  |
| **No Swift integration**        | Dolt is Go-only. Would need to either: (a) shell out to `dolt` CLI (same as current git approach), (b) run Dolt as a server and connect via MySQL protocol, or (c) use cgo/gomobile bridge. None are clean. |
| **External dependency**         | Users must install Dolt separately. Git ships with macOS (via Xcode CLT).                                                                                                                                   |
| **Overkill for the use case**   | The snapshot system stores ~hundreds to low-thousands of reminders. Git handles this trivially. Dolt's advantages (efficient diff at scale, SQL queries on history) don't materialize at this data size.    |
| **Complexity**                  | Running a MySQL-compatible server or managing a Dolt database adds operational complexity vs a simple git repo.                                                                                             |
| **Maturity for this niche**     | Dolt is mature for its target use case (collaborative data versioning), but using it as an embedded local backup store is an unusual fit.                                                                   |
| **No macOS system integration** | Git integrates with macOS Keychain, is available via `xcrun git`, etc. Dolt has no OS-level integration.                                                                                                    |
| **Server process**              | For SQL access, Dolt needs to run as a server (`dolt sql-server`). The CLI mode works but is slower for repeated queries.                                                                                   |

### Neutral / Context-Dependent

| Factor                 | Git (current)                                             | Dolt                                                       |
| ---------------------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| **Data format**        | Human-readable JSON files (easy to inspect with any tool) | Binary database (requires Dolt or MySQL client to inspect) |
| **Backup portability** | Clone the git repo anywhere                               | Need Dolt installed to read                                |
| **Hosting/sharing**    | GitHub, any git remote                                    | DoltHub, or self-hosted DoltLab                            |
| **Learning curve**     | Users already know git                                    | New tool to learn                                          |
| **Ecosystem**          | Ubiquitous                                                | Niche but growing                                          |

---

## Analysis for This Project

### The current git approach is well-suited because:

1. **Scale is small** — Hundreds of reminders, not millions of rows. Git handles this without breaking a sweat.
2. **File-per-reminder is actually good** — It produces meaningful, readable diffs. You can `git log -p data/id/ABC123.json` to see the full history of one reminder.
3. **Zero additional dependencies** — Git is pre-installed on macOS.
4. **Human-readable** — Users can browse the snapshot repo with any file manager or text editor.
5. **Simple implementation** — The current `SnapshotManager.swift` is ~200 lines shelling out to `/usr/bin/git`. Clean and maintainable.

### Dolt would make sense if:

1. **You needed SQL queries across snapshot history** — e.g., "show me all reminders whose priority changed in the last month" or "which reminders were deleted between snapshot 5 and snapshot 10?" This is hard with git (requires parsing JSON diffs) but trivial with Dolt.
2. **The dataset were much larger** — Tens of thousands of records where file-per-record git repos become unwieldy.
3. **You wanted to expose version history via the MCP server** — Dolt's SQL interface would make it easy to add tools like `query_reminder_history` or `diff_snapshots` that return structured data.
4. **There were a Swift-native or embedded option** — Without one, you're shelling out to `dolt` CLI just like you shell out to `git`, losing Dolt's main advantage (the SQL interface).

---

## Recommendation

**Stay with git.** The current approach is the right tool for this job.

If structured history queries become important in the future, a more pragmatic path would be:

1. Keep git for storage/versioning (it works well)
2. Add a SQLite index of snapshot history (lightweight, Swift-native via `sqlite3`)
3. Parse git diffs into structured data when needed

This gives you SQL queryability without adding a 103 MB Go binary dependency.

---

## Sources

- [Dolt Documentation — What Is Dolt?](https://docs.dolthub.com/)
- [Dolt GitHub Repository](https://github.com/dolthub/dolt)
- [Dolt Version Control Features](https://docs.dolthub.com/sql-reference/version-control)
- [Embedding Dolt in Go Applications](https://www.dolthub.com/blog/2022-07-25-embedded/)
- [Dolt is as Fast as MySQL (Dec 2025)](https://www.dolthub.com/blog/2025-12-04-dolt-is-as-fast-as-mysql/)
- [Dolt Diff vs SQLite Diff](https://www.dolthub.com/blog/2022-06-03-dolt-diff-vs-sqlite-diff/)
- [JSON Showdown: Dolt vs SQLite](https://www.dolthub.com/blog/2024-11-18-json-sqlite-vs-dolt/)
- [Sizing Your Dolt Instance](https://www.dolthub.com/blog/2023-12-06-sizing-your-dolt-instance/)
