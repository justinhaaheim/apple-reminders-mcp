# Beads Issue Tracking

This project uses **beads_rust** (`br`) for issue tracking. See `@AGENTS.md` for the full command reference.

**ALWAYS use beads for ALL work.** Every task — even trivial ones — should have a bead. This is non-negotiable. Beads provide accountability, trackability, visibility, and an audit trail. Specifically:

- **Before starting any work**, check `br ready` for existing beads, or create one.
- **For non-trivial tasks**, create an epic bead, break it into sub-beads, then implement. Close sub-beads as you go.
- **For quick tasks**, create a single bead, do the work, close it.
- **At session end**, ensure all completed work has closed beads, and any unfinished work has open beads with context for the next session.
- **Do NOT use markdown TODOs, task lists, or other tracking methods.** Beads is the single source of truth for task tracking.
