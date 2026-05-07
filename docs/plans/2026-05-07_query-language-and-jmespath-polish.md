# Query language & JMESPath polish — plan + discussion record

> **Status**: complete
> **Started**: 2026-05-07
> **Completed**: 2026-05-07 (epic `apple-reminders-mcp-kw8` closed)
> **Supersedes**: the GitHub-style query-language migration (epic `apple-reminders-mcp-3h8`, closed)

## What shipped

All 11 sub-beads of `apple-reminders-mcp-kw8` are closed:

- **Manager** (`eic`): `RemindersManager.queryReminders` accepts `createdFrom`/`createdTo`/`modifiedFrom`/`modifiedTo`/`dueFrom`/`dueTo`. Due-date range pushes into `predicateForIncompleteReminders` when status=incomplete; created/modified/all-status due-date are post-fetch filters. Old `dateFrom`/`dateTo` auto-switch removed.
- **JMESPath functions** (`z6e`): `Sources/AppleRemindersCore/JMESPathExtensions.swift` defines `LowerFunction` and `UpperFunction` and a `JMESRuntimeFactory.makeRuntime()` that registers them. `applyJMESPath` now uses the factory so the extensions are available everywhere.
- **CLI flags + positional JMESPath** (`xda` + `unl`): `QueryCommand.swift` has the six per-field date flags. `--from`/`--to`/`--jmespath` removed (ArgumentParser cleanly rejects them). The JMESPath query is `@Argument` (positional).
- **MCP schema** (`jcj`): `query_reminders` schema adds the six per-field date inputs, removes `dateFrom`/`dateTo`. `query` field name kept (already in use). Description mentions the convention and links to `docs/query-reference.md`.
- **HelpContent** (`n8p`): `topLevelVerbose`, `topLevelSkill`, `queryConcise`, `queryVerbose`, `querySkill` updated.
- **Foundation reference** (`lwv`): `docs/query-reference.md` written from scratch (Overview, CLI-first convention, CLI flag reference, JMESPath fundamentals, project extensions, recipes, JMESPath-vs-jq, field reference, sources). Old `docs/query-cheatsheet.md` removed.
- **SKILL.md docs** (`stm`, `ul4`): top-level `SKILL.md` and `skills/reminders/SKILL.md` updated with the convention, new flag set, positional JMESPath, lower()/upper() guidance.
- **CLAUDE.md** (`14z`): query_reminders description in the tools table mentions the convention and links to the reference. CLI Usage section updated with the new flag examples and convention statement.
- **Tests** (`5bu`): `test/search.test.ts` has two new describe blocks ("per-field date filtering" and "positional JMESPath via the `query` field"). `test/api-parity.test.ts` updated to use the new fields. Schema snapshot regenerated. **All 102 tests pass.**

Verification:

- `bun run signal` (prettier-check) — passes.
- `swift build -c release` — passes.
- All tests pass: `AR_MCP_TEST_MODE=1 bun test` → 102 pass / 0 fail.
- ArgumentParser cleanly rejects `--from`/`--to`/`--jmespath` with "Unknown option" errors.
- Same flags + same JMESPath produce identical results regardless of CLI argument order (verified manually + has a test).

## Things noted but not addressed (not blocking)

- `HelpSystem.interceptIfNeeded()` calls `_exit(0)` after `print()` without flushing stdout, so on Linux `reminders --help` produces no output. Pre-existing — predates this work and is unrelated to the migration. Worth a separate small bead.

