# Handoff: starting the next session

This file says when and how a session hands its work on to a fresh session. In Justin's words (2026-10-29): "claude code's job is to call our tool to kickoff the new session, and that that tool may opt not to open the session due to session limits, rate limits, or any other reason. So there's a clear API, claude knows what to do, and claude doesn't try to hack around it (i don't want claude "going rogue" like that opening new cc sessions)."

## When to hand off

Hand off only when this session cannot go on:

- its context is nearly full,
- Justin asked for a new session, or
- a wrap-up notice told it to hand off.

Never hand off as a way to stop with open work.

Hand off only with no background work running: no subagent and no background shell of yours may still be working. Justin can set the old tab to exit or close after the handoff, and that ends everything still running in it.

## How to hand off

Run this command once, from the repository root:

```
./node_modules/.bin/justin-sdk thread handoff --note "<one line the next session must know>"
```

- Spell it exactly like this, starting with `./node_modules/.bin/justin-sdk`. Do not start it with `bun`: Claude Code never lets a command that starts with `bun` out of the sandbox, and the handoff then fails.
- Run it bare. Put nothing before or after it: no `cd … &&`, no redirect, no `$(…)`. Any of them keeps the whole call inside the Claude Code sandbox, even where Justin's global sandbox exclusion matches the command, and the handoff then fails.
- Keep backticks out of the note. A note that holds a backtick keeps the call inside the sandbox, even inside single quotes, and the handoff then fails.
- Run it from the repository root, where `node_modules` is. If `./node_modules/.bin/justin-sdk` is not in the current directory, run `cd <repository root>` as its own Bash call first.
- If `./node_modules/.bin/justin-sdk` is missing at the repository root too, the repository has no `bun install` yet. Say so in your final report and stop.
- It records the handoff on this session's bead and prints a handoff block. Where `componentConfig.thread.handoff.successor` is on, it also opens the next session in a new tab, or refuses.
- `./node_modules/.bin/justin-sdk thread handoff --help` lists every step and exit code.

## What the exit code means

The command may refuse: too many sessions running, usage too high, or another reason. Refusing is its job.

- **Exit 0: handed off.** If the output names a new tab, the next session is already running there. If it does not, put the printed handoff block in your final report, so Justin can start the next session from it. Either way, write your final report now and end your turn. Do no more work: the next session works in the same checkout.
- **Exit 1: a step failed after the handoff was recorded.** The output says what was done. Quote it in your final report and stop. Do not run `thread handoff` again.
- **Exit 2: nothing was written.** The output says why. If your call was wrong, fix it and run it again. Otherwise report the message and stop.
- **Exit 3: the gate refused.** The handoff and the refusal are recorded, and nothing was opened. The refusal is final. Put the printed handoff block in your final report and stop. Do not run `thread handoff` again.

Where the old tab is set to exit or close after a handoff, it waits until the next session has linked and your last message is recorded. Do nothing to help it: finish your report and stop.

## Never start a session another way

- `thread handoff` is the only way to start the session that continues this one.
- Never start a session for unrelated work or in another project. File the work as a bead and tell Justin in your report.
- The one exception is a repository with `componentConfig.thread.spawn.allowed` on, which is home-base, where the mayor runs. Only there does `bun run justin-sdk thread spawn` run (see its `--help`). It passes the same gate, and its exit 3 is final too. Everywhere else it refuses: do not retry it from another directory.
- Never open, type into or close a tab, pane or workspace with `cmux`: no `new-workspace`, `new-surface`, `new-split`, `new-pane`, `send` or `close-…`. Reading with `cmux identify`, `cmux tree` or `cmux read-screen` is fine.
- Never start Claude Code yourself: no `claude` with or without a prompt, no `--bg`, `-p`, `--resume` or `attach`.
- Where `componentConfig.thread.handoff.successor` is on, a guard refuses these commands. It does not catch every spelling: a command it lets through is still forbidden. When it refuses one, do not rewrite the command to get past it.
- Subagents never run `thread handoff` or `thread spawn`. They report to the session that dispatched them. The guard refuses a subagent's call and records it.
