# `reminders query` — foundation reference

A field guide to querying reminders. Approachable from a cold start: read top-down to learn the model, jump to **Recipes** when you know what you want.

> Today's date assumed: **2026-05-07**. Examples that compute relative dates (e.g. "last 7 days") use that as the anchor.

---

## Overview

`reminders query` searches reminders. It runs in two stages:

1. **Structured filters** — `--list`, `--status`, `--search`, the per-field date flags. Cheap, fast, applied at fetch time (some push down into EventKit's predicate).
2. **JMESPath** — a single expression as the positional `[QUERY]` argument. Runs on the result of stage 1, on the full reminder payload. Used for filtering JMESPath can express better, projection (transforming output shape), and sorting.

Both stages are optional. Running `reminders` with no args returns incomplete reminders from the default list — usually what you want.

---

## CLI-first / JMESPath-second convention

The two stages always run in this order:

> **Structured CLI flags filter first. The JMESPath expression filters and projects on whatever's left.**

That means the order you write things on the command line never changes the result:

```bash
reminders query --list "Work" "[?priority == 'high']" --pretty
reminders query "[?priority == 'high']" --list "Work" --pretty
# ↑ same result
```

Why two stages? Each does what it does best:

- **Structured filters** are concise and fast. `--list "Work"` reads cleanly and lets EventKit narrow what's fetched before any post-processing.
- **JMESPath** is composable and expressive. It does AND/OR, projection, sort, slice, count — things that would be ugly as flags.

When in doubt: prefer flags for the things that have them; reach for JMESPath for everything else.

---

## CLI flags reference

### List selection

| Flag              | Meaning                             |
| ----------------- | ----------------------------------- |
| `--list "Name"`   | One list by name (case-insensitive) |
| `--list-id "..."` | One list by ID                      |
| `--all-lists`     | Search across every list            |
| _(omitted)_       | The default list                    |

`--list`, `--list-id`, and `--all-lists` are mutually exclusive.

### Status

| Flag                  | Meaning                             |
| --------------------- | ----------------------------------- |
| `--status incomplete` | (default) Only incomplete reminders |
| `--status completed`  | Only completed reminders            |
| `--status all`        | Both                                |

### Text search

| Flag              | Meaning                                            |
| ----------------- | -------------------------------------------------- |
| `--search "term"` | Case-insensitive match across `title` and `notes`. |

For more flexible matching (regex-like patterns, conditions on other fields), drop `--search` and use JMESPath with `lower()` / `upper()`.

### Per-field date ranges

Each `from` is **inclusive lower bound** (`>=`); each `to` is **inclusive upper bound** (`<=`). Reminders missing the field are excluded from the filter.

| Flag                     | Filters by     |
| ------------------------ | -------------- |
| `--created-from <date>`  | `createdDate`  |
| `--created-to <date>`    | `createdDate`  |
| `--modified-from <date>` | `modifiedDate` |
| `--modified-to <date>`   | `modifiedDate` |
| `--due-from <date>`      | `dueDate`      |
| `--due-to <date>`        | `dueDate`      |

Date format: ISO 8601 with timezone (`2026-05-07T09:00:00-08:00`) or date-only (`2026-05-07`).

There's no per-field `completedDate` flag — the EventKit predicate doesn't expose it cleanly when combined with other filters. Use JMESPath: `[?completedDate >= '2026-04-30']`.

### Output shape

| Flag               | Meaning                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `--detail minimal` | `id`, `title`, plus context-implied `listName` / `isCompleted`                                                       |
| `--detail compact` | (default) Adds `notes`, `dueDate`, `priority`, `createdDate`, `modifiedDate`, plus enrichment fields. Nulls omitted. |
| `--detail full`    | Every field including `alarms`, `recurrenceRules`, `url`, plus enrichment fields. Nulls shown.                       |

Enrichment fields (`hashtags`, `parentId`, `childIds`, `section`) appear in `compact` and `full` when SQLite enrichment is available. They're omitted from `compact` when null (DB unavailable) and shown explicitly in `full`.

When you supply a JMESPath expression, `--detail` is ignored — JMESPath always operates on the full payload (so it can see all fields), and the output is whatever the expression returns.

### SQLite enrichment filters

Reading the read-only Apple Reminders Core Data store unlocks four extra
filter flags. EventKit doesn't surface any of these fields; the SQLite
layer is purely a read-through (no writes ever).

| Flag                     | Meaning                                                                     |
| ------------------------ | --------------------------------------------------------------------------- |
| `--hashtag <name>`       | Reminders with the named hashtag (case-insensitive on canonical name).      |
| `--parent <uuid>`        | Direct children of the given reminder UUID. Mutually exclusive with…        |
| `--top-level`            | …`--top-level`, which keeps only reminders without a parent.                |
| `--section <name\|uuid>` | Reminders in a section matching by display name or UUID (case-insensitive). |

These filters require Full Disk Access on the calling terminal. Without
FDA the filter is skipped with a single stderr warning and the unfiltered
result is returned. Same goes for the enrichment fields themselves —
they're `null` when the SQLite store is unreachable.

### Sort

| Flag              | Order                              |
| ----------------- | ---------------------------------- |
| `--sort newest`   | (default) `createdDate` descending |
| `--sort oldest`   | `createdDate` ascending            |
| `--sort priority` | `high` → `medium` → `low` → `none` |
| `--sort dueDate`  | Soonest first, nulls last          |

When you supply a JMESPath expression, `--sort` is ignored — sort inside the expression: `sort_by(@, &dueDate)` / `reverse(sort_by(@, &createdDate))`.

### Pagination

| Flag                | Meaning                                            |
| ------------------- | -------------------------------------------------- |
| `--per-page <int>`  | 1–1000. Omit to auto-paginate at 200.              |
| `--cursor <opaque>` | From the previous response's `pageInfo.endCursor`. |

When you supply a JMESPath expression, pagination is disabled — slice inside the expression: `[:50]`.

### Globals

| Flag          | Meaning                                           |
| ------------- | ------------------------------------------------- |
| `--pretty`    | Pretty-print JSON output                          |
| `--mock`      | In-memory mock store; doesn't touch real data     |
| `--test-mode` | Restrict writes to `[AR-MCP TEST]` prefixed lists |
| `--verbose`   | Stderr debug logging                              |

---

## JMESPath fundamentals

[JMESPath](https://jmespath.org) is a JSON query language. Two things to know up front:

1. The reminder list is an **array**: `[{...}, {...}, ...]`. Most expressions start with `[`.
2. JMESPath has **two important constructs**: filter projections (`[?expr]`) and pipes (`|`). Once you've seen them, the rest follows.

### Filter projection — `[?expr]`

Pick array elements that satisfy a boolean expression. The element under inspection is implicit.

```jmespath
[?priority == 'high']                           # high-priority reminders
[?priority != 'none']                           # any priority set
[?isCompleted]                                  # completed
[?!isCompleted]                                 # incomplete
[?dueDate == null]                              # no due date
[?dueDate >= '2026-05-07']                      # due today or later (lexical)
[?priority == 'high' && !isCompleted]           # AND
[?priority == 'high' || priority == 'medium']   # OR
[?!(priority == 'none')]                        # NOT
```

> **String comparisons** — `<`, `<=`, `>`, `>=` work on strings here even though the JMESPath spec restricts them to numbers. The Swift JMESPath implementation does lexical comparison, which is exactly what you want for ISO 8601 dates.

### Projection — pulling out fields

```jmespath
[].title                                        # array of titles
[].{name: title, due: dueDate}                  # array of {name, due} objects
[?priority == 'high'].title                     # filter, then project
[].{name: title, due: dueDate, list: listName}  # multi-field
```

### Pipes — chain stages

`|` re-evaluates the next expression against the current result. Useful when you want to filter, then project, then slice:

```jmespath
sort_by([?priority == 'high'], &dueDate) | [].title
[?dueDate != null] | sort_by(@, &dueDate) | [:10]
```

### Sort

```jmespath
sort_by(@, &createdDate)                        # ascending by createdDate
reverse(sort_by(@, &createdDate))               # descending
sort_by([?dueDate != null], &dueDate)           # filter, then sort
```

`@` is the current value (the whole array here). `&field` is an "expression reference" — `sort_by` and `min_by`/`max_by` take one to identify the sort key.

### Slice

```jmespath
[:10]                                           # first 10
[-5:]                                           # last 5
sort_by(@, &createdDate) | [:10]                # 10 oldest
```

### Count

```jmespath
length(@)                                       # count of current array
length([?priority == 'high'])                   # count after filter
```

### Useful built-ins

| Function                                          | Use                                |
| ------------------------------------------------- | ---------------------------------- |
| `contains(string\|array, value)`                  | Substring or array membership      |
| `starts_with(s, prefix)` / `ends_with(s, suffix)` | What it says                       |
| `length(x)`                                       | Length of array, object, or string |
| `sort_by(arr, &field)`                            | Sort by field                      |
| `reverse(x)`                                      | Reverse array or string            |
| `keys(obj)` / `values(obj)`                       | Object keys/values                 |
| `min_by(arr, &field)` / `max_by(arr, &field)`     | Single element by field            |

Field names are camelCase: `createdDate`, `modifiedDate`, `dueDate`, `completedDate`, `listName`, `isCompleted`, `priority`, `notes`, `title`, `url`, `alarms`, `recurrenceRules`.

---

## Project-specific JMESPath extensions

These functions are registered for `reminders query` but aren't part of standard JMESPath. They mirror the same names AWS CLI's JMESPath implementation provides.

### `lower(string)` — lowercase a string

```jmespath
[?contains(lower(title), 'meeting')]            # case-insensitive contains
[?lower(priority) == 'high']                    # belt-and-suspenders
```

### `upper(string)` — uppercase a string

```jmespath
[?upper(title) == upper('Buy MILK')]            # case-insensitive equality
```

Both raise a function-error if you pass non-string input. Use `null` checks (or `notes || ''`) for fields that can be null:

```jmespath
[?contains(lower(notes || ''), 'todo')]
```

---

## Recipes

Quick, copy-pasteable answers to common questions. All examples assume today's date is **2026-05-07**.

### 1. Task Journal: created in last 7 days OR with any priority

```bash
reminders query --list "Task Journal" --created-from 2026-04-30 --status all --pretty \
  "[?priority != 'none' || createdDate >= '2026-04-30']"
```

### 2. Task Journal: created more than 14 days ago

```bash
reminders query --list "Task Journal" --created-to 2026-04-23 --status all --pretty
```

### 3. High-priority incomplete reminders, all lists

```bash
reminders query --all-lists --pretty "[?priority == 'high']"
```

### 4. Reminders due in next 7 days, sorted by due date

```bash
reminders query --all-lists --due-from 2026-05-07 --due-to 2026-05-14 --sort dueDate --pretty
```

### 5. "meeting" in title (case-insensitive), due in next 14 days

```bash
reminders query --all-lists --due-to 2026-05-21 --pretty \
  "[?contains(lower(title), 'meeting')]"
```

### 6. Count of incomplete reminders in Work

```bash
reminders query --list "Work" --pretty "length(@)"
# or just look at .totalCount in the regular response
reminders query --list "Work" --pretty | jq '.totalCount'
```

### 7. 10 oldest reminders in Personal

```bash
reminders query --list "Personal" --status all --sort oldest --per-page 10 --pretty
# JMESPath equivalent (when you also need filtering):
reminders query --list "Personal" --status all --pretty "sort_by(@, &createdDate) | [:10]"
```

### 8. Recently completed reminders, all lists, last 7 days

```bash
reminders query --all-lists --status completed --detail full --pretty \
  "sort_by([?completedDate >= '2026-04-30'], &completedDate)"
```

`--detail full` is needed because `compact` (the default) doesn't include `completedDate`. JMESPath ignores `--detail`, so it'd see the field anyway — but the example here uses both filter and sort inside JMESPath.

### 9. Reminders with no due date

```bash
reminders query --all-lists --pretty "[?dueDate == null]"
```

### 10. Reminders modified today

```bash
reminders query --all-lists --modified-from 2026-05-07 --status all --pretty
```

### 11. Just titles for a quick scan

```bash
reminders query --list "Work" --pretty "[].title"
```

### 12. Multi-field projection of high-priority

```bash
reminders query --all-lists --pretty \
  "[?priority == 'high'].{title: title, due: dueDate, list: listName}"
```

---

## JMESPath vs jq

`reminders query` returns JSON, so `jq` works fine for further processing:

```bash
reminders query --all-lists --pretty | jq -r '.reminders[] | .title'
```

When to reach for which:

- **JMESPath** — anything that runs **inside** the server. Filtering before pagination, sorting before slicing, projection before output detail kicks in. It also has the project-specific `lower()` / `upper()`.
- **jq** — anything **after** results return. Reformatting, complex aggregation, regex (`test`, `match`), conditional logic (`if/then/else`), CSV/TSV (`@csv`, `@tsv`).

The two are complementary, not competing. A common pattern:

```bash
# Filter server-side with JMESPath, format client-side with jq
reminders query --all-lists "[?priority == 'high']" --pretty | \
  jq -r '.[] | [.title, .dueDate // "no date"] | @tsv'
```

---

## Things to know

- **JMESPath ignores `--detail`, `--sort`, and pagination flags.** It operates on full fields, results aren't sorted or paginated. Sort with `sort_by`, slice with `[N:M]`.
- **JMESPath ignores `--detail` only when present.** The CLI flags pre-filter the result set before JMESPath runs, so they still work.
- **Priority sorts lexically** (`high < low < medium < none`). Use `--sort priority` for the sensible order; in JMESPath use explicit equality.
- **Use single quotes around the JMESPath expression** in shells to avoid globbing on `[`. If your expression starts with `-`, separate with `--`: `reminders query -- "-not-an-expression-but-a-positional"`.
- **The `--mock` flag** runs against an in-memory store — useful for testing JMESPath syntax without touching real reminders. Pair with `_seed_mock_data` in MCP, or just use literals: `reminders --mock "lower('TEST')"` returns `"test"`.

---

## Sources

- JMESPath spec — https://jmespath.org/specification.html
- JMESPath tutorial — https://jmespath.org/tutorial.html
- AWS CLI's JMESPath extensions (where `lower` / `upper` come from) — https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html
- Swift implementation — https://github.com/adam-fowler/jmespath.swift
