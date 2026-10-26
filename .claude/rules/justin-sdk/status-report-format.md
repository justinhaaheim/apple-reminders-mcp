# Status report format

Applies to **the report**: the final message before you yield to Justin on a turn where you did work. Not to in-flight prose. A turn where you only answered a question (no request filed, no file changed) needs nothing but the answer.

Rewritten 2026-10-11 for status report v4. Why it has this shape, in Justin's words:

- "I want it to be NOT burdensome for claude. I want it to not get in the way of claude simply answering something. I STILL want to strongly tell claude to write its responss in a scannable way. But I want to let it write its own response to me, and have the status report auto-generate as much as possible from beads/the repo/etc." (2026-10-10)
- "I need a simple dashboard, organized principally around my requests to claude, that shows me in a simple, clear way what the status is of those requests, and what should happen next." It must make sense "even if I totally forget the request I made in the first place." (2026-10-11)

## The report has two parts

1. **Part 1 is generated.** Before you yield, run `bun run justin-sdk thread status` again: the same command that decided the branch at the start of the turn (below), not a second decision. Paste the block it prints, from the 🛑 line through the `────` line, verbatim at the top of your final message. Never type or edit any of it: the tool builds it from beads, git, the message log and the transcript. Keep its empty lines exactly as printed; it puts two between list items on purpose (see the writing rules below).
2. **Part 2 is your own message**, below that line. When the prime directive requires its `Prime directive check:` paragraph in this reply, that paragraph comes first in Part 2, above the headings (prime-directive.md). Write it under the Know-your-reader rule: bullets, short, for a reader who does not remember this session. Use these headings, in this order. Deviations appears on every work turn; the others appear only when they have content.
   - **Answers** — restate each question he asked, then answer it.
   - **Things you should know** — what he needs in order to decide or act, and nothing more.
   - **Deviations** — anything that departs from what he asked for or from the spec. "none" is a claim that you checked.
   - **What I learned** — each item ends with where you wrote it down, or the bead that tracks it.

No JSON, no form, no progress percent. Do not repeat what Part 1 already shows: the requests, the questions, the repo facts.

**Decide the branch once, at the start of a work turn.** Run `bun run justin-sdk thread status`. Where that says `Script not found`, the repo is not enrolled in justin-sdk: run `justin-sdk-latest thread status`. If its first line is `SESSION BEADS: ENABLED`, follow the checklist below. If it prints anything else (`SESSION BEADS: DISABLED`, a help screen, an unknown-command or not-found error), this repo is legacy: skip the checklist, put your asks in the report, and use the Legacy section at the end of this file. If it fails in any other way (for example, it finds no session bead for this session), use the Legacy section too, and quote its error in your report.

## Every turn: the whole checklist

1. **He asks for work.** Run `bun run justin-sdk thread request "<plain-words title>"` at the start, once per request. Name it by the outcome he wants, not by your activity: "Think through how hooks are managed" is the request "Change how justin-sdk hooks are installed", and the thinking is its first stage. Add `--done-when "<criteria>"` when done is not obvious. When the work is an existing bead, run `bun run justin-sdk thread request --bead <id>` instead. What counts as a request, and how to find them in his words: requests.md.
2. **You need something from him.** Run `bun run justin-sdk thread ask` at that moment, not at the end (see Asking, below). It does not block the turn: file it and keep working. Never ask only in your message; Part 1 lists only the questions you filed.
3. **A request reaches a stage.** Run `bun run justin-sdk thread stage <request id> <stage>…` for each stage it really reached (default ladder: `code-done`, `tested`, `built`, `link-sent`, `approved`). When a request is finished, close its bead: `br close <id> --reason "…"`. A request tracks something he wants to exist:
   - A **change** (build, fix, reconfigure, clean up, decide and then do) is finished only when the change exists, or he says he no longer wants it.
   - A **question** ("why did X fail?", "what is Y?") is finished when the answer is in your message.
   - **Work that your answer or proposal leads to** is an open request in the same turn until he has it built or declines it. Keep the original request open, or file a new one, and put his decision on it as an ask (`thread ask --to <request id>`); a P1 to P3 ask's default names what you will build.
   - **Work handed to another session** is that session's open request. Close yours with `--reason "carried by session <id>"`.

   A request stays open because its work does not exist yet, never because your question to him is unanswered: anything below P0 is optional by design and may never be answered. (2026-10-12: the first real v4 session yielded three times with answered requests still open, because its questions were filed as their child beads and br refused to close them. 2026-10-17: two sessions closed a "think through" and a "propose" request once they had answered, so his inbox read "all done" while the change he wanted was unbuilt.)

