#!/bin/bash

# Run the setup-env script which handles both local and remote environments
bun scripts/setup-env.ts

# Initialize beads if not already initialized (remote only)
if [ "$CLAUDE_CODE_REMOTE" = "true" ]; then
  if [ ! -d .beads ]; then
    bd init --quiet 2>/dev/null || true
  fi
  echo "bd is ready! Use 'bd ready' to see available work."
fi

exit 0
