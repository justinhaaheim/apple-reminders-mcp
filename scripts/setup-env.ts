#!/usr/bin/env bun
/**
 * setup-env.ts — Ensure development tools are installed and available.
 *
 * Behavior differs by environment:
 *   - Remote (CLAUDE_CODE_REMOTE=true): Installs Swift for Linux,
 *     installs beads (bd), runs `bun install`, and adds tools to PATH.
 *   - Local: Validates that required tools are available and prints
 *     actionable errors if they're not. Does not install anything.
 *
 * This script is referenced by the SessionStart hook in .claude/settings.json.
 * It is idempotent and safe to re-run.
 */

import {execSync} from 'child_process';
import {appendFileSync, existsSync} from 'fs';
import {resolve} from 'path';

const HOME = process.env.HOME ?? '/root';
const PROJECT_ROOT = resolve(import.meta.dirname, '..');
const IS_REMOTE = process.env.CLAUDE_CODE_REMOTE === 'true';

// Swift installation paths
const SWIFT_VERSION = '6.1';
const SWIFT_RELEASE = `swift-${SWIFT_VERSION}-RELEASE`;
const SWIFT_INSTALL_DIR = resolve(HOME, '.local/swift');

function run(
  cmd: string,
  options?: {cwd?: string; ignoreError?: boolean; timeout?: number},
): string {
  try {
    return execSync(cmd, {
      cwd: options?.cwd ?? PROJECT_ROOT,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: options?.timeout ?? 120_000,
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
  console.warn(`[setup-env] WARNING: ${msg}`);
}

function commandExists(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, {stdio: 'pipe'});
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Swift installation (remote only)
// ---------------------------------------------------------------------------

function getSwiftBinDir(): string {
  // Check common install locations
  const candidates = [
    resolve(SWIFT_INSTALL_DIR, 'usr/bin'),
    `/tmp/${SWIFT_RELEASE}-ubuntu24.04/usr/bin`,
  ];
  for (const dir of candidates) {
    if (existsSync(resolve(dir, 'swift'))) {
      return dir;
    }
  }
  return resolve(SWIFT_INSTALL_DIR, 'usr/bin');
}

function installSwift(): void {
  // Check if swift is already available
  if (commandExists('swift')) {
    const version = run('swift --version', {ignoreError: true});
    if (version) {
      log(`Swift already installed: ${version.split('\n')[0]}`);
      return;
    }
  }

  // Check if we already downloaded it
  const swiftBinDir = getSwiftBinDir();
  if (existsSync(resolve(swiftBinDir, 'swift'))) {
    log(`Swift already downloaded at ${swiftBinDir}`);
    addToPath(swiftBinDir);
    return;
  }

  log(`Installing Swift ${SWIFT_VERSION} for Linux...`);

  // Detect architecture
  const arch = run('uname -m');
  const archSuffix = arch === 'aarch64' ? '-aarch64' : '';

  // Detect Ubuntu version
  const osRelease = run('cat /etc/os-release', {ignoreError: true});
  let ubuntuVersion = '24.04';
  let ubuntuCodename = 'ubuntu2404';
  if (osRelease.includes('22.04')) {
    ubuntuVersion = '22.04';
    ubuntuCodename = 'ubuntu2204';
  }

  const tarball = `${SWIFT_RELEASE}-ubuntu${ubuntuVersion}${archSuffix}.tar.gz`;
  const url = `https://download.swift.org/swift-${SWIFT_VERSION}-release/${ubuntuCodename}${archSuffix}/${SWIFT_RELEASE}/${tarball}`;
  const tmpTarball = `/tmp/${tarball}`;

  // Download
  log(`Downloading from ${url}...`);
  run(`curl -sL "${url}" -o "${tmpTarball}"`, {timeout: 600_000});

  // Extract to install dir
  log('Extracting...');
  run(`mkdir -p "${SWIFT_INSTALL_DIR}"`);
  run(
    `tar xzf "${tmpTarball}" --strip-components=1 -C "${SWIFT_INSTALL_DIR}"`,
    {timeout: 300_000},
  );

  // Clean up tarball
  run(`rm -f "${tmpTarball}"`, {ignoreError: true});

  // Add to PATH
  const binDir = resolve(SWIFT_INSTALL_DIR, 'usr/bin');
  addToPath(binDir);

  // Verify
  const version = run(`"${resolve(binDir, 'swift')}" --version`, {
    ignoreError: true,
  });
  if (version) {
    log(`Swift installed: ${version.split('\n')[0]}`);
  } else {
    warn('Swift installation may have failed — swift --version returned empty');
  }
}

function addToPath(dir: string): void {
  const envFile = process.env.CLAUDE_ENV_FILE;
  if (envFile) {
    appendFileSync(envFile, `export PATH="${dir}:$PATH"\n`);
  } else {
    warn(
      'CLAUDE_ENV_FILE not set. Swift may not be on PATH for subsequent commands.',
    );
  }
}

// ---------------------------------------------------------------------------
// Beads initialization (remote only)
// ---------------------------------------------------------------------------

function installBeads(): void {
  if (commandExists('bd')) {
    log('bd (beads) already installed.');
    return;
  }

  log('Installing bd (beads issue tracker)...');
  run(
    'curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash',
    {ignoreError: true, timeout: 60_000},
  );
}

// ---------------------------------------------------------------------------
// Remote environment setup
// ---------------------------------------------------------------------------

function setupRemote(): void {
  log('Remote environment detected. Installing tools...');

  // 1. Install node dependencies
  log('Installing node dependencies...');
  run('bun install', {ignoreError: true});

  // 2. Install Swift
  installSwift();

  // 3. Install beads
  installBeads();

  log('Remote setup complete.');
}

// ---------------------------------------------------------------------------
// Local environment validation
// ---------------------------------------------------------------------------

function validateLocal(): void {
  let hasErrors = false;

  // Check Swift
  if (!commandExists('swift')) {
    warn(
      'Swift is not installed. Install from https://www.swift.org/install/ or via Xcode.',
    );
    hasErrors = true;
  }

  // Check bun
  if (!commandExists('bun')) {
    warn('Bun is not installed. Install from https://bun.sh/');
    hasErrors = true;
  }

  if (!hasErrors) {
    log('Local environment OK.');
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