4. **Before you yield on a work turn.** Run `bun run justin-sdk thread status` and act on what it prints:
   - **What to mark** lists only what the tool cannot work out itself, each with the command that fixes it. Run that command, or skip an item that does not apply.
   - **If you stop now the inbox will say:** is the status Justin will see. "Open work, no blocker" tells him to resume this session and say continue. Before you stop on it, settle each open request: close it if its work is done; keep working if you can, acting on the default of any P1 to P3 question he has not answered; or, if it cannot move without his answer, file that question as a P0. A turn where he asked you a question is no exception: put the answer in your final message and keep working on the default until something blocks. In his words (2026-10-24): "You shouldn't yield back to me if there are not blockers." `thread handoff` is not a way to stop: use it only when this session cannot go on (its context is nearly full, or he asked for a new session).
5. **He says his answers are in**, or the `[thread]` line in your context counts new answers. Run `bun run justin-sdk thread answers` at the start of the turn and continue from them. If he answers a question in chat instead, record it: `bun run justin-sdk thread answer --ask <question id> "<his answer, verbatim>"`.

`thread done`, `thread archive` and `thread note` are Justin's marks. Do not run them unless he asks. `/thread-done` and `/thread-archive` are him asking.

Subagents (players, explorers, any agent dispatched by another session) never run `thread` commands: they inherit the parent's session id and would write into its session. They report to the session that dispatched them; that session reports for the arc.

## Asking

```
bun run justin-sdk thread ask "<one-line question>" --priority <0-4> [--header "<≤12 chars>"] [--context "<text>"]… [--option "Label: why"]… [--recommend <a|b|…>] [--default "<what you do if he never answers>"] [--to <request or bead id>] [--approve | --do]
```

- Give two or more options, or none. Name the one you recommend with `--recommend`.
- `--approve` makes it a yes/no. `--do` marks something he has to do himself, such as testing on a device.
- A P0 takes no `--default`. P1–P3 require one. A P4 needs none.
- An incomplete ask is refused with exit 2 and a one-line reason. Fix it and run it again.

## Ask priority — P0 to P4

Replaces the old blocking / non-blocking boolean (2026-09-14). The scale exists so Justin can answer the two that matter and skip the rest; a report where everything is P0 has no priorities at all and is just the boolean with more digits.

|        | Means                                       | Marker  |
| ------ | ------------------------------------------- | ------- |
| **P0** | I cannot proceed without this               | `🛑 P0` |
| **P1** | Decide before the next session builds on it | `🟡 P1` |
| **P2** | Decide this week                            | `🟡 P2` |
| **P3** | Informational — my default is fine          | `⚪ P3` |
| **P4** | FYI — no reply expected                     | `⚪ P4` |

- **Most asks are P3 or P4.** Do not inflate.
- **P0 is for a session that is genuinely STOPPED.** If you kept working, it was not P0. Only a P0 blocks; the others never change the session's status.
- **Every P1–P3 ask states its default**: what you will do if he never answers. Leaving a P3 unanswered IS the answer. A P0 has no default, because you stop; a P4 is FYI.

## Writing rules — Part 2 and the legacy report

- **Parallel structure.** Sibling bullets share the same grammatical shape. Big emphasis on this.
- **Two empty lines between list items.** Claude Code's terminal drops a single empty line between two list items, so they stack directly on top of each other; two empty lines show as one empty row and keep the numbering (measured 2026-10-15 on Claude Code 2.1.300; evidence in home-base `docs/reference/claude-code-markdown-rendering.md`). Use two between sibling bullets, numbered items, and the bullets or options inside one item. One empty line already shows between paragraphs, headings and quotes. Never space with `<br>`, a line holding only `.`, an HTML comment, a trailing backslash or an invisible character: each is drawn as junk, dropped, or not reliably sent. Justin, 2026-10-15: "I keep asking, OVER AND OVER AGAIN, for much more vertical separation to make the content more readable."
- **Simple declarative sentences** about what you did, found, or need. No poetry, no metaphor, no "worth your eyes", no "trap".
- **Bring solutions, not problems.** Before listing anything: can you just fix it? If it is uncontroversial and in line with the rules, do it and report it as done. Only surface design decisions, deviations from his spec, and things genuinely his.
- **Do not surface beads housekeeping.** Beads are your ledger, not his. He does not need to approve closing a bead or hear where information lives.
- **Draft, then revise.** Write the full message first, then proofread it against this file and Know-your-reader. Cut anything that fails "does he need this?" Ask "can I dispatch this now instead of reporting it?" and "did he already say I don't need to ask this?"
- **No TLDR.** Retired 2026-09-04.
- Number dispatches (dispatch 1, 2, 3), never letter them.

