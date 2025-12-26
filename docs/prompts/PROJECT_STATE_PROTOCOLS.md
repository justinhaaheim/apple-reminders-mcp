# Project State Protocols

## TLDR

The assistant should ALWAYS maintain two living documents: `ROADMAP.md` (project-level) and scratchpad files (task-level).

**On every commit**, the assistant should:

- ALWAYS update the active scratchpad with what was done and what's next
- ALWAYS ensure the Roadmap's "Next Actions" section has at least 3 prioritized items
- NEVER leave the project in a state where "what to work on next" is unclear

**When the human asks "what should I work on?"**, the assistant should:

- ALWAYS read `ROADMAP.md` and any linked scratchpads before responding
- ALWAYS present concrete options from "Next Actions" with relevant context
- Help the human choose something that moves toward a meaningful milestone

**When starting new work**, the assistant should:

- ALWAYS create a scratchpad if one doesn't exist for this work stream
- ALWAYS link the scratchpad from the Roadmap

**Key principle:** The assistant should capture "what's next" at the END of a work session (when context is fresh), not defer it to the START of the next session (when context is lost).

---

## Why This Matters

Context evaporates. Claude starts fresh each session. Human memory degrades, especially when juggling multiple projects. Chat history is ephemeral. Without a system, resuming work requires significant effort—opening editors, hunting for old conversations, reconstructing what was happening.

This protocol solves that by externalizing project state into living documents that are **always up to date**.

**The key insight:** Make decisions about "what's next" at the END of a session (when context is fresh), not at the START of the next session (when context is lost).

---

## The Two-Document System

### 1. Roadmap Document

**Location:** `ROADMAP.md` at project root
**Purpose:** The home base for all project planning—a living, frequently-updated document

The Roadmap answers questions at different levels:

| Level            | Question                         | Content                                     |
| ---------------- | -------------------------------- | ------------------------------------------- |
| Vision           | Where are we going?              | The exciting outcome we're building toward  |
| Milestones       | What are the chunks of work?     | Major steps, roughly sequenced, MVP-focused |
| In Progress      | What's actively being worked on? | Links to active scratchpad documents        |
| **Next Actions** | **What should I work on next?**  | **Always 3+ concrete, prioritized options** |
| Backlog          | What shouldn't we forget?        | Bugs, ideas, deferred items                 |

**The "Next Actions" section is the most important.** It's the thing you read when you're tired and just need a clear answer.

**If no Roadmap exists:** Create one. Start with what you know from CLAUDE.md and conversation context. It doesn't need to be perfect—it will evolve through use.

### 2. Scratchpad Documents

**Location:** `docs/plans/YYYY-MM-DD_descriptive-slug.md`
**Purpose:** Working memory for a specific stream of work

A scratchpad tracks one work stream—could be a single commit or span many commits / a full PR. It provides higher resolution than the Roadmap: implementation details, specific decisions, progress tracking, bugs encountered.

**Relationship to Roadmap:**

- Roadmap links to active scratchpads
- When starting new work, first step is creating a scratchpad
- Scratchpads contain detail; Roadmap contains summary

See `docs/prompts/USE_SCRATCHPAD.md` for scratchpad creation guidelines.

---

## The Protocol

### On Every Commit

**Always update the scratchpad:**

- Document what was accomplished
- Update progress checkboxes
- Capture what needs to happen next
- Note any bugs or issues encountered

**Check if Roadmap needs updating:**

- Check off completed items from "Next Actions"
- **If fewer than 3 items remain in "Next Actions", add more while context is fresh**
- Capture any new bugs, ideas, or backlog items
- Update links to scratchpads if work streams changed

### When User Asks "What should I work on?"

1. Read the Roadmap document
2. Read any linked active scratchpads
3. Consider recent conversation context
4. Present the prioritized options from "Next Actions" with relevant context
5. Help the user choose based on energy, importance, or what sounds satisfying
6. Be aware that it's easy to drift toward tinkering—help facilitate choosing something that moves toward a meaningful milestone

### When Starting New Work

1. Create a scratchpad for the work stream if one doesn't exist
2. Flesh out the goal, steps, and any known constraints
3. Link the scratchpad from the Roadmap's "In Progress" section

### When User Does a Brain Dump

Users may share unstructured thoughts about the project—ideas, bugs noticed, features wanted, concerns. When this happens:

1. Organize the content into appropriate Roadmap sections
2. Help identify the MVP path—minimum focused work to reach the next milestone
3. Update the Roadmap with the organized content

---

## Design Principles

1. **Living documents** — Updated constantly, not static artifacts
2. **Capture context when fresh** — Always record "what's next" while you still know
3. **3+ options rule** — "Next Actions" always has at least 3 prioritized items
4. **Commit = scratchpad update** — Every code commit includes a scratchpad update
5. **MVP mindset** — Help identify the minimum work to reach each milestone
6. **Links between docs** — Roadmap links to scratchpads; everything is traversable

---

## Quick Reference

| Trigger                   | Action                                              |
| ------------------------- | --------------------------------------------------- |
| Making a commit           | Update scratchpad; check if Roadmap needs updates   |
| User asks "what's next?"  | Read Roadmap + scratchpads, present options         |
| Starting new work         | Create scratchpad, link from Roadmap                |
| Completing a milestone    | Check off in Roadmap, ensure 3+ next actions remain |
| User brain dumps thoughts | Organize into Roadmap sections                      |
