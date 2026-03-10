#!/usr/bin/env bun

/**
 * Build universal macOS binary for npm distribution.
 *
 * Produces a fat binary containing both arm64 and x86_64 slices,
 * then copies it to npm/bin/ for packaging.
 *
 * Usage:
 *   bun scripts/build-universal.ts          # Build and copy to npm/bin/
 *   bun scripts/build-universal.ts --check  # Also verify the result with lipo -info
 */

import {$} from 'bun';
import {join} from 'path';

const REPO_ROOT = join(import.meta.dir, '..');
const BUILD_DIR = join(REPO_ROOT, '.build');
const NPM_BIN = join(REPO_ROOT, 'npm', 'bin');
const PRODUCT = 'reminders';

const check = process.argv.includes('--check');

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

// Build both architectures
await run(`Building ${PRODUCT} for arm64...`, [
  'swift',
  'build',
  '-c',
  'release',
  '--arch',
  'arm64',
]);
await run(`Building ${PRODUCT} for x86_64...`, [
  'swift',
  'build',
  '-c',
  'release',
  '--arch',
  'x86_64',
]);

// Verify binaries exist
const arm64Bin = join(BUILD_DIR, 'arm64-apple-macosx', 'release', PRODUCT);
const x86_64Bin = join(BUILD_DIR, 'x86_64-apple-macosx', 'release', PRODUCT);

for (const [arch, path] of [
  ['arm64', arm64Bin],
  ['x86_64', x86_64Bin],
] as const) {
  if (!(await Bun.file(path).exists())) {
    console.error(`ERROR: ${arch} binary not found at ${path}`);
    process.exit(1);
  }
}

// Create universal binary with lipo
await $`mkdir -p ${NPM_BIN}`;
await run('Creating universal binary...', [
  'lipo',
  '-create',
  arm64Bin,
  x86_64Bin,
  '-output',
  join(NPM_BIN, PRODUCT),
]);
await $`chmod +x ${join(NPM_BIN, PRODUCT)}`;

console.log(`==> Universal binary created at ${join(NPM_BIN, PRODUCT)}`);

if (check) {
  console.log('==> Verifying:');
  await $`lipo -info ${join(NPM_BIN, PRODUCT)}`;
  await $`ls -lh ${join(NPM_BIN, PRODUCT)}`;
}

console.log('==> Done.');
