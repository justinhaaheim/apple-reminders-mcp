# jtest1-reminders-db fixture

A snapshot of an Apple Reminders Core Data store layout, captured from a dedicated test macOS account (`jtest1`) on 2026-05-09. Used by tests that exercise the read-only SQLite enrichment path (epic `apple-reminders-mcp-rbf`).

The directory layout mirrors the real `~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/` so production discovery code can run unmodified against this path.

## Provenance

Snapshots taken via `sqlite3 .backup` (consistent online backup, not raw `cp`) so the resulting files are self-contained and don't carry WAL/SHM siblings. The source account was newly seeded for this purpose; no real personal data is present.

## Contents

| File                     | Size   | Rows                                                                             | What it represents                                                                                      |
| ------------------------ | ------ | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `Data-5FDFBC03-….sqlite` | 1.1 MB | 57 reminders, 4 lists, 4 sections, 3 hashtag-applications, 1 parent + 5 children | **Primary fixture** — exercises hashtags, sections, parent/child, multi-section lists, tombstoned lists |
| `Data-99115FCC-….sqlite` | 892 KB | 48 reminders, all `ZMARKEDFORDELETION=1`                                         | Tests tombstone filtering — a stale CloudKit replica                                                    |
| `Data-7DFE19AA-….sqlite` | 860 KB | 0 rows of reminder data, 289 history rows                                        | Tests handling of dormant/migrated stores                                                               |
| `Data-32870CEC-….sqlite` | 736 KB | 1 system list (`SiriFoundInApps`)                                                | Tests skipping system-internal stores                                                                   |
| `Data-local.sqlite`      | 716 KB | Empty                                                                            | Tests handling of empty on-device stores                                                                |

Total: ~4.2 MB. Plain-committed (not LFS) — small enough not to warrant the indirection.

## Sensitivity

- All reminder titles and notes are synthetic (`Batch test N`, generic chores, placeholder names).
- The single contact-handle BLOB contains `+15555555555` (Apple's universal fictional number).
- CloudKit record blobs contain only infrastructure strings (`__defaultOwner__`, generic record types).
- No emails, phone numbers, real names, Siri / UserActivity payloads, or attachments.
- Two pseudonymous identifiers are present (`ZACCOUNTIDENTIFIER`, `ZCKUSERRECORDNAME`) — Core Data / CloudKit machinery, not PII. They identify the test account itself, which has no real-world content.

## What's exercised

- Hashtags: 3 hashtag labels (`Home`, `work`, plus one added with the subtasks); 3 applications across reminders that contain `#home` / `#Home` / `#work` in their titles.
- Sections: 4 sections across 2 lists. The `Reminders` list has `Test Column 1` / `Test Column 2`; `Groceries` has `Breads & Cereals` / `Sauces & Condiments`. `Work` has no sections.
- Parent/child: 1 parent (`Test parent reminder`) with 5 child rows.
- Tombstones: 1 list (`Reminders` Z_PK=2) marked for deletion, plus 48 tombstoned reminders in `Data-99115FCC`.
- Multi-store discovery: 5 stores total, of which only 2 hold meaningful data.

## Refreshing this fixture

If Apple changes the Reminders schema and a fresh capture is needed:

```bash
# from a terminal with permission to read jtest1's home directory
for f in <list of Data-*.sqlite filenames>; do
  sudo -u jtest1 sqlite3 \
    "/Users/jtest1/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/${f}" \
    ".backup 'test/fixtures/jtest1-reminders-db/${f}'"
done
sudo chown $USER test/fixtures/jtest1-reminders-db/*.sqlite
```

Verify post-refresh that the test set still covers hashtags, sections, parent/child, tombstones, and multi-store discovery before committing.
