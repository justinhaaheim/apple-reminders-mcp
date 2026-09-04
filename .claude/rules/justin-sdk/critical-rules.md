<!-- justin-sdk rules · commit 44c79b132676 · content 141785f0b240 · generated 2026-09-04 · GENERATED FILE — do not edit; run: bunx @justinhaaheim/justin-sdk rules-update -->

# Critical Rules

# 1. Communication

Before yielding back after work has been completed:

- ALWAYS explicitly describe what specific testing steps should be taken to test the changes that were just made, when appropriate.
- ALWAYS provide a short description of what to suggest working on next.

**Flag contradictory, duplicated, or stale content in CLAUDE.md and other memory/rules files as soon as you notice it.** I cannot see it, and it may be steering you toward behavior I don't want. File a bead and offer to fix it: "I noticed X and Y contradict each other in CLAUDE.md — filed `<id>`. Want me to handle it now?" The `memory-cleanup` skill covers what belongs where.

# 2. Development Best Practices

- **When making decisions and evaluating options, rely on credible research, experiments and data whenever possible.** Challenge claims (including claims in your own reasoning) if they are vague, overconfident or unsupported.
  - **Never present conjecture as fact.** Always explicitly name speculation and uncertainty as such. This is an essential part of rigorous reasoning.
- **Prefer using existing libraries over writing hand-rolled code.** A mature library typically brings better edge-case handling, standards compliance, API design, and bug finding/fixing. It keeps our local code simpler/smaller. Vet the libraries first, though: look at project age, recent maintenance cadence, and adoption/GitHub stars — and when in doubt, dispatch a subagent to clone and inspect the code.
- **Run shell commands one at a time.** One logical action per invocation; read its output before deciding the next command. Do NOT chain multiple state-changing steps into a single compound command: if any step fails mid-chain the failure is buried, the partial state is hard to see, and recovery is a mess. Sequential commands cost nothing and make every result inspectable. Shell plumbing within one action is fine (pipes, a guard like `test -f x && …`) — the smell is stacking independent actions, especially writes, behind a single Enter.
- **Use a `./tmp/` folder** for genuinely disposable files — scratch data, backups, throwaway output — and keep `tmp/` in `.gitignore` so the working tree stays clean.
- **Never leave CODE in `tmp/`.** Anything with reuse value goes in the repo proper, from the first version. `tmp/` is excluded from TypeScript, ESLint and Prettier, so code there is silently unchecked, and the directory is liable to be cleared at any moment. Commit it and prune later if it turns out not to matter — that is far cheaper than losing it or shipping something nothing ever type-checked.
- **Create, enter, and exit git worktrees with the Claude Code worktree tools, not raw `git worktree` commands.** Removing a worktree by hand leaves its Claude transcript stranded in an orphaned project directory, where `--resume` will not find it; the tools move it back. Raw removal also destroys any unpushed commits and submodule state living in that worktree.
- **Codify reusable commands as `package.json` scripts.** Anything worth running more than once — even a memorable one-off — becomes a named script rather than living only in chat or shell history. Predictable aliases (`prettier:write`, `fix`, etc.) document the command explicitly for humans and agents, remove the recall cost of bespoke per-tool syntax, and are discoverable via shell completion (an ADHD-ergonomics win). Whenever you hand over a command to run, lean toward adding it as a script first, then saying to run `bun run <name>`. Even non-JS projects should keep a `package.json` for these aliases. Prefix disposable one-offs with `tmp:` (e.g. `tmp:fetch-otter-april`) so they're visibly throwaway and easy to garbage-collect, while still committed to git as a record of the exact invocation.
- **Write scripts in TypeScript rather than shell script**, run them with `bun`, and put them in a `/scripts/` folder. TypeScript is more readable and adds static typing, so prefer it unless a shell script has clear advantages.
- **NEVER use "barrel files" or the "directory index pattern".** Barrel files are `index.{js|ts|jsx|tsx}` files that only re-export other modules; the directory index pattern is creating a directory with an index file where a single module file would suffice (use `module.ts`, not `module/index.ts`). ALWAYS import modules directly from their specific file. Exception: only use index files where the framework requires them (e.g. Expo Router pages).

# 3. Use beads for planning and tracking

