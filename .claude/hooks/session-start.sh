#!/bin/bash

# Only run in Claude Code Web (remote) environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

# Install dependencies
bun i

# Install beads (bd) for issue tracking
if ! command -v bd &>/dev/null; then
  echo "Installing bd (beads issue tracker)..."
  curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
fi

# Initialize beads if not already initialized
if [ ! -d .beads ]; then
  bd init --quiet
fi

echo "bd is ready! Use 'bd ready' to see available work."

exit 0
