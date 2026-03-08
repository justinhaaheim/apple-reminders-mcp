# npm Distribution Plan

**Date**: 2026-03-08
**Goal**: Enable one-line installation via `npx` for Claude Desktop users

## Target User Experience

Claude Desktop config:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "npx",
      "args": ["-y", "apple-reminders-mcp"]
    }
  }
}
```

That's it. No git clone, no Swift toolchain, no manual binary paths.

## Status

- [ ] Plan approved
- [ ] GitHub Actions release workflow (build universal binary)
- [ ] npm package structure (launcher + postinstall)
- [ ] Publish to npm
- [ ] Update docs

---

## Design Decisions

### Approach: Single npm package with postinstall binary download

**Why not platform-specific packages (esbuild pattern)?**

- esbuild's `@esbuild/darwin-arm64` pattern is great for cross-platform (Linux, Windows, macOS × arm64/x64 = 6+ packages)
- We only need macOS. A single universal binary (arm64 + x86_64 via `lipo`) covers all Mac users
- Much simpler to maintain one package vs multiple

**Why not bundle the binary in the npm package?**

- npm has a 60MB upload limit; universal Swift binaries can be large
- Downloading from GitHub Releases keeps the npm package tiny (~5KB)
- Users always get the exact version matching the npm package version

### Binary strategy: Universal macOS binary

Build with `lipo` to combine arm64 + x86_64 into a single binary. This means:

- One binary works on all Macs
- No architecture detection needed at install time
- GitHub Actions can build both architectures on macOS runners

---

## Implementation Plan

### 1. GitHub Actions Release Workflow

New workflow: `.github/workflows/release.yml`

Triggered by: pushing a git tag like `v0.1.0`

Steps:

1. Build on macOS runner (arm64): `swift build -c release`
2. Build on macOS runner (x86_64): cross-compile or use separate runner
3. Create universal binary with `lipo -create -output`
4. Create GitHub Release with the universal binary attached
5. Trigger npm publish (or do it manually)

**Note**: GitHub's macOS runners are arm64 (M1) by default. For x86_64, use `macos-13` runner. For arm64, use `macos-14` or later.

### 2. npm Package Structure

```
npm/
├── package.json        # Published to npm
├── bin/
│   └── apple-reminders-mcp    # Shell script launcher
├── scripts/
│   └── postinstall.js  # Downloads binary from GitHub Releases
└── README.md           # npm page content
```

**package.json** (npm version):

```json
{
  "name": "apple-reminders-mcp",
  "version": "0.1.0",
  "description": "MCP server for Apple Reminders on macOS — use with Claude Desktop",
  "bin": {
    "apple-reminders-mcp": "bin/apple-reminders-mcp"
  },
  "scripts": {
    "postinstall": "node scripts/postinstall.js"
  },
  "os": ["darwin"],
  "engines": {
    "node": ">=16"
  },
  "files": ["bin/", "scripts/", "README.md"],
  "repository": "justinhaaheim/apple-reminders-mcp",
  "license": "MIT"
}
```

**bin/apple-reminders-mcp** (shell script):

```bash
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$DIR/../vendor/reminders"
exec "$BINARY" mcp "$@"
```

**scripts/postinstall.js**:

- Reads version from package.json
- Downloads binary from `https://github.com/justinhaaheim/apple-reminders-mcp/releases/download/v${version}/reminders-macos-universal`
- Saves to `vendor/reminders`
- Makes executable (`chmod +x`)
- Verifies it runs (`./vendor/reminders --version`)
- Falls back gracefully with clear error if download fails

### 3. Versioning Strategy

- npm package version and git tag version stay in sync
- Tag `v0.1.0` → GitHub Release `v0.1.0` → npm `0.1.0`
- The postinstall script uses its own package.json version to know which release to download

### 4. Root package.json changes

The existing root `package.json` is for development (bun, prettier, husky). The npm-published package will be in `npm/` subdirectory with its own `package.json`. This keeps concerns separate.

**Alternative**: Rename root package.json to not conflict, or restructure. TBD.

Actually, the cleaner approach might be to make the root package.json the published one and move dev deps elsewhere. But that conflicts with the current dev setup. Let's use the `npm/` subdirectory approach.

---

## Open Questions

1. **Package name**: `apple-reminders-mcp` is already the repo name. Is it available on npm?
2. **Should we also publish the CLI?** The npm package could expose both `apple-reminders-mcp` (MCP server) and `reminders` (CLI) binaries
3. **Fallback**: If the binary download fails, should we try to build from source? (Requires Swift toolchain — probably not worth it)
4. **npm org scope**: Publish as `apple-reminders-mcp` or `@justinhaaheim/apple-reminders-mcp`?

---

## Next Steps

1. Set up GitHub Actions release workflow
2. Create `npm/` directory with package structure
3. Write postinstall.js
4. Test locally (simulate the flow)
5. Create a test release on GitHub
6. Publish to npm
7. Test end-to-end with Claude Desktop