I use [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`) as the single source of truth for plans, tasks, and progress. **Do NOT write planning documents in `docs/plans/` or anywhere else, and do NOT use markdown TODO lists.** Beads replaced both an old `ROADMAP.md` north-star doc and the `docs/plans/` scratchpad pattern — don't reintroduce either. If you find yourself wanting to write a planning markdown file, write a bead instead.

**Use beads for ALL work.** Every task — even trivial ones — gets a bead.

## 3.1 Why this matters

Context evaporates between sessions: chat history is gone, file diffs are lossy, and memory is fragile. Beads are the durable, externalized memory that survives — the accountability, trackability, and audit trail that outlast the conversation — so use them **rigorously**. Capture in the bead's own body fields (see **Keep the bead current** below):

- **Decisions** made, and the reasoning behind them.
- **Anti-decisions** — approaches considered and deliberately rejected, and why.
- **Things already tried** that didn't work — what you tried, what happened, and what it rules out. This is one of the most valuable things to record: it stops a future session from re-reproducing a dead end.
- **Important context** about the task — constraints, gotchas, the live edge of an investigation.
- **Verbatim instructions from the human** — captured as given, so intent isn't lost in paraphrase.

**Before yielding back to the human, proactively capture all project and task status in beads** — always, without waiting to be asked and without deferring it. Every yield is a handoff moment: it is never certain the conversation will continue, so treat each one as if the next session will start cold. This is the carpe diem rule — seize the moment while the context is fresh in your head: record the project status, the decisions, the learnings, the surprises and the troubleshooting dead-ends, and create beads for the follow-ups you noticed, all before the end of the turn. Leave the project in a state where "what to work on next" is answerable from the beads alone, without reading code.

**Acceptance criteria are essential — use them almost always.** Roughly half the value of a bead is its acceptance criteria: they define, concretely, what "fully complete" means in the way the human intended. Without them it is far too easy to do work that merely _sounds like_ the bead's title, declare it done, and close it — while missing what the human actually asked for. Write them when you create the bead, and treat them as the definition of done.

## 3.2 Keep the bead current — the body is the only source of truth

A bead's **title and body fields** (`description`, `design`, `acceptance_criteria`, `notes`) are the source of truth for the spec and for the state of the work. Everything listed above goes there, and nowhere else.

- **They must always be accurate.** A bead is not a log of what was once believed — it describes the problem, the plan, and the status **as currently understood**. Keeping them current is critically important: a body that has gone stale actively misleads the next session, which is worse than no bead at all. Keep the title and body in sync with each other, too; a title that no longer matches the body is itself a bug.
- **Rewrite freely — removing is not destroying.** Do NOT hesitate to change or delete anything inside a bead. Beads are tracked in git, so every prior version stays recoverable: **git history is the changelog; the body is the present tense.** Preserving a predecessor's superseded text out of deference is the failure mode here, not the careful choice.
- **Prune aggressively.** More information is not better when it is stale, superseded, confusing, misleading, or irrelevant — cut it. The goal is that the bead is an accurate representation, at all times, of the work to be done given the current understanding of the project.
- **Anything changes → update the title and the body, now.** A decision reversed, a spec revised, a question answered, a hypothesis ruled out: rewrite the affected fields in place so they read correctly to someone who has never seen an earlier version. Recording an abandoned approach as an anti-decision is valuable — write it as current knowledge ("X was tried and rejected because Y"), not as an append-only trail under text that still describes X as the plan.
- **Do NOT use comments.** Never `br comments add` (decided by Justin, 2026-09-04). Comments are not surfaced by `br show` or `br list`, so anything filed there is invisible in practice — and treating them as an equally good home for updates is precisely what let spec reversals accumulate as comments while bead bodies went on describing designs that had already been abandoned. Everything that matters goes in the body; what does not matter goes nowhere. The two cases that feel like they need a comment are already covered: `br close --reason "…"` writes the `close_reason` field, and a reason for reopening goes in `notes`.

## 3.3 When you start work

Before doing anything, decide which case you're in:

1. **Trivial task** (single file edit, simple fix) — create one bead, do the work, close it.

   ```bash
   br create "Short imperative title" -t task -p 2
   br close <id> --reason "..."
   ```

2. **Non-trivial task** (multiple files, real design decisions, multi-session work) — create an **epic**, plan it in the epic's `description` (vision/context), `design` (technical approach), `acceptance_criteria` (what "done" means) and `notes` (open questions, references) fields — via `br update` or passed on create — then break it into **child beads**.

   ```bash
   br create "Short epic title" -t epic -p 2                # → e.g. voice-recorder-10c
   br create "Phase 1 thing" --parent voice-recorder-10c    # → voice-recorder-10c.1
   br create "Phase 2 thing" --parent voice-recorder-10c    # → voice-recorder-10c.2
   ```

   `--parent` does two things at once: it creates the sub-bead AND establishes the `parent-child` relationship correctly. Use it instead of `br dep add` for epic / sub-bead relationships.

3. **Already-planned work** — pick up the highest-priority unblocked bead.

   ```bash
   br ready                              # what's actionable right now
   br epic status                        # how active epics are progressing
   br show <id>                          # full context for one bead
   br update <id> --status=in_progress   # claim it
   ```

## 3.4 During work

- Update bead status as you go: `in_progress` when claimed, `closed` with a `--reason` when done.
- **Carefully review the acceptance criteria before closing a bead** — confirm the work genuinely meets every criterion, not just the bead's title.
- Discover a follow-up task? Create it: `br create "..." -t task -p N` (add `--parent EPIC` if it belongs to one).
- Surprises, decisions, dead-ends worth remembering — write them into the bead's `notes` field (`br update <id> --notes '...'`), rewriting the field so it reads as the current state of the work rather than a transcript of how you got there. `--notes` REPLACES what's there, which is the point: read the existing note, fold in what's new, cut what's now stale. The bead is the durable memory; chat history is not.

## 3.5 When you finish (or hit a stopping point)

- The `.beads/` directory IS the source of truth, and most projects **auto-flush** it to `.beads/issues.jsonl`. **But you must remember to COMMIT that file** — it happens often that beads get changed and then left uncommitted. Stage and commit it alongside your code changes so beads state travels with the branch.
- If the work is a multi-bead epic and you're handing off mid-stream, give a **short handoff message** for the next agent: the epic id, the branch, what's done, and what's next (which bead to claim). The message is a pointer, not the record — the detail must already be in the bead bodies, since the message is gone the moment the session is.

## 3.6 Notes

- If beads doesn't appear to be set up in a project, do NOT run `br init` yourself — flag it to the human instead ("my guidance says to use beads, but it doesn't look set up here yet").
- Beads are local to a branch / worktree. To see beads created in a worktree you must `cd` into that worktree first — if you've been told to work on a bead in a particular worktree, check out that worktree before running any `br` commands.
- Bead types: `task`, `bug`, `feature`, `epic`, `chore`, `docs`, `question`. Priorities are 0–4 (P0 = critical, P4 = backlog).
- Dependency directions matter. The short version: use `--parent EPIC_ID` for epic / sub-bead; use `br dep add <waiter> <waited-on>` (default `--type blocks`) for true sequencing.

# 4. Stay focused

- Focus on addressing the given task in the smartest, most direct way possible.
- Follow the instructions you were given by the human precisely.
- Always prioritize getting the change _working_ over fixing lint/typescript issues that arise. Return to fix the lint/ts issues at the end.
- Do not change anything that is not directly related to the task at hand. Do not alter/remove comments or code unless it is required for the task, or explicitly instructed.

# 5. Use good style

- **NEVER disable a lint rule unless explicitly authorized to do so.**
  - The lint rules for a project were carefully chosen for a reason. These rules help prevent anti-patterns, mistakes, and hard-to-debug code.
  - Focus on getting the change WORKING first, but always come back and address lint/ts issues.
  - Always attempt to _improve the code_ in order to address the warnings/errors.
  - If stuck addressing a lint/ts issue, move onto the next one, but ALWAYS explicitly flag the issue rather than silently skipping it.

- Use `null` when a particular property is absent — e.g. a `uri` that is not known now but will be known later is `null`, never an empty string. This improves clarity and reduces bugs, and may require updating the TypeScript type definition and accommodating the new null possibility elsewhere in the code.

- When creating a new file/component, check the codebase for code that already exists to fulfill that purpose.

- Use functional, declarative programming. Never create JavaScript classes unless specifically requested. Prefer the module pattern over classes.

- Use the function declaration syntax for functions/components at the top level of a file. Otherwise use whatever is most idiomatic.

# 6. Failure is not empty: never conflate "it failed" with "there is none"

**A failed measurement must never be representable as a normal value.** "The tool errored", "there is no value", "the value is zero", and "the list is empty" are four different facts. Any code that maps one onto another — `return 0` on a failed subprocess, `return []` on a thrown enumeration, `catch { return null }` where null also means "genuinely absent" — is manufacturing false evidence, and the damage lands downstream where nobody can see the substitution happened.

This is a hard invariant for all code, not a style preference. It ranks with "never disable a lint rule."

## 6.1 Why this is cardinal

- **The failure mode is silence-shaped.** Fabricated neutral values produce _calm_ output: zero differences, empty lists, "nothing to do". Nothing red ever happens, so no one looks. The bug is invisible at the layer that created it and undiagnosable at the layer it detonates.
- **Downstream consequences are unbounded** — you do not know what will be decided from your return value. Real case (repo-status, 2026-08): `if (out == null) return {ahead: 0, behind: 0}` on a failed `git rev-list` read as "0 commits ahead" → "fully merged, proven safe" → eligible for automated **remote branch deletion**; one conflated null, six sibling bugs of the same shape, worst reachable consequence irreversible data loss reported as success.
- **The reassuring direction is the dangerous one.** A failure that degrades to "more work to do" wastes time; one that degrades to "all clear" destroys things. Audit every fallback by asking: does this substitution move the verdict TOWARD "safe/done/clean"? If yes, it is a bug right now.

## 6.2 What to do instead

- **Make the type carry the distinction.** `number | null`, `T[] | null`, a `Result`/outcome union — whatever fits, but the failed state must be a _distinct type member_ the compiler forces every consumer to handle. Never a sentinel that is also a legal value (`0`, `''`, `[]`, `-1`).
- **One nullable field, not many.** Group values that come from a single measurement so "half known" is unrepresentable (`{ahead, behind} | null`, not two nullable numbers).
- **Route missing evidence to the cautious verdict, loudly.** Unknown is never "merged/clean/safe/empty" — it is "review/unknown/failed", surfaced with the failed command named, and checked _before_ any reassuring rule can run.
- **Silence must be a claim.** An empty list in output must mean "checked, and there are none" — never "couldn't check." If a check can be skipped or can fail, the output must distinguish checked-and-clean from not-checked.
- **`.trim()`, `Number('')`, and parsers count too.** `Number('')` is `0`; a trimmed filename is a different filename; a desynced parser yields garbage that "resolves nowhere" — the same conflation arriving through the parse layer instead of the error path.

"Use `null` when a property is absent (never `''`)" is the modeling half of this principle; this rule is the enforcement half — the null must be _load-bearing_: produced on failure, typed distinctly, impossible to mistake for a measured zero.

# 7. Do these first

- **CHECK the code before you build** - Before building something new, check the codebase for existing functionality. Make smart choices whether to augment/refactor/replace what exists, or to build something additional. It's ok to duplicate/rebuild things, but only do so intentionally and explicitly.
- **Locate/setup VERIFICATION tooling before you build** - Agents benefit immensely from having a way to inspect and verify what they're building (web UI, iOS app, shell output, etc). If you have one, use it. If you don't, suggest this to the human. Currently preferred tools are playwright (browser), detox (react native e2e tests), ios-simulator mcp (driving the sim directly), and bun tests (incl snapshot tests).
- **LOOK before you build** - inspect what you are building/using/doing before/during/after. DON'T BUILD BLIND. Look at the sim/page snapshot/screenshot.

# 8. Check signals

Always check work with the project's `signal` script when you're done making changes. It is usually also wired to run automatically — in a pre-commit hook, or in a PostToolUse hook (in which case there's no need to run it again by hand).

- `bun run signal` - Check for typescript, lint and formatting issues all at once

Most projects also expose these directly:

- `bun run ts-check` - Check for typescript errors
- `bun run lint` - Check for lint issues
- `bun run prettier:check` - Check for formatting issues

# 9. Screenshot tests

UI screenshots are stored **as screenshot tests** — never as loose files or historical galleries.

- Each UI test that captures a screenshot **asserts** it against a baseline image **committed to the repo** (`jest-image-snapshot` over Detox screenshots in RN, or the platform's equivalent pixel-diff tool). That committed baseline is the one canonical "this is what the UI looks like" record per test.
- **A UI change must fail the screenshot test.** Updating a baseline requires an explicit update flag/script (e.g. `bun run test:e2e:update-screenshots`) — running it is the signal that you KNOW the UI changed and have **reviewed the new screenshot**. Never let a test run silently rewrite baselines, and never pass the update flag to turn a red gate green without looking at the images.
- **No historical screenshot folders.** Baselines are overwritten in place — git history preserves every prior stage, and the baseline-update commit is itself the reviewable record of the change.
- Keep captures deterministic so the diff means something: pinned device/simulator, frozen status bar (time/battery), capture only after the asserted state has settled, and the smallest diff tolerance that runs reliably.

When building UI in a project that has no screenshot tests yet, suggest setting them up — they're cheap once the e2e harness exists, and they turn every future UI change into a reviewable image diff.

# 10. Commit regularly

- Commit changes regularly using `git add ...` and `git commit ...` (run them as separate commands, not chained).
- Wrap the commit message in **single quotes**, as in `git commit -m '<message>'` — not double quotes, which let the shell interpolate backticks and `$` in the message.
- Follow the Conventional Commits specification when writing commit messages.
- ALWAYS commit changes proactively, at regular intervals, as soon as a unit of work is done.
- NEVER leave uncommitted changes in the working directory. It is better to commit now and fix any issues in follow-up commits than to leave uncommitted changes in the working directory.

# 11. Justin SDK

**justin-sdk** (`@justinhaaheim/justin-sdk`) provides useful tools in a consistent way across many different projects. Its whole purpose is to avoid rolling my own near-duplicate scripts in virtually every project — and then having to keep all those copies in sync.

## 11.1 Prefer uniformity across projects over matching local code

For tooling that exists (or should exist) in more than one of my projects — build/ship scripts, config, shared helpers — **strive for uniform, ideally identical, patterns across similar projects**. Do NOT default to "match the surrounding code" of whichever project you happen to be in.

"Match the surrounding code" is a _within-a-project_ tiebreaker for idiom and naming. It is NOT a reason to let the same tool diverge into a different local dialect from one project to the next. If a shared script doesn't lint/typecheck/build in some project, the right fix is to make that project support the shared version (e.g. add the types it needs to its tsconfig), NOT to fork the script.

## 11.2 Consolidate shared functionality into justin-sdk

When there's an opportunity to consolidate similar functionality used across projects _into_ justin-sdk, that is usually the right choice: reusing one implementation from the SDK is **strictly better** than copy-pasting it into N projects and keeping the copies in sync. Some things genuinely may not work (or not work as well) inside the justin-sdk package itself — keep those per-project, but still uniform across projects. Most of the time that isn't the case, so put it in justin-sdk and reuse it.

# 12. Advisor tool

The `advisor` tool is a stronger reviewer model that gives feedback on designs, implementations, and problems you're stuck on. It sees the whole conversation history automatically.

When to use the advisor:

- After scoping/designing a significant feature/workstream, ask the advisor to review your spec/approach before implementing -- to identify and challenge your assumptions, and to provide constructive feedback.
- If you are stuck debugging something ask the advisor for help before spending too much time spinning your wheels.
- If you are considering pivoting to a different approach, but are uncertain about which approach to take or whether to pivot in the first place, ask the advisor to think it through with you.

When to NOT use the advisor:

- When you are making small or simple changes.
- When the task is already clearly scoped.
- When the task has little ambiguity.
- When the approach follows well-established patterns.
- When the changes are easily reversible, straightforward, and entail little-to-no risk.

Important: **Advisor feedback must NEVER cause you to deviate from the instructions or specifications the human gave you** — follow those precisely. The advisor exists to help you achieve the spec, not to alter it. If it flags a problem or offers an alternate approach that would mean deviating, you MUST get explicit approval from the human before making any deviation.

## 12.1 If the advisor tool is unavailable

Fall back to spawning a subagent as the advisor, and treat it the same way.

1. **Package the context.** A subagent does NOT inherit the conversation transcript, so you must provide it everything it needs: the task/goal/bead id, what's been done so far (key tool calls + results), decisions/dead-ends/trade-offs, your current reasoning/plan, the relevant files or diffs, and the specific question to review. Frame it as "review my work/plan as a skeptical senior reviewer and push back."
2. **Instruct the subagent to not spawn its own subagents or advisors.** Use this language verbatim: "Do NOT spawn any subagents and do NOT use any advisor tool — answer directly in this single session and return your review as your final message."
3. **Use a model one tier ABOVE the current main model**, passed via the Agent tool's `model` param. Ascending ladder: **`haiku` → `sonnet` → `opus` → `fable`**. If already on `fable` (the top tier), use `fable` again — a fresh, differently-anchored reviewer still adds value.

# 13. NEVER manually wrap text

**Do not insert your own newlines to wrap a text at some column width.** Let the thing that displays the text do the wrapping.

This is not "avoid all newlines." Structural line breaks are correct and expected. The rule is narrow and specific: **never break a line purely because it got long.**

This applies to **everything you write**, not just code. Only manually wrap lines when it is explicitly called for.
