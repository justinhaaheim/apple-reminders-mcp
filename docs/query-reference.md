# `reminders query` reference

Foundation reference for querying reminders. Approachable from a cold start: read top to bottom and you'll be able to write working queries in a few minutes. Equally useful for humans and LLMs.

> **TL;DR**: CLI flags filter first, JMESPath filters/projects second. Order on the command line doesn't matter — flags always run first. That's the whole convention.

---

## 1. Overview

`reminders query` is the primary search command. It has two complementary filter layers:

1. **Structured CLI flags** — `--list`, `--status`, `--search`, the per-field date ranges, and so on. These run at fetch time. Where possible they push down to EventKit's factory predicates so the OS does the work.
2. **JMESPath expression** — an optional positional argument. Runs after the CLI flags and operates on the result. JMESPath is also the only layer that can project / reshape output.

Both layers are powerful on their own; you combine them when one isn't enough.

The default with no arguments returns incomplete reminders from the default list, sorted newest first.

```bash
reminders                          # same as `reminders query`
reminders query --pretty           # JSON-pretty output
```

---

## 2. The CLI-first convention

> **Rule**: CLI flags filter at fetch time. JMESPath runs after. Always.

This is the single rule that governs every `reminders query` invocation. It exists for two reasons:

- **Predictability.** No matter how you order arguments on the command line, the same flags + same JMESPath expression produce the same result.
- **Performance.** CLI flags push down to EventKit when they can. JMESPath always runs on the post-fetch set.

You can't reorder the layers, only what gets done in each:

```bash
# These two invocations are equivalent. CLI flags always run first.
reminders query --list "Work" "[?priority == 'high']"
reminders query "[?priority == 'high']" --list "Work"
```

If you want to filter by something the flags don't cover (e.g. `priority == 'high'`), put it in the JMESPath argument. If you want to filter by something they do (e.g. `--list`), use the flag — it's faster and clearer.

---

## 3. CLI flag reference

### Selection

| Flag                  | Effect                                |
| --------------------- | ------------------------------------- |
| `--list "Name"`       | Match a list by case-insensitive name |
| `--list-id "x-..."`   | Match a list by exact ID              |
| `--all-lists`         | Search across every list              |
| _(none of the above)_ | Default list                          |
| `--status incomplete` | (default) Incomplete reminders only   |
| `--status completed`  | Completed reminders only              |
| `--status all`        | Both                                  |

### Text search

| Flag           | Effect                                                  |
| -------------- | ------------------------------------------------------- |
| `--search "x"` | Case-insensitive substring match in `title` and `notes` |

### Date ranges (per-field)

Each flag targets exactly one reminder field. There is no auto-switching.

| Flag                | Field                | Notes                                                                                                    |
| ------------------- | -------------------- | -------------------------------------------------------------------------------------------------------- |
| `--created-from D`  | createdDate ≥ D      | Post-fetch filter                                                                                        |
| `--created-to D`    | createdDate ≤ D      | Post-fetch filter                                                                                        |
| `--modified-from D` | lastModifiedDate ≥ D | Post-fetch filter                                                                                        |
| `--modified-to D`   | lastModifiedDate ≤ D | Post-fetch filter                                                                                        |
| `--due-from D`      | dueDate ≥ D          | Pushed to EventKit when `--status incomplete`. Reminders with no due date are excluded from this filter. |
| `--due-to D`        | dueDate ≤ D          | Same as above.                                                                                           |

`D` is ISO 8601 (`2026-03-07T09:00:00-08:00`) or a date-only `YYYY-MM-DD`.

### Output shape

| Flag               | Effect                                                      |
| ------------------ | ----------------------------------------------------------- |
| `--detail minimal` | id, title (plus listName/isCompleted when not implied)      |
| `--detail compact` | (default) compact useful set, nulls omitted                 |
| `--detail full`    | every field, nulls preserved as `null`                      |
| `--sort newest`    | (default) by createdDate desc                               |
| `--sort oldest`    | by createdDate asc                                          |
| `--sort priority`  | high → low                                                  |
| `--sort dueDate`   | ascending, nulls last                                       |
| `--per-page N`     | results per page (auto-paginates at 200 when omitted)       |
| `--cursor C`       | opaque cursor from previous response's `pageInfo.endCursor` |
| `--pretty`         | pretty-print JSON                                           |

