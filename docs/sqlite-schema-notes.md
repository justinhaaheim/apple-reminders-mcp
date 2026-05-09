# Apple Reminders SQLite schema notes

This file captures everything we've learned about the on-disk Core Data
schema that backs Apple Reminders, focused on the fields the read-only
`ReminderDBReader` enrichment path consumes. EventKit remains
authoritative for writes; nothing here implies we mutate the store.

## Store discovery

```
~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/
├── Data-<uuid>.sqlite     ← live stores; one per CloudKit zone
├── Data-local.sqlite      ← legacy / dormant since 2023; skip
└── *.sqlite-wal, *.sqlite-shm  ← created transiently by SQLite; skip
```

`ReminderDBReader.discover()` opens each `Data-*.sqlite` (excluding
`Data-local.sqlite`) with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`
and the URI form `file:<path>?mode=ro`. WAL replay is required to see
current data, so we deliberately do not pass `immutable=1`.

## Core entities used by enrichment

| Table                | Purpose                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| `ZREMCDREMINDER`     | One row per reminder. UUID in `ZCKIDENTIFIER` (round-trips to EventKit's `calendarItemIdentifier`).     |
| `ZREMCDBASELIST`     | One row per list. UUID in `ZCKIDENTIFIER`. Holds section-membership JSON blobs.                         |
| `ZREMCDBASESECTION`  | Section definitions (`ZDISPLAYNAME`, `ZCKIDENTIFIER`). FK `ZLIST` → `ZREMCDBASELIST.Z_PK`.              |
| `ZREMCDOBJECT`       | Union table. `Z_ENT = 32` rows are hashtag applications (`ZHASHTAGLABEL` × `ZREMINDER…ZREMINDER5` FKs). |
| `ZREMCDHASHTAGLABEL` | Master hashtag inventory: `ZNAME`, `ZCANONICALNAME`, `ZRECENCYDATE`, `ZFIRSTOCCURRENCECREATIONDATE`.    |
| `Z_METADATA`         | Core Data version/uuid/plist; component of schema fingerprint.                                          |
| `Z_MODELCACHE`       | Compiled model blob; second component of schema fingerprint.                                            |

Tombstones: every row carries a `ZMARKEDFORDELETION` integer column.
Always filter `= 0` when reading. (One exception: `ZREMCDHASHTAGLABEL`
in the current schema doesn't have this column — labels are never
deleted, just orphaned.)

## Hashtags

A reminder's hashtag applications live in `ZREMCDOBJECT` rows where
`Z_ENT = 32`. The reminder FK has migrated across columns over schema
versions — `ZREMINDER2` is the current active one. We `COALESCE` the
six observed variants for forward-compat:

```sql
COALESCE(o.ZREMINDER2, o.ZREMINDER1, o.ZREMINDER,
         o.ZREMINDER3, o.ZREMINDER4, o.ZREMINDER5)
```

Master inventory query lives in `hashtagInventory(includeUnused:)`;
the per-reminder lookup in `hashtags(forReminderUUIDs:)`.

## Parent / child

`ZREMCDREMINDER.ZPARENTREMINDER` is an integer FK to the parent's
`Z_PK`, NULL for top-level reminders. UUIDs round-trip via
`ZCKIDENTIFIER` on both sides.

`children()` orders by `ZICSDISPLAYORDER ASC, Z_PK ASC` so that the
returned subtask list matches the user's arrangement in Reminders.app.

## Sections (kanban columns)

Section definitions are in `ZREMCDBASESECTION`. The interesting twist
is that **section membership is not stored as a foreign key on the
reminder row** — it's serialized as JSON on the parent list.

### Membership JSON (verified)

Column: `ZREMCDBASELIST.ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA`
(BLOB containing UTF-8 JSON).

```json
{
  "minimumSupportedVersion": 20230430,
  "memberships": [
    {
      "groupID": "EF456A06-151A-4AF0-901D-40F7D9404EBD",
      "memberID": "FB780964-E13C-418B-AB57-53A69292FDDE",
      "modifiedOn": 800021991.15653205
    }
  ]
}
```

- `groupID` → `ZREMCDBASESECTION.ZCKIDENTIFIER`
- `memberID` → `ZREMCDBASESECTION` is in the same list whose blob this
  is, so we resolve `groupID` against the list's sections.
- `modifiedOn` → Core Data timestamp (seconds since 2001-01-01 UTC).
  We don't currently surface this field.

### Section ordering (observed empty in fixture)

Column: `ZREMCDBASELIST.ZSECTIONIDSORDERINGASDATA`. Apple uses this for
explicit user-defined ordering when present. In the test fixture every
list has it as NULL — sections fall back to display-name ordering.
When non-null in the wild, the blob is JSON of the form
`["<sectionUUID>", …]` and would be the primary sort key.

## Date encoding

Apple stores Core Data timestamps as `Double` (seconds since
`2001-01-01 00:00:00 UTC`). Swift's `Date.timeIntervalSinceReferenceDate`
uses the same reference point — `Date(timeIntervalSinceReferenceDate:)`
is a direct conversion.

`SQLITE_NULL` (returned by `sqlite3_column_type`) distinguishes "missing"
from "0.0" since Core Data overloads REAL columns with NULL.

## Schema fingerprint

We hash `Z_METADATA` + `Z_MODELCACHE` rows with a deterministic FNV-1a
derivative, producing a 32-char hex digest. Same DB → same fingerprint
forever; an Apple schema bump produces a new digest, which we log
prominently so users / maintainers know to verify the enrichment paths.

## Read-only invariants verified

`Tests/AppleRemindersCoreTests/ReminderDBReaderTests.swift` includes a
`testNoFixtureMutation` test that records the mtime of every fixture
`.sqlite` file before exercising every enrichment query and re-checks
mtime afterwards. Any drift fails the test.

(SQLite may create transient `.sqlite-wal` / `.sqlite-shm` siblings on
open even in read-only mode if the source DB was last in WAL mode —
they're listed in `.gitignore` and cleaned by Reminders.app on its next
checkpoint. They never represent mutation of the actual data.)
