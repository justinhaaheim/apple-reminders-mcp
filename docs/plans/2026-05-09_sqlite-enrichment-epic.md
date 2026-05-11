# SQLite Enrichment Epic — Work Plan

Epic: `apple-reminders-mcp-rbf` — Extend MCP/CLI with EventKit-invisible fields via direct SQLite read.

## Sub-beads

1. **aol** — DB reader scaffolding (gates everything)
2. **cvm** — Hashtags
3. **qfp** — Parent/child
4. **16x** — Sections
5. **9py** — Surface integration

## Environment notes

- Working from Linux (Swift 6.1, libsqlite3-dev installed). The codebase already
  uses `#if canImport(EventKit)` so the package builds on Linux with the
  EventKit-dependent parts elided.
- On Linux, `import SQLite3` doesn't work out of the box (no system module),
  so we add a `CSQLite3` system library target with a module map and use a
  `#if canImport(SQLite3)` toggle so production builds on macOS still get the
  Apple-supplied SQLite3 module verbatim, while Linux/CI uses the modulemap.
- Tests: there's no existing Swift test target. Adding a `swift test` target
  for the new DB layer is justified — the existing TS tests assume access to
  EventKit (a real macOS context) and aren't suitable for fixture-based
  read-only verification.

## Sub-bead 1 (aol) — DB reader scaffolding

Files:

- `Sources/CSQLite3/module.modulemap` + `shim.h` (Linux libsqlite3 binding)
- `Sources/AppleRemindersCore/ReminderDBReader.swift`
- `Tests/AppleRemindersCoreTests/ReminderDBReaderTests.swift`
- `Package.swift` updates (system library target, test target)

Public surface:

- `enum ReminderDBError`: notFound, permissionDenied, unsupportedSchema(String), sqliteError(Int32, String)
- `class ReminderDBReader`:
  - `init(storeURL: URL) throws` — opens with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`, URI form `file:...?mode=ro`
  - `static func discover(containerOverride: URL?) -> [ReminderDBReader]` — discovers stores in the group container; skips `Data-local.sqlite`, `*-wal`, `*-shm`
  - `func schemaFingerprint() throws -> String` — sha256 of Z_METADATA + Z_MODELCACHE rows
  - `func isSchemaSupported() throws -> Bool` — fingerprint vs. known-good list
  - `func reminderRowID(forUUID: String) throws -> Int64?` — UUID lookup
  - `deinit` closes connection
- Single stderr warning per process via an atomic flag.

## Sub-bead 2 (cvm) — Hashtag enrichment

- ReminderDBReader API:
  - `func hashtags(forReminderUUIDs: [String]) -> [String: [String]]`
  - `func hashtagInventory(includeUnused: Bool) -> [HashtagInfo]`
- Models: `hashtags: [String]?` on ReminderOutput (null when DB unavailable)
- CLI: `--hashtag <name>` filter; `reminders hashtags` command
- MCP: hashtag field on query_reminders output; new `list_hashtags` tool

Z_ENT for hashtag rows = 32; FK column is `ZREMINDER2` in current schema —
must `COALESCE(ZREMINDER2, ZREMINDER1, ZREMINDER, ZREMINDER3, ZREMINDER4, ZREMINDER5)` for forward-compat.

## Sub-bead 3 (qfp) — Parent/child

- ReminderDBReader API:
  - `func parentChildPairs(forReminderUUIDs: [String]) -> [(child: String, parent: String)]`
  - or batched `parents` and `children` per UUID
- Models: `parentId: String?` and `childIds: [String]?` on ReminderOutput
- CLI: `--parent <id>`, `--top-level` (mutually exclusive)
- MCP: `parentId` filter, `topLevelOnly` boolean

## Sub-bead 4 (16x) — Sections

JSON shape (verified from fixture):

```json
{"minimumSupportedVersion":20230430,"memberships":[{"groupID":"<section uuid>","memberID":"<reminder uuid>","modifiedOn":<float>}]}
```

- ReminderDBReader API:
  - `func sections(forListUUID: String) -> [SectionInfo]` (ordered by ZSECTIONIDSORDERINGASDATA)
  - `func reminderSectionMap(forListUUIDs: [String]) -> [String: SectionInfo]`
- Models: `section: { id, name }?` on reminders; `sections: [...]?` on lists
- CLI: `--section <name>` filter (requires `--list`)
- MCP: `sectionId` filter; `sections` array on get_lists output

## Sub-bead 5 (9py) — Surface integration

- Wire enrichment into RemindersManager (single batched query per result set)
- Update CLI flags, MCP tool schemas, help content
- Update CLAUDE.md, SKILL.md, query-reference.md, ROADMAP.md
- New `docs/sqlite-schema-notes.md`

## Progress

- [x] aol — DB reader scaffolding
- [x] cvm — Hashtags
- [x] qfp — Parent/child (also fixed pre-existing macOS CI failure by
      pinning swift-argument-parser <1.6, since its 1.7.0's
      `internal import os` requires Swift 6 / experimental flag).
- [x] 16x — Sections (membership JSON shape verified and documented in
      `docs/sqlite-schema-notes.md`)
- [x] 9py — Surface integration (CLAUDE.md, SKILL.md, query-reference.md,
      ROADMAP.md, HelpContent.swift all updated)
- [ ] Close epic

## Verification done locally (Linux Swift 6.1)

- `swift build` clean.
- `swift test` — 30 XCTest cases pass against the jtest1 fixture.
  - 9 in ReminderDBReaderTests (incl. mtime invariant)
  - 7 in HashtagEnrichmentTests
  - 6 in ParentChildEnrichmentTests
  - 8 in SectionEnrichmentTests
- `bun run signal` — prettier clean.
- CLI smoke: `reminders --help` lists `hashtags`; `reminders hashtags
--mock --pretty` gracefully falls through with a single stderr warning
  when DB enrichment is unavailable.

## Verification still needed (macOS)

These can't be done from this Linux environment:

- Run binary from terminal with FDA, confirm `hashtags`, `parentId`,
  `childIds`, `section` populate against real EventKit data.
- Performance: 1,000 reminders enriched in < 100ms over EventKit-only
  baseline (acceptance criterion of bead 9py).
- Confirm the existing `bun test` TS suite still passes (no regressions
  in batch operations).
