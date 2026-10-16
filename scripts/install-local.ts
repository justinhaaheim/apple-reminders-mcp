#!/usr/bin/env bun

/**
 * Install the `reminders` binary to ~/.local/bin, independent of this checkout.
 *
 * Claude Desktop, other repos' .mcp.json files and launchd jobs run the
 * installed copy, so rebuilding or switching branches here never changes what
 * they run. Before 2026-10-16 they all ran .build/release/reminders directly,
 * and that binary silently held an unmerged branch's code for four months.
 *
 * - Refuses uncommitted changes to the build inputs, so every install maps to
 *   a commit (recorded in the install log).
 * - Builds into its own scratch path (.build-install/), never touching .build/.
 * - Checks the new binary runs (`--help`) before swapping it in.
 * - Keeps the previous binary as reminders.prev for rollback:
 *     mv ~/.local/bin/reminders.prev ~/.local/bin/reminders
 * - Swaps with a rename, so a running MCP server keeps its old file.
 * - Appends one line per install to
 *   ~/.local/share/apple-reminders-mcp/installs.jsonl.
 *
 * Usage:
 *   bun run install:local
 */

import {$} from 'bun';
import {createHash} from 'node:crypto';
import {
  appendFileSync,
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
} from 'node:fs';
import {homedir} from 'node:os';
import {join} from 'node:path';

const REPO_ROOT = join(import.meta.dir, '..');
const SCRATCH_DIR = join(REPO_ROOT, '.build-install');
const PRODUCT = 'reminders';
const BUILD_INPUTS = ['Sources', 'Package.swift', 'Package.resolved'];

const BIN_DIR = join(homedir(), '.local', 'bin');
const INSTALLED = join(BIN_DIR, PRODUCT);
const STAGED = `${INSTALLED}.new`;
const PREVIOUS = `${INSTALLED}.prev`;
const LOG_DIR = join(homedir(), '.local', 'share', 'apple-reminders-mcp');
const LOG_FILE = join(LOG_DIR, 'installs.jsonl');

async function run(label: string, cmd: string[]) {
  console.log(`==> ${label}`);
  const result = await Bun.spawn(cmd, {
    cwd: REPO_ROOT,
    stdout: 'inherit',
    stderr: 'inherit',
  }).exited;
  if (result !== 0) {
    console.error(`ERROR: command failed with exit code ${result}`);
    process.exit(1);
  }
}

function sha256(path: string): string {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

async function assertRuns(path: string) {
  const result = await $`${path} --help`.nothrow().quiet();
  if (result.exitCode !== 0) {
    console.error(
      `ERROR: ${path} --help exited ${result.exitCode}; not installing.\n${result.stderr.toString()}`,
    );
    process.exit(1);
  }
}

// 1. The build inputs must match a commit.
const status =
  await $`git -C ${REPO_ROOT} status --porcelain -- ${BUILD_INPUTS}`
    .nothrow()
    .quiet();
if (status.exitCode !== 0) {
  console.error(
    `ERROR: git status failed (exit ${status.exitCode}); cannot tell whether the sources are committed.\n${status.stderr.toString()}`,
  );
  process.exit(1);
}
const dirty = status.stdout.toString().trim();
if (dirty !== '') {
  console.error(
    `ERROR: uncommitted changes to the build inputs. Commit them first so the installed binary maps to a commit:\n${dirty}`,
  );
  process.exit(1);
}
const commit = (await $`git -C ${REPO_ROOT} rev-parse HEAD`.text()).trim();

// 2. Build into a scratch path of its own.
await run(
  `Building ${PRODUCT} at ${commit.slice(0, 7)} into ${SCRATCH_DIR}...`,
  [
    'swift',
    'build',
    '-c',
    'release',
    '--product',
    PRODUCT,
    '--scratch-path',
    SCRATCH_DIR,
  ],
);
const built = join(SCRATCH_DIR, 'release', PRODUCT);
if (!existsSync(built)) {
  console.error(`ERROR: build reported success but ${built} does not exist`);
  process.exit(1);
}
await assertRuns(built);

// 3. Stage next to the target, check the copy, keep the old one, swap.
mkdirSync(BIN_DIR, {recursive: true});
copyFileSync(built, STAGED);
chmodSync(STAGED, 0o755);
await assertRuns(STAGED);

const previousSha256 = existsSync(INSTALLED) ? sha256(INSTALLED) : null;
if (previousSha256 !== null) {
  copyFileSync(INSTALLED, PREVIOUS);
  chmodSync(PREVIOUS, 0o755);
}
renameSync(STAGED, INSTALLED);

// 4. Record what is installed.
const installedSha256 = sha256(INSTALLED);
mkdirSync(LOG_DIR, {recursive: true});
appendFileSync(
  LOG_FILE,
  `${JSON.stringify({
    commit,
    installedAt: new Date().toISOString(),
    path: INSTALLED,
    previousSha256,
    sha256: installedSha256,
  })}\n`,
);

console.log(`==> Installed ${INSTALLED} from ${commit.slice(0, 7)}`);
console.log(`    sha256 ${installedSha256}`);
if (previousSha256 !== null) {
  console.log(
    `    previous binary kept at ${PREVIOUS} (sha256 ${previousSha256})`,
  );
}
console.log(`    install log: ${LOG_FILE}`);
