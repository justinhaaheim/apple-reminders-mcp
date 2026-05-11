#!/usr/bin/env bun
/**
 * setup-env.ts — Ensure development tools are installed and available.
 *
 * Behavior differs by environment:
 *   - Remote (CLAUDE_CODE_REMOTE=true): Bootstraps mise + PATH, runs any
 *     project-specific `setup-env:*` scripts declared in package.json, then
 *     delegates to `doctor --fix --yes` for SDK-component tool installation.
 *     The --yes flag pre-approves system-level installs (mise, br, etc.).
 *   - Local: Runs `doctor --quiet` to validate the environment. Never
 *     auto-installs anything — approvals must be explicit via --yes.
 *
 * Project-specific setup hook:
 *   Any package.json script whose name starts with `setup-env:` is treated
 *   as a project-specific setup step. They run between the mise/PATH
 *   bootstrap and `doctor --fix`, in alphabetical order. Use numeric
 *   prefixes (`setup-env:10-swift`, `setup-env:20-foo`) if you need strict
 *   ordering. Each sub-script is responsible for its own idempotence and
 *   failure handling — setup-env.ts logs + continues on sub-script failure.
 *
 * This script is designed to be copied into any project at scripts/setup-env.ts
 * and referenced by a SessionStart hook in .claude/settings.json.
 *
 * PREREQUISITE: bun must be installed. In Dockerfiles, add either:
 *   RUN npm i -g bun
 *   RUN curl -fsSL https://bun.sh/install | bash
 *
 * It is idempotent and safe to re-run.
 */

import {execSync} from 'child_process';
import {appendFileSync, existsSync, readFileSync} from 'fs';
import {resolve} from 'path';

const HOME = process.env.HOME ?? '/root';
const PROJECT_ROOT = resolve(import.meta.dirname, '..');
const MISE_BIN = resolve(HOME, '.local/bin/mise');
const MISE_SHIMS_DIR = resolve(HOME, '.local/share/mise/shims');
const IS_REMOTE = process.env.CLAUDE_CODE_REMOTE === 'true';

function run(
  cmd: string,
  options?: {cwd?: string; ignoreError?: boolean},
): string {
  try {
    return execSync(cmd, {
      cwd: options?.cwd ?? PROJECT_ROOT,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    if (options?.ignoreError) return '';
    throw error;
  }
}

function log(msg: string): void {
  console.log(`[setup-env] ${msg}`);
}

function warn(msg: string): void {
  console.warn(`[setup-env] ⚠ ${msg}`);
}

// ---------------------------------------------------------------------------
// Project-specific setup-env:* sub-script discovery
// ---------------------------------------------------------------------------

function discoverProjectSetupScripts(): string[] {
  const pkgPath = resolve(PROJECT_ROOT, 'package.json');
  if (!existsSync(pkgPath)) return [];

  let pkg: {scripts?: Record<string, string>};
  try {
    pkg = JSON.parse(readFileSync(pkgPath, 'utf-8')) as {
      scripts?: Record<string, string>;
    };
  } catch (error) {
    warn(`Failed to parse package.json: ${String(error)}`);
    return [];
  }

  const scripts = pkg.scripts ?? {};
  return Object.keys(scripts)
    .filter((name) => name.startsWith('setup-env:'))
    .sort();
}

function runProjectSetupScripts(): void {
  const subScripts = discoverProjectSetupScripts();
  if (subScripts.length === 0) return;

  log(
    `Running ${subScripts.length} project setup script(s): ${subScripts.join(', ')}`,
  );
  for (const name of subScripts) {
    log(`→ ${name}`);
    try {
      execSync(`bun run ${name}`, {
        cwd: PROJECT_ROOT,
        encoding: 'utf-8',
        stdio: 'inherit',
      });
    } catch {
      warn(`${name} failed — continuing.`);
    }
  }
}

// ---------------------------------------------------------------------------
// Remote environment setup
// ---------------------------------------------------------------------------

function setupRemote(): void {
  log('Remote environment detected. Installing tools...');

  // Phase 1: Bootstrap — things that must happen before doctor can run

  // 1a. Install node dependencies (needed for SDK / doctor to be available)
  log('Installing node dependencies...');
  run('bun install', {ignoreError: true});

  // 1b. Install mise if not present
  if (!existsSync(MISE_BIN)) {
    log('Installing mise...');
    run('curl -fsSL https://mise.run | sh', {ignoreError: true});
  }

  // 1c. Ensure mise shims + ~/.local/bin are on PATH
  const envFile = process.env.CLAUDE_ENV_FILE;
  if (envFile) {
    if (existsSync(MISE_BIN)) {
      log('Adding mise shims to PATH...');
      appendFileSync(envFile, `export PATH="${MISE_SHIMS_DIR}:$PATH"\n`);
    }
    const localBin = resolve(HOME, '.local/bin');
    appendFileSync(envFile, `export PATH="${localBin}:$PATH"\n`);
  } else {
    warn(
      'CLAUDE_ENV_FILE not set. Tool binaries may not be on PATH for subsequent commands.',
    );
  }

  // Phase 1.5: Project-specific setup-env:* scripts
  runProjectSetupScripts();

  // Phase 2: Delegate to doctor --fix --yes for SDK component tools.
  // --yes pre-approves system-level installs (mise, br). Safe in
  // remote/sandbox environments; on local dev, approvals are explicit.
  log('Running doctor --fix --yes...');
  try {
    execSync('bun run doctor:fix -- --yes', {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      stdio: 'inherit',
    });
    log('Remote setup complete.');
  } catch {
    warn('doctor --fix --yes reported failures. Check output above.');
  }
}

// ---------------------------------------------------------------------------
// Local environment validation
// ---------------------------------------------------------------------------

function validateLocal(): void {
  try {
    execSync('bun run doctor -- --quiet', {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      stdio: 'inherit',
    });
  } catch {
    // doctor prints its own output — no need to duplicate
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  if (IS_REMOTE) {
    setupRemote();
  } else {
    validateLocal();
  }
}

main();