This document captures both the **decision and the discussion that led
there**. Several alternatives we explored remain plausible future
directions and are worth revisiting; they're noted under
[Deferred / future considerations](#deferred--future-considerations).

---

## TL;DR

We're keeping JMESPath as the query language and polishing the rough
edges, instead of building a custom GitHub-search-style parser.
Specifically:

1. **Replace `--from` / `--to` with explicit per-field flags**: `--created-from`, `--created-to`, `--modified-from`, `--modified-to`, `--due-from`, `--due-to`. Today's "auto" semantics (dueDate for incomplete, completionDate for completed) are gone — too implicit.
2. **Make the JMESPath query a positional argument** instead of `--jmespath EXPR`. `reminders query --created-from 2026-04-30 '[?priority == \'high\']'`.
3. **Register `lower()` and `upper()` as custom JMESPath functions** so case-insensitive comparison works without spec gymnastics.
4. **Define and document the convention**: CLI flags filter first (at EventKit fetch level when possible), JMESPath runs after. No exceptions, no order-dependence.
5. **Build a solid foundation reference** (cheatsheet + tutorial) for JMESPath in `docs/`, linked from `SKILL.md` / `CLAUDE.md` / `--help`. Approachable for both LLMs and humans.
6. **Rewrite the project skill files** (`SKILL.md`, `skills/reminders/SKILL.md`, `CLAUDE.md`, `HelpContent.swift`) to teach this convention.

---

## Discussion record

The path here was non-linear. Quick replay of the thread:

### Starting question

User wanted to run a JMESPath-style ad-hoc query for "Task Journal,
created in last 7 days OR has priority set, deduplicated and merged."

I steered toward a custom GitHub-style query language migration —
incorrect framing, the existing JMESPath surface already covered this
case. The "limitation" I cited (JMESPath spec restricts `<`/`>` to
numbers) wasn't a limitation in our actual `jmespath.swift`
implementation, which supports lexical string comparison
(`Variable.swift:220-229`).

The original task works **today**:

```bash
reminders query --list "Task Journal" --status all --pretty \
  --jmespath "[?createdDate >= '2026-04-30' || priority != 'none']"
```

### Detour: GitHub-style migration plan

I drafted a full migration plan (custom parser, AST, FilterPlan,
positional query, `--or` flag, MCP shape) and created an epic +
11 sub-beads. The plan was thorough but the **cost-benefit was poor**
for two reasons:

1. The existing JMESPath surface was already capable; the new syntax
   was an ergonomic upgrade, not a capability upgrade.
2. Writing a small parser in Swift was achievable (~200 LoC) but adds
   a class of new failure modes (parse errors, escaping, edge cases)
   for a feature that's mostly recognizability. There's no
   off-the-shelf Swift parser for Lucene/GitHub-search syntax;
   integrating other-language parsers is more overhead than the parser
   itself.

### Pivotal user input

User raised the right concerns:

- **JMESPath isn't intuitive yet** for them — but that argues for
  _teaching_ it well, not replacing it.
- **Building a parser introduces failure points** — yes, real concern.
- **JMESPath's value to LLMs**: it's a flexible tool for narrowing
  context-window consumption (filter + project before results return).
  This is a **feature of JMESPath itself**, not its syntax — replacing
  it loses this.
- **Two ways to do things is confusing**: today CLI flags AND JMESPath
  can both filter, sometimes overlapping. The fix should be a clear
  convention and an integrated UX, not adding a third language.

### jq integration tangent

We considered replacing JMESPath with jq (more powerful, regex,
case-insensitive built-in, more widely recognized). Three integration
paths exist:

- **Path A**: shell out to system `jq` binary (~20 LoC, requires user has jq installed)
- **Path B**: bundle `jq` as a binary resource (~750KB + code-signing)
- **Path C**: link `libjq.a` statically (1–3 days of SwiftPM C-target setup)

Decision: **don't integrate jq**. Reasoning:

- jq's syntax isn't dramatically friendlier than JMESPath for filter
  ops (`.[] | select(.x == "y")` vs `[?x == 'y']`).
- jq's wins are regex, conditionals, aggregation — useful but not
  blocking for our use case.
- Users can still pipe to system `jq` for transformations: `reminders
query --jmespath '...' | jq '...'`. This pattern mirrors AWS CLI +
  jq in the wild.
- Adding jq doesn't reduce "two ways to do things" — it'd make it three.

Captured as a deferred bead.

### JMESPath pushdown optimizer

Considered: parse the user's JMESPath AST, detect `listName == 'X'`
clauses at the top of a conjunction, push down to EventKit's factory
predicate. The trap: only safe inside a top-level AND, not inside an
OR (would silently drop matches). It's a small optimizer with real
correctness reasoning. Worth doing only if performance bites.

Captured as a deferred bead.

### What converged

Stick with JMESPath. Smooth the rough edges. Define and document the
convention. Teach the language well. Add `lower()`/`upper()` to fix
the case-insensitivity gap. Replace `--from`/`--to` with unambiguous
per-field flags. Make the JMESPath query positional so it reads like
`gh search "..."`.

---

## Decisions

### Convention (governing rule)

**CLI flags filter at fetch time. JMESPath filters and projects on
the result.** Order of CLI flags on the command line doesn't matter —
they always run first, JMESPath always runs second. This is
documented at the top of `--help`, in `SKILL.md`, and in the
foundation reference.

Why: predictability. Users (humans + LLMs) only need to learn one
rule.

### CLI surface (after this work)

```bash
# Date ranges — explicit per-field
reminders query --created-from 2026-04-30 --created-to 2026-05-07
reminders query --modified-from 2026-05-01
reminders query --due-from 2026-05-08 --due-to 2026-05-15

# JMESPath as positional
reminders query "[?priority == 'high']"
reminders query --list "Work" "[?contains(lower(title), 'meeting')]"

# Combine — convention says CLI flags first, JMESPath second
reminders query --list "Task Journal" --created-from 2026-04-30 --status all \
  "[?priority != 'none']"
```

Removed: `--from`, `--to`, `--jmespath`. Behavior change for any
caller depending on the auto-semantics of `--from`/`--to`. Fine — the
project doesn't have public API stability commitments yet.

Retained: `--list`, `--list-id`, `--all-lists`, `--status`,
`--search`, `--detail`, `--sort`, `--per-page`, `--cursor`, `--pretty`,
`--mock`, `--test-mode`, `--verbose`.

### MCP surface

`query_reminders` schema:

- Add `createdFrom`, `createdTo`, `modifiedFrom`, `modifiedTo`,
  `dueFrom`, `dueTo` (all optional ISO 8601 strings).
- Remove `dateFrom`, `dateTo`.
- Rename existing `jmespathQuery` field to `query` (positional CLI
  arg's MCP equivalent). Or keep as `jmespath` if rename causes too
  much churn — final naming TBD during implementation. Short, clear
  name preferred.

### `lower()` / `upper()` JMESPath functions

Implement `JMESFunction` types and register at startup via
`Runtime.registerFunction`. Document them in the foundation
reference as project-specific extensions (mirrors AWS CLI's `lower`
extension, which is also non-standard).

Skip `now()` for now — date arithmetic isn't built into JMESPath,
so `now()` alone doesn't compose well; better to revisit if a
specific use case requires it.

### Documentation deliverables

Each gets its own bead:

- `HelpContent.swift` — CLI `--help` and `--help --verbose`
- `SKILL.md` (top-level) — primary reference for both LLMs and humans
- `skills/reminders/SKILL.md` — Claude Code plugin skill
- `CLAUDE.md` — project overview / convention
- `docs/query-reference.md` — foundation reference (replaces
  `docs/query-cheatsheet.md`; merges recipe content + JMESPath
  fundamentals into one approachable doc)

The foundation reference is the most important new artifact. It
should make JMESPath approachable from a cold start: what it is,
core concepts (filter projection, pipe, comparisons, functions),
project-specific extensions (`lower`/`upper`), the CLI-first /
JMESPath-second convention, and a tested set of recipes.

---

## Work items (and beads)

A new epic encapsulates the migration. Sub-beads have explicit
acceptance criteria. The deferred items live as standalone beads
outside the epic so they're trackable but not blocking.

### Epic

**JMESPath polish + ergonomic date flags** — closes when all
sub-beads close, `bun run signal` + `bun run test` pass, and the
headline verification runs.

### Sub-beads

1. **Manager: per-field date filtering** — extend
   `RemindersManager.queryReminders` to accept separate
   `createdFrom`/`createdTo`/`modifiedFrom`/`modifiedTo`/`dueFrom`/`dueTo`
   parameters. Push due-date ranges into EventKit factory predicates
   when status allows; created/modified are post-fetch filters.
   Remove the old auto-switch branch.
2. **CLI: per-field date flags + remove `--from`/`--to`** — add
   six `--*-from` / `--*-to` flags, validate ISO 8601, route to
   manager.
3. **CLI: positional JMESPath argument + remove `--jmespath`** —
   convert to `@Argument(...) var query: String?` in
   `QueryCommand.swift`. Empty/missing = no JMESPath stage.
4. **MCP: schema update** — add per-field date inputs, remove
   `dateFrom`/`dateTo`, rename `jmespathQuery` → `query`.
   Regenerate schema snapshot.
5. **JMESPath: register `lower()` and `upper()`** — implement
   `JMESFunction` structs, register at MCP/CLI startup. Unit
   coverage in TS tests.
6. **Docs: foundation reference (`docs/query-reference.md`)** —
   merge cheatsheet + JMESPath fundamentals. Sections: overview,
   CLI-first convention, CLI flags reference, JMESPath
   fundamentals, project extensions, recipes, jq-vs-JMESPath
   comparison, sources.
7. **Docs: `HelpContent.swift`** — concise + verbose help reflect
   new flag set, positional query, link to foundation reference.
8. **Docs: top-level `SKILL.md`** — rewrite with
   CLI-first/JMESPath-second convention, link to foundation
   reference.
9. **Docs: plugin `skills/reminders/SKILL.md`** — same convention,
   updated user-preferences section.
10. **Docs: `CLAUDE.md`** — update CLI Usage section, mention
    convention, link to foundation reference.
11. **Tests: extend `test/search.test.ts`** — cover per-field date
    flags, positional JMESPath, `lower()`/`upper()` functions, the
    convention's predictability (flag-then-jmes vs jmes-then-flag
    yield identical results).

### Deferred (separate beads, not blocking the epic)

- **JMESPath pushdown optimizer**: parse AST, detect
  `listName == 'X'` in top-level conjunctions, push to EventKit
  factory predicate. Only safe in top-level ANDs.
- **jq integration evaluation**: revisit if specific use cases
  (regex, complex aggregation) start hurting. Three paths
  documented above.
- **GitHub-style query syntax** (the previous epic): not closed off
  conceptually — if users (humans or LLMs) keep struggling with
  JMESPath, this becomes a stronger case. Re-read the previous epic's
  beads (`apple-reminders-mcp-3h8` and friends) for the design work
  already done.

---

## Verification

```bash
bun run build

# Headline — original motivating task:
.build/release/reminders query --list "Task Journal" --created-from 2026-04-30 \
  --status all --pretty "[?priority != 'none' || createdDate >= '2026-04-30']"

# Per-field dates without JMESPath:
.build/release/reminders query --modified-from 2026-05-01 --pretty

# Case-insensitive search via lower():
.build/release/reminders query "[?contains(lower(title), 'meeting')]" --pretty

# CLI-first convention regression test (these should be equivalent):
.build/release/reminders query --list "Work" "[?priority == 'high']" --pretty
.build/release/reminders query "[?priority == 'high']" --list "Work" --pretty
```

Then `bun run test` and `bun run signal`.

---

## Things to revisit

- **GitHub-style syntax** — full plan still in
  `~/.claude/plans/let-s-actually-just-plan-imperative-marble.md` and
  in the closed epic's bead descriptions. Real code-design work
  done; not lost.
- **jq integration** — three concrete paths documented.
- **Pushdown optimizer** — useful when reminder corpus gets large.
- **`now()` and date arithmetic in JMESPath** — punted because
  arithmetic on dates isn't built-in, but if a recurring use case
  (e.g. "show me everything from last week") becomes annoying to
  type as a hardcoded date, revisit.
- **Convention enforcement**: today the convention is documented
  but not enforced — there's no warning if someone does something
  weird. If users get confused in practice, consider adding a
  warning or error for ambiguous combinations.
