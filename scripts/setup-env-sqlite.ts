#!/usr/bin/env bun
/**
 * setup-env-sqlite.ts — Install libsqlite3-dev in remote (Linux) environments.
 *
 * Called automatically by setup-env.ts via the `setup-env:sqlite` package.json
 * script. Only acts in remote (Linux) environments — on macOS, sqlite3 ships
 * with the OS and the headers come with the Command Line Tools.
 *
 * Idempotent: skips install if pkg-config can already locate sqlite3 (i.e. the
 * dev headers are present). Falls through silently when apt-get isn't
 * available, so it's safe to run on any host.
 */

import {execSync} from 'child_process';

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
  console.log(`[setup-env-sqlite] ${msg}`);
}

function warn(msg: string): void {
  console.warn(`[setup-env-sqlite] ⚠ ${msg}`);
}

function commandExists(cmd: string): boolean {
  try {
    execSync(`command -v ${cmd}`, {stdio: 'pipe'});
    return true;
  } catch {
    return false;
  }
}

function sqliteDevAvailable(): boolean {
  try {
    execSync('pkg-config --exists sqlite3', {stdio: 'pipe'});
    return true;
  } catch {
    return false;
  }
}

function main(): void {
  if (process.env.CLAUDE_CODE_REMOTE !== 'true') {
    if (!commandExists('sqlite3')) {
      warn('sqlite3 not found. macOS ships with sqlite3 — this is unexpected.');
    }
    return;
  }

  if (sqliteDevAvailable()) {
    const version = run('pkg-config --modversion sqlite3', {ignoreError: true});
    log(`libsqlite3-dev already available (sqlite3 ${version}).`);
    return;
  }

  if (!commandExists('apt-get')) {
    warn(
      'apt-get not available — cannot auto-install libsqlite3-dev. Install sqlite3 and its dev headers manually if you need SQLite C interop.',
    );
    return;
  }

  log('Installing sqlite3 + libsqlite3-dev via apt-get...');
  run('apt-get update', {ignoreError: true, timeout: 300_000});
  run('apt-get install -y sqlite3 libsqlite3-dev pkg-config', {
    timeout: 300_000,
  });

  if (sqliteDevAvailable()) {
    const version = run('pkg-config --modversion sqlite3', {ignoreError: true});
    log(`Installed: sqlite3 ${version}`);
  } else {
    warn(
      'Install completed but pkg-config still cannot find sqlite3. Inspect output above.',
    );
  }
}

main();