When the JMESPath argument is supplied, `--sort` and `--detail` are ignored — JMESPath always operates on full fields and returns whatever shape the expression produces.

---

## 4. JMESPath fundamentals

JMESPath is a JSON query language similar in spirit to XPath. The full spec is at <https://jmespath.org/specification.html> (this reference covers what you need for `reminders query`).

The input to your expression is the array of reminder objects that the CLI flags returned. Each reminder has fields like `id`, `title`, `notes`, `priority`, `dueDate`, `createdDate`, `lastModifiedDate`, `listName`, `listId`, `isCompleted`, etc. (Use `--detail full` separately if you want to see every field name; JMESPath always sees the full set.)

### Filter projection: `[?expr]`

The most common pattern. Returns elements matching `expr`.

```bash
reminders query "[?priority == 'high']"
reminders query "[?isCompleted]"
reminders query "[?listName == 'Work']"
```

### Comparisons

`==`, `!=`, `<`, `<=`, `>`, `>=`. The Swift JMESPath we use supports lexical comparison of strings, which makes ISO 8601 date comparison "just work":

```bash
reminders query "[?createdDate >= '2026-04-30']"
reminders query "[?dueDate < '2026-06-01']"
```

### Logical operators

`&&` (AND), `||` (OR), `!` (NOT). Parenthesise for precedence.

```bash
reminders query "[?priority == 'high' || priority == 'medium']"
reminders query "[?listName == 'Work' && !isCompleted]"
reminders query "[?(priority != 'none') && createdDate >= '2026-04-30']"
```

### Field projection

Extract just one field, or build a custom shape:

```bash
reminders query "[].title"                                      # array of titles
reminders query "[].{name: title, due: dueDate}"                # array of {name, due}
reminders query "[?priority == 'high'].{title: title, due: dueDate}"
```

### Sort and reverse

```bash
reminders query "sort_by(@, &dueDate)"                          # ascending
reminders query "reverse(sort_by(@, &createdDate))"             # newest first
reminders query "sort_by([?dueDate != null], &dueDate)"         # filter then sort
```

`@` means "the current value" — i.e. the whole input array. The `&` syntax creates a JMESPath expression reference that `sort_by` calls per-element.

### Pipe and slicing

```bash
reminders query "sort_by([?dueDate != null], &dueDate) | [:10]"  # 10 earliest
reminders query "[?priority == 'high'] | length(@)"              # count high-priority
```

### Useful built-in functions

| Function              | Example                          | Effect                           |
| --------------------- | -------------------------------- | -------------------------------- |
| `contains(s, sub)`    | `[?contains(title, 'meeting')]`  | substring match (case-sensitive) |
| `starts_with(s, p)`   | `[?starts_with(title, 'TODO ')]` | prefix match                     |
| `ends_with(s, p)`     | `[?ends_with(title, '?')]`       | suffix match                     |
| `length(x)`           | `length([?priority == 'high'])`  | count of array items             |
| `sort_by(arr, &k)`    | `sort_by(@, &dueDate)`           | sort by computed key             |
| `not_null(a, b, ...)` | `not_null(notes, '')`            | first non-null arg               |

Full list at <https://jmespath.org/specification.html#built-in-functions>.

### Project-specific extensions

The standard `contains()` is case-sensitive. To match case-insensitively, lower (or upper) both sides first using project extensions:

```bash
reminders query "[?contains(lower(title), 'meeting')]"
reminders query "[?contains(upper(notes), 'TODO')]"
```

These extensions mirror the AWS CLI's `lower()` extension; both are non-standard and not in the JMESPath spec.

---

## 5. Recipes

Today's date in these examples: 2026-05-07. 7 days ago = 2026-04-30; 14 days ago = 2026-04-23.

### 5.1 All reminders in Task Journal created in last 7 days OR with any priority

```bash
reminders query --list "Task Journal" --status all --pretty \
  "[?createdDate >= '2026-04-30' || priority != 'none']"
```

Or with the per-field flag pulling more weight:

```bash
reminders query --list "Task Journal" --created-from 2026-04-30 --status all --pretty \
  "[?priority != 'none' || createdDate >= '2026-04-30']"
```

### 5.2 All reminders in Task Journal created more than 14 days ago

```bash
reminders query --list "Task Journal" --created-to 2026-04-23 --status all --pretty
```

### 5.3 All high-priority incomplete reminders across all lists

```bash
reminders query --all-lists "[?priority == 'high']" --pretty
```

