# Requests: what Justin asked for

A request is what `thread status` and Justin's inbox track for a session. status-report-format.md says how to file one and when to close it. This file says what counts as a request and how to find the requests in his words.

It exists because of one failure: a session filed requests, closed every one, and the thing he asked for was never done. In his words (2026-10-17): "If I can't trust that the tooling and the way that Claude Code is using the tooling are going to actually accurately capture the requests … then I start to lose trust in the whole system itself."

In a subagent, do not file requests. Tell the session that dispatched you about any you notice.

## What a request is

- A request is "anything that the user has indicated they want to happen, even if conditional, even if they're not sure about it, especially if they're not sure about it" (Justin, 2026-10-17).
- A request is the outcome behind his words, not their verb. "Build", "fix", "change" and "decide, then do" say how the work gets done. The request is what exists once it is done.
- "Help me fix this thing", "help me scope it" and "do some research on X" are all requests.

## From a message to its requests

1. Read the whole message before you file anything.
2. File the highest-level ask first: the outcome that would make him say "yes, that's what I wanted".
3. File a sub-request only when he will want to see it tracked on its own.
4. File a conditional step now, as its own request. "If that's the case, then do this third thing" is a request.
5. File a research or look-into ask as a request with three stages: you answer, he decides, the work gets done.
6. When his wording is loose ("we need to fix this somehow"), name the outcome: "X works again". Do not guess whether it is a bug or a feature.

## A placeholder beats a miss

- When you are unsure whether something is a request, file it. In his words: "it's better to create a request as sort of a stub, a placeholder … if there's any uncertainty about it and then to close it later" (2026-10-17).
- Close one that turns out not to be needed with its reason: `br close <id> --reason "not needed: …"`.
- A missed request is the failure. An extra request that you close costs nothing.

## Requests span turns

- Expect a request to outlive the turn. In his words: "requests are sometimes or maybe oftentimes not going to be resolved in a single turn, and that that should be Claude Code's expectation" (2026-10-17).
- Yielding with open requests is normal. His inbox tells him what he has to do. A closed request tells him the outcome exists.

## Before you close the last open request

Closing the last open request tells him "nothing to do here". Before you close it:

1. Re-read his first message, then every later message.
2. Check each thing he asked for: it exists, your message answers it, or a request for it is open.
3. File a request for each thing that fails the check. Then close the last one.

Do this check yourself, every time. A reminder from `thread nudge` or `thread status` is a prompt to do it, not a substitute for it. The reminder is best-effort: it misses some closes, so its silence is not a sign that the check passed.

## Worked examples

The messages below are made-up examples, not his words.

**A research ask.** He writes: "Do some research for me on X, Y and Z. I want to pick one for the sync job."

- File: "Choose X, Y or Z for the sync job and set it up". Its stages: your comparison, his choice, the setup of the one he picks.
- Do not file "Research X", "Research Y" and "Research Z" in its place. Each closes when its write-up is done, and the choice he asked for is left unmade. That is the failure this file exists for.

**A think-it-through ask.** He writes: "Think through how we manage hooks across projects. Keep the per-repo entries, or go back to a plugin?"

- File: "Change how justin-sdk hooks are installed". Its stages: your proposal, his decision, the change built.
- Do not file "Think through how hooks are managed", or one request per part of your analysis. Each closes when you have answered, and the change he wanted is left unbuilt. A real session reported five of five requests done while the hooks were unchanged.

**A conditional three-step build.** He writes: "Add a CSV export to the report page. Check whether the PDF export runs the same query. If it does, move both onto one shared query."

- File: "Add a CSV export to the report page".
- File: "Move the CSV and PDF exports onto one shared query, if the PDF export runs the same query". File it now. If the check says no, close it: `--reason "not needed: the PDF export runs its own query"`.
- Do not file "Check whether the PDF export runs the same query". The check is a step of the second request, not an outcome he asked for.
