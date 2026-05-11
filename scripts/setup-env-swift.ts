#!/usr/bin/env bun
/**
 * setup-env-swift.ts — Install Swift for Linux in remote environments.
 *
 * Called automatically by setup-env.ts via the `setup-env:swift` package.json
 * script. Only installs in remote (Linux) environments — on macOS, Swift is
 * assumed to be available via Xcode or the Command Line Tools.
 *
 * Idempotent: checks for existing Swift installations before downloading.
 */

import {execSync} from 'child_process';
import {appendFileSync, existsSync} from 'fs';
import {resolve} from 'path';

const HOME = process.env.HOME ?? '/root';
const SWIFT_VERSION = '6.1';
const SWIFT_RELEASE = `swift-${SWIFT_VERSION}-RELEASE`;
const SWIFT_INSTALL_DIR = resolve(HOME, '.local/swift');

function run(
  cmd: string,
  options?: {ignoreError?: boolean; timeout?: number},
): string {
  try {
    return execSync(cmd, {
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
  console.log(`[setup-env-swift] ${msg}`);
}

function warn(msg: string): void {
  console.warn(`[setup-env-swift] ⚠ ${msg}`);
}

function commandExists(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, {stdio: 'pipe'});
    return true;
  } catch {
    return false;
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

function getSwiftBinDir(): string {
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

function main(): void {
  if (process.env.CLAUDE_CODE_REMOTE !== 'true') {
    if (!commandExists('swift')) {
      warn(
        'Swift is not installed. Install from https://www.swift.org/install/ or via Xcode.',
      );
    }
    return;
  }

  if (commandExists('swift')) {
    const version = run('swift --version', {ignoreError: true});
    if (version) {
      log(`Swift already installed: ${version.split('\n')[0]}`);
      return;
    }
  }

  const swiftBinDir = getSwiftBinDir();
  if (existsSync(resolve(swiftBinDir, 'swift'))) {
    log(`Swift already downloaded at ${swiftBinDir}`);
    addToPath(swiftBinDir);
    return;
  }

  log(`Installing Swift ${SWIFT_VERSION} for Linux...`);

  const arch = run('uname -m');
  const archSuffix = arch === 'aarch64' ? '-aarch64' : '';

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

  log(`Downloading from ${url}...`);
  run(`curl -sL "${url}" -o "${tmpTarball}"`, {timeout: 600_000});

  log('Extracting...');
  run(`mkdir -p "${SWIFT_INSTALL_DIR}"`);
  run(
    `tar xzf "${tmpTarball}" --strip-components=1 -C "${SWIFT_INSTALL_DIR}"`,
    {timeout: 300_000},
  );
  run(`rm -f "${tmpTarball}"`, {ignoreError: true});

  const binDir = resolve(SWIFT_INSTALL_DIR, 'usr/bin');
  addToPath(binDir);

  const version = run(`"${resolve(binDir, 'swift')}" --version`, {
    ignoreError: true,
  });
  if (version) {
    log(`Swift installed: ${version.split('\n')[0]}`);
  } else {
    warn('Swift installation may have failed — swift --version returned empty');
  }
}

main();
