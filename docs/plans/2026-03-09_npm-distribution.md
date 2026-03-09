# npm Distribution Setup

## Goal

Distribute `apple-reminders-mcp` via npm so users can install with `npx apple-reminders-mcp` or `npm install -g apple-reminders-mcp-cli`.

## Approach

**Bundled universal binary** — ship a fat macOS binary (arm64 + x86_64) directly in the npm package. No postinstall scripts, no external downloads.

### Why this approach

- Works with `--ignore-scripts` (common security setting)
- No external network calls during install (only npm registry)
- No corporate firewall issues
- Simplest possible implementation
- ~20-30MB package size is acceptable

### Alternatives considered

1. **postinstall download from GitHub Releases** — fragile, breaks with `--ignore-scripts`
2. **esbuild-style optionalDependencies** — overkill for 2 platforms
3. **Combined approach (Sentry)** — unnecessary complexity for macOS-only

## What was done

- [x] Created `npm/package.json` with name `apple-reminders-mcp-cli`
- [x] Both binaries exposed: `apple-reminders-mcp` and `reminders` (both point to same universal binary)
- [x] `"os": ["darwin"]` prevents install on non-macOS
- [x] Created `scripts/build-universal.sh` — builds arm64 + x86_64, lipo creates universal binary in `npm/bin/`
- [x] Added `build:universal` and `build:npm` scripts to root package.json
- [x] Created `.github/workflows/npm-publish.yaml` — triggers on GitHub Release, builds universal binary, publishes to npm
- [x] Workflow includes manual dispatch with dry-run option
- [x] Version synced from root `package.json` at publish time

## Usage after publish

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "npx",
      "args": ["-y", "apple-reminders-mcp-cli"]
    }
  }
}
```

Or install globally:

```bash
npm install -g apple-reminders-mcp-cli
reminders query --all-lists --pretty
```

## Next steps

- [ ] Add README.md to npm/ package (can copy/adapt from root README)
- [ ] Set up NPM_TOKEN secret in GitHub repo settings
- [ ] Test with a dry-run publish
- [ ] Consider adding `engines` field for minimum Node.js version
