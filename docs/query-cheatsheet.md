# `reminders query` recipe book — JMESPath vs GitHub-style

Side-by-side comparison of the two query approaches for `reminders query`.

- **JMESPath** column: works **today**, no new code needed. Uses `--jmespath`.
- **GitHub-style** column: proposed query language (epic
  `apple-reminders-mcp-3h8`). Not yet implemented — shown so you can
  compare ergonomics.

## Two styles for JMESPath: hybrid vs pure

JMESPath examples in this doc default to a **hybrid** style: CLI flags
(`--list`, `--status`, `--search`) narrow at the EventKit
factory-predicate level, and JMESPath handles whatever flags can't
express.

You can also write **pure JMESPath** — one self-contained expression
that filters everything. CLI flags then just open the floodgates
(`--all-lists --status all`).

**Hybrid (this doc's default):**

```bash
swift run reminders query --list "Task Journal" --status all --pretty \
  --jmespath "[?createdDate >= '2026-04-30' || priority != 'none']"
```

**Pure JMESPath equivalent:**

```bash
swift run reminders query --all-lists --status all --pretty \
  --jmespath "[?listName == 'Task Journal' && (createdDate >= '2026-04-30' || priority != 'none')]"
```

### Conversion table — CLI flag ↔ JMESPath

| CLI flag              | JMESPath equivalent                                    |
| --------------------- | ------------------------------------------------------ |
| `--list "X"`          | `listName == 'X'`                                      |
| `--all-lists`         | _(omit; JMESPath sees all)_                            |
| `--status incomplete` | `[?!isCompleted]`                                      |
| `--status completed`  | `[?isCompleted]`                                       |
| `--status all`        | _(no extra filter needed)_                             |
| `--search "term"`     | `contains(title, 'term') \|\| contains(notes, 'term')` |

### When to prefer which

- **Hybrid** is faster when you have many thousands of reminders — the
  factory predicate narrows what EventKit returns.
- **Pure** gives you one self-contained expression you can save, share,
  or build on. Easier to learn JMESPath fluently when everything lives
  in one place.
- **Case sensitivity gotcha**: `--search` is case-insensitive;
  JMESPath `contains()` is case-sensitive. For free-text search, the
  hybrid `--search` is usually still the right tool.

## Quick syntax reference

### JMESPath (current)

| Pattern             | Form                                                                 |
| ------------------- | -------------------------------------------------------------------- |
| Filter equals       | `[?field == 'value']`                                                |
| Filter not equals   | `[?field != 'value']`                                                |
| Comparison (string) | `[?field >= '2026-04-30']`                                           |
| AND                 | `[?A == 'x' && B == 'y']`                                            |
| OR                  | `[?A == 'x' \|\| B == 'y']`                                          |
| Sort ascending      | `sort_by([?…], &field)`                                              |
| Sort descending     | `reverse(sort_by([?…], &field))`                                     |
| Project field       | `[].title`                                                           |
| Multiple fields     | `[].{a: title, b: createdDate}`                                      |
| Count               | `length([?…])`                                                       |
| Quirks              | strings need `'…'`, fields camelCase, `&field` only inside `sort_by` |

### GitHub-style (proposed)

| Pattern    | Form                                          |
| ---------- | --------------------------------------------- |
| Equals     | `priority:high`                               |
| Not equal  | `-priority:none` _(future, TBD)_              |
| Comparison | `created:>=2026-04-30`                        |
| Range      | `created:2026-04-30..2026-05-07`              |
| AND        | whitespace: `priority:high status:incomplete` |
| OR         | repeated `--or` flag (CLI) / array (MCP)      |
| Quoting    | `list:"Task Journal"`                         |
| Free text  | bare term: `"team standup"`                   |
| Sort       | still via `--sort` flag                       |

---

## Recipes

Today's date assumed: **2026-05-07**. 7 days ago = 2026-04-30; 14 days ago = 2026-04-23.

### 1. All reminders in Task Journal created in last 7 days OR with any priority

The original motivating query.

**JMESPath (today):**

```bash
swift run reminders query --list "Task Journal" --status all --pretty \
  --jmespath "[?createdDate >= '2026-04-30' || priority != 'none']"
```

**GitHub-style (proposed):**

```bash
swift run reminders query --pretty \
  'list:"Task Journal" created:>=2026-04-30 status:all' \
  --or 'list:"Task Journal" priority:>=low status:all'
```

---

### 2. All reminders in Task Journal created **more than 14 days ago**

**JMESPath:**

```bash
swift run reminders query --list "Task Journal" --status all --pretty \
  --jmespath "[?createdDate < '2026-04-23']"
```

**GitHub-style:**

```bash
swift run reminders query --pretty \
  'list:"Task Journal" created:<2026-04-23 status:all'
```

---

### 3. All high-priority incomplete reminders across all lists

**JMESPath:**

```bash
swift run reminders query --pretty \
  --jmespath "[?priority == 'high']"
```

(Status defaults to `incomplete`; no `--list` means default list — use `--all-lists` to span all.)

```bash
swift run reminders query --all-lists --pretty \
  --jmespath "[?priority == 'high']"
```

**GitHub-style:**

```bash
swift run reminders query --pretty 'priority:high'
```

(Omitting `list:` means all lists in the new design.)

---

### 4. Reminders due in the next 7 days, sorted by due date

**JMESPath:**

```bash
swift run reminders query --all-lists --pretty \
  --jmespath "sort_by([?dueDate >= '2026-05-07' && dueDate <= '2026-05-14'], &dueDate)"
```

(Sort happens inside JMESPath because `--sort` is bypassed when `--jmespath` is set.)

**GitHub-style:**

```bash
swift run reminders query --pretty --sort dueDate \
  'due:2026-05-07..2026-05-14'
```

---

### 5. Reminders with "meeting" in title, due in next 14 days

**JMESPath** — combine server-side `--search` with JMESPath:

```bash
swift run reminders query --all-lists --search "meeting" --pretty \
  --jmespath "[?dueDate <= '2026-05-21']"
```

**GitHub-style:**

```bash
swift run reminders query --pretty \
  '"meeting" due:<=2026-05-21'
```

---

### 6. Count of incomplete reminders in Work list

**JMESPath:**

```bash
swift run reminders query --list "Work" --pretty \
  --jmespath "length(@)"
```

(Or just look at `totalCount` in the regular response wrapper without `--jmespath`.)

**GitHub-style:**

```bash
swift run reminders query 'list:"Work"' | jq '.totalCount'
```

(No first-class count operator in the proposed grammar; `jq` for now.)

---

### 7. 10 oldest reminders in Personal list (by creation)

**JMESPath:**

```bash
swift run reminders query --list "Personal" --status all --pretty \
  --jmespath "sort_by(@, &createdDate)[:10]"
```

(`[:10]` is a JMESPath slice — first 10 elements after sorting.)

**GitHub-style:**

```bash
swift run reminders query --pretty --sort oldest --per-page 10 \
  'list:"Personal" status:all'
```

---

### 8. Recently completed reminders across all lists (last 7 days)

**JMESPath:**

```bash
swift run reminders query --all-lists --status completed --pretty \
  --jmespath "sort_by([?completionDate >= '2026-04-30'], &completionDate)"
```

Note: needs `--detail full` if you want the full reminder payload; `compact` (the default) doesn't include `completionDate`.

```bash
swift run reminders query --all-lists --status completed --detail full --pretty \
  --jmespath "sort_by([?completionDate >= '2026-04-30'], &completionDate)"
```

**GitHub-style:**

```bash
swift run reminders query --pretty --sort newest \
  'completed:>=2026-04-30 status:completed'
```

---

### 9. Reminders with no due date set

**JMESPath:**

```bash
swift run reminders query --all-lists --pretty \
  --jmespath "[?dueDate == null]"
```

**GitHub-style:**

```bash
swift run reminders query --pretty 'no:due'   # syntax TBD; not in v1 grammar
```

(Negative-existence queries aren't in the proposed v1 grammar — JMESPath stays the better tool for these.)

---

### 10. Reminders modified today

**JMESPath:**

```bash
swift run reminders query --all-lists --status all --pretty \
  --jmespath "[?lastModifiedDate >= '2026-05-07']"
```

**GitHub-style:**

```bash
swift run reminders query --pretty \
  'modified:>=2026-05-07 status:all'
```

---

### 11. Title-only output for a quick scan

**JMESPath** — extract the field via projection:

```bash
swift run reminders query --list "Work" --pretty \
  --jmespath "[].title"
```

**GitHub-style:** still use `--jmespath` for projection (the new syntax is filter-only):

```bash
swift run reminders query 'list:"Work"' --jmespath "[].title" --pretty
```

(JMESPath remains the right tool for _transforming_ output; the new syntax is for _filtering_.)

---

### 12. Multi-field projection

**JMESPath:**

```bash
swift run reminders query --all-lists --pretty \
  --jmespath "[?priority == 'high'].{title: title, due: dueDate, list: listName}"
```

Same approach with the proposed syntax — filter via query string, project via JMESPath.

---

## When to reach for which

**Reach for the proposed GitHub-style syntax** for filtering: anything
with `field:value` or comparisons or ranges.

**Reach for JMESPath** for:

- Anything not yet supported by the new grammar (existence checks, projections, counts).
- Arbitrary output shaping — extracting / renaming / restructuring fields.
- Sorting + filtering when you need to filter by something the new
  grammar doesn't cover.

The two are complementary: `--jmespath` stays as the projection /
escape-hatch tool; the GitHub-style query string handles the common
filter cases without syntax overhead.

## Things to know about JMESPath in this project

1. The Swift implementation (`jmespath.swift`) supports lexical comparison of strings via `<`/`<=`/`>`/`>=` even though the JMESPath spec restricts them to numbers — this is what makes ISO 8601 date comparison work.
2. When `--jmespath` is set, **`--sort` is bypassed** and **pagination is disabled** — sort inside the expression with `sort_by(@, &field)`.
3. JMESPath operates on the full reminder payload regardless of `--detail` — `--detail` only affects non-jmespath output.
4. Field names are camelCase: `createdDate`, `lastModifiedDate`, `dueDate`, `completionDate`, `listName`, `isCompleted`, `priority`.
5. `priority` values: `'none'`, `'low'`, `'medium'`, `'high'`. Sorts lexically as `high < low < medium < none` — for ordering by importance, use explicit equality checks: `[?priority == 'high' || priority == 'medium']`.

## Sources

- JMESPath spec: https://jmespath.org/specification.html
- JMESPath tutorial: https://jmespath.org/tutorial.html
- GitHub search syntax (proposed family ref): https://docs.github.com/en/search-github/searching-on-github/understanding-the-search-syntax
