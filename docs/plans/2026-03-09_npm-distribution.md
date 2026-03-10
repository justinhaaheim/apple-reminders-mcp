# npm Distribution Setup

## Goal

Distribute `apple-reminders-mcp` via npm so users can install with `npx apple-reminders-mcp-cli` or `npm install -g apple-reminders-mcp-cli`.

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
- [x] Binaries exposed: `apple-reminders-mcp` and `apple-reminders` (both point to same universal binary)
- [x] `"os": ["darwin"]` prevents install on non-macOS
- [x] Created `scripts/build-universal.ts` (TypeScript, runs with bun)
- [x] Added `build:universal` and `build:npm` scripts to root package.json
- [x] Created `.github/workflows/npm-publish.yaml` — triggers on GitHub Release, builds universal binary, publishes to npm
- [x] Workflow includes manual dispatch with dry-run option, setup-node before first node usage
- [x] Version synced from root `package.json` at publish time

## Code review fixes applied

- [x] **#1** getDiff() — changed to `git show --stat HEAD` (was always empty after snapshot)
- [x] **#2** SnapshotTakeCommand — eliminated double store; calls `requestAccess()` on single store
- [x] **#3** ExportResult.note — only set when using temp dir default
- [x] **#4** MCPCommand — added `GlobalOptions`, wires up `--mock`, `--test-mode`
- [x] **#6** EKReminderStore.createReminder — replaced `fatalError` with `throw`
- [x] **#7** runGit — separated stdout/stderr pipes
- [x] **#8** DateFormatter — cached as static instances
- [x] **#9** CI — moved `setup-node` + `setup-bun` before build steps
- [x] **#10** npm bin — renamed `reminders` → `apple-reminders`
- [x] **#11** Reminder protocol — added `: AnyObject` constraint
- [x] **#12** CLI version — extracted to `Version.swift` in core library

### Not addressed (design discussions)

- **#5** queryReminders returns `Any` — genuine design tension with JMESPath returning arbitrary types
- **#13** SnapshotManager as actor — valid but orthogonal; no concurrent snapshot operations today

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
apple-reminders query --all-lists --pretty
```

## Next steps

- [ ] Add README.md to npm/ package (can copy/adapt from root README)
- [ ] Set up NPM_TOKEN secret in GitHub repo settings
- [ ] Test with a dry-run publish
- [ ] Consider adding `engines` field for minimum Node.js version