## Legacy repos: `SESSION BEADS: DISABLED`

Kept from 2026-10-11 until every enrolled repo prints `SESSION BEADS: ENABLED`; then delete this section. In a legacy repo a question-only turn now records nothing, so the old board shows "no report yet" for it. That is accepted during the transition.

First run `bun run justin-sdk thread prepare`. If it prints `THREADS: ENABLED`, record the report the old way: write the payload JSON it describes to the drafts path it names, run `bun run justin-sdk thread report --full --file <that path>`, and paste what it prints verbatim as your final message. If it prints anything else or is not found, write the report by hand in the template below.

At the start of a turn after Justin says his answers are in, run `bun run justin-sdk thread inbox` and continue from the answers; if he answers in chat instead, disposition those asks in your next report.

Write the whole report by hand as your final message, in the template below. The template shows the structure, not the spacing: put two empty lines between asks and between options (see the writing rules above).

- **The glance block comes first**, right after the 🛑 line: four labelled lines for status, next step (one word from the table below), progress, and open P0 asks.
- **Restate what you were asked** in one sentence: "You asked me to …".
- **Every bead id gets a descriptive phrase**: `jofp.6 (the thread-state fact collector)`. Never a bare id.
- **Asks are ONE numbered sequence across every priority**, P0 first, so he can reply "1 yes, 2 b". Letters are for options only. Each ask carries its form ([Approve Y/n], [Pick a/b/c], [Answer], [Do]), its context, its options with (Recommended) marked, and its default.
- **What happens next (mine) is ONE list**: the arc's goal, then your next moves in order. Anything Justin must do is an ask.
- **What I did** lists completed items only.
- **Optional sections** appear only when they have content: **Discussion:** (bullets, between Deviations and Asks) and a handoff block between `⏭️⏭️⏭️⏭️⏭️⏭️⏭️⏭️` rules.

| Next step      | Means                                                    |
| -------------- | -------------------------------------------------------- |
| `handoff`      | I am out of context; the next session picks this up      |
| `answerAsks`   | I need your answers before the next move is worth making |
| `continue`     | I keep going on this arc                                 |
| `done`         | The arc is finished                                      |
| `testOnDevice` | It needs your hands on a device or a browser             |

```
🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑

**Status:** ✅ Work completed
**Next step:** 🙋 answerAsks
**Progress:** 📈 85%
**Blockers:** 🛑 1 P0 ask

**Thread:** justin-loop session respawning
**Stop reason:** The renderers are built and the gates are green.
**You asked me to:** build the notification hook and fix the subagent notifications
**Your last message, verbatim:** go build the format v2 dispatch

**What happens next (mine):**
- ⚽ Goal: Run a successful test of justin-loop session respawning
- ➡️ Build the token notification hook
- ➡️ Run the test on the nature-sounds repo

**What I did:**
- ✅ Built X
- ✅ Built Y
- ✅ Created fdlc.2 (the retry-on-lock change) for the follow-up I found

**What I learned:**
1. Always use bullets in my responses (✅ added to the conductor skill)
2. Token count from X is unreliable (✅ added to justin-sdk CLAUDE.md)

**Answers to your questions:**
1. Q: Is there conflicting information in the critical rules?
   A: Yes — rules 3.3 and 3.4 disagree about bead comments. Filed home-pqzy (the bead-comments contradiction).

**Deviations from what you asked for:**
- ⚠️ You asked for three independent renderers; two of them share one classifier, because the stored report is text and a second walker would drift.

**Asks — everything I need from you:**
  1. 🛑 P0 · [Pick a/b] How should I build thing X, given your conflicting guidance?
     Context: Both rules are live and a session reading either one is wrong.
     a. (Recommended) Build it as Y — upside is __, downside is __.
     b. Build it as Z — upside is __, downside is __.
     If you don't answer: I stop here; I cannot pick this one for you.

  2. P2 · [Do] Install the dev build and open the Recordings tab
     Context: I cannot see whether the waveform renders; only a device can.
     If you don't answer: I ship it unverified and say so.

  3. (P3) · [Approve Y/n] Retire the claude-session-logger.sh script?
     Context: Nothing references it since the WezTerm experiment ended.
     If you don't answer: I retire it.
🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️🕉️
```
