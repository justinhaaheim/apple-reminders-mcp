# Agent Instructions


## Dependency Direction (IMPORTANT)

`br dep add <issue> <depends-on>` means `<issue>` is **blocked by** `<depends-on>`.

- **Epic/sub-bead pattern**: The **epic depends on its sub-beads**, NOT the other way around. The epic is blocked until its sub-beads are done.
  - Correct: `br dep add EPIC SUB_BEAD` (epic is blocked by sub-bead)
  - WRONG: `br dep add SUB_BEAD EPIC` (this would mean the sub-bead can't start until the epic is done, which is backwards)
- **Sequential tasks**: If task B can't start until task A is done: `br dep add B A`
- Think of it as: **"Who is waiting?"** The _waiter_ is the first argument.

<!-- br-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`/`bd`) for issue tracking. Issues are stored in the project beads workspace and tracked in git.

### Essential Commands

Most subcommands accept multiple issue IDs in a single invocation.

```bash
# View ready issues (open, unblocked, not deferred)
br ready              # or: bd ready

# List and search
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br show <id1> <id2>   # Show multiple issues at once
br search "keyword"   # Full-text search

# Create and update
br create --title="..." --description="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once
br reopen <id1> <id2> # Reopen multiple issues at once
br delete <id1> <id2> # Delete multiple issues at once

# Sync with git
br sync --flush-only  # Export DB to JSONL
br sync --status      # Check sync status
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only open, unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git commit -m "..."     # Commit everything
git push                # Push to remote
```

### Best Practices

- Check `br ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `br create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always sync before ending session

<!-- end-br-agent-instructions -->