### 5.4 Reminders due in the next 7 days, sorted by due date

```bash
reminders query --all-lists --due-from 2026-05-07 --due-to 2026-05-14 --sort dueDate --pretty
```

If you also need to project shape:

```bash
reminders query --all-lists --due-from 2026-05-07 --due-to 2026-05-14 --pretty \
  "sort_by(@, &dueDate)"
```

### 5.5 Reminders with "meeting" in title (case-insensitive), due in next 14 days

```bash
reminders query --all-lists --due-to 2026-05-21 --pretty \
  "[?contains(lower(title), 'meeting')]"
```

### 5.6 Count of incomplete reminders in Work list

```bash
reminders query --list "Work" --pretty "length(@)"
```

(Alternatively, the regular response's `totalCount` field has this without JMESPath.)

### 5.7 10 oldest reminders in Personal list (by creation)

```bash
reminders query --list "Personal" --status all --sort oldest --per-page 10 --pretty
```

Or via JMESPath if you want a custom shape:

```bash
reminders query --list "Personal" --status all --pretty \
  "sort_by(@, &createdDate)[:10]"
```

### 5.8 Recently completed reminders across all lists (last 7 days)

```bash
reminders query --all-lists --status completed --pretty \
  "sort_by([?completionDate >= '2026-04-30'], &completionDate)"
```

`compact` (the default detail) doesn't include `completionDate` for `--status completed`. JMESPath always sees the full record so this works without `--detail full`.

### 5.9 Reminders with no due date set

```bash
reminders query --all-lists --pretty "[?dueDate == null]"
```

(The `--due-from`/`--due-to` flags exclude reminders with no due date by design — for "no due date" the JMESPath is the right tool.)

### 5.10 Reminders modified today

```bash
reminders query --all-lists --modified-from 2026-05-07 --status all --pretty
```

### 5.11 Title-only output for a quick scan

```bash
reminders query --list "Work" --pretty "[].title"
```

### 5.12 Multi-field projection

```bash
reminders query --all-lists --pretty \
  "[?priority == 'high'].{title: title, due: dueDate, list: listName}"
```

---

## 6. JMESPath vs jq

`reminders query` outputs JSON to stdout, so you can always pipe to `jq` for further work. Rules of thumb:

- Use **JMESPath** when you want filtering and projection done **server-side** so less data crosses the boundary. This is where the LLM context-window savings come from.
- Use **jq** for transformation that JMESPath can't express (regex, advanced aggregation, custom string surgery), or when you've already got the data and want to reshape it.

Quick comparison for a common case:

```bash
# JMESPath (server-side):
reminders query "[?priority == 'high'].title"

# jq equivalent (after a normal query):
reminders query | jq -r '.reminders[] | select(.priority == "high") | .title'
```

JMESPath wins when the result set is large and you only need a slice. jq wins when you need its broader feature set.

---

## 7. Field reference

The fields available in JMESPath expressions and on full output:

| Field                 | Type     | Notes                                   |
| --------------------- | -------- | --------------------------------------- |
| `id`                  | string   | Unique reminder ID                      |
| `title`               | string   |                                         |
| `notes`               | string?  | May be null                             |
| `listId`              | string   |                                         |
| `listName`            | string   |                                         |
| `isCompleted`         | boolean  |                                         |
| `priority`            | string   | `'none'`, `'low'`, `'medium'`, `'high'` |
| `dueDate`             | string?  | ISO 8601                                |
| `dueDateIncludesTime` | boolean? |                                         |
| `completionDate`      | string?  | ISO 8601                                |
| `createdDate`         | string   | ISO 8601                                |
| `lastModifiedDate`    | string   | ISO 8601                                |
| `url`                 | string?  |                                         |
| `alarms`              | array?   | See `--detail full` output for shape    |
| `recurrenceRules`     | array?   | See `--detail full` output for shape    |

`priority` sorts lexically as `high < low < medium < none`. To order by importance use explicit equality checks rather than `sort_by(@, &priority)`.

---

## 8. Sources & further reading

- JMESPath specification: <https://jmespath.org/specification.html>
- JMESPath tutorial: <https://jmespath.org/tutorial.html>
- jq manual (for the pipe-to-jq pattern): <https://jqlang.github.io/jq/manual/>
- AWS CLI's `lower()` extension (the precedent for our `lower`/`upper`): <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-output-filter-clientside.html>
