/**
 * CLI auto-snapshot tests.
 *
 * Verifies the AR_SNAPSHOT_ENABLED behavior on the `reminders` CLI binary:
 * - default off (no snapshot output, no repo created)
 * - enabled + fresh repo: pre + post snapshot
 * - enabled + recent commit: post only
 * - enabled + last snapshot > 7 days old: pre + post
 *
 * Tests run against the mock store, with AR_SNAPSHOT_REPO pointed at a tmp
 * directory so they never touch the user's real snapshot repo.
 */

import {describe, test, expect, beforeEach, afterEach} from 'bun:test';
import {spawn} from 'bun';
import {mkdtempSync, rmSync, existsSync} from 'fs';
import {tmpdir} from 'os';
import {join} from 'path';

const CLI = '.build/release/reminders';

interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

async function runCLI(
  args: string[],
  env: Record<string, string> = {},
): Promise<RunResult> {
  // Clear inherited mode env vars so tests behave the same whether the suite
  // was launched with AR_MCP_TEST_MODE=1 or not. We pass --mock explicitly
  // when needed.
  const baseEnv = {...process.env};
  delete baseEnv.AR_MCP_TEST_MODE;
  delete baseEnv.AR_MCP_MOCK_MODE;
  delete baseEnv.AR_SNAPSHOT_ENABLED;
  delete baseEnv.AR_SNAPSHOT_REPO;

  const proc = spawn([CLI, ...args], {
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: 'pipe',
    env: {...baseEnv, ...env},
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  return {stdout, stderr, exitCode};
}

async function gitLog(repoPath: string): Promise<string[]> {
  const proc = spawn(['git', '-C', repoPath, 'log', '--format=%s'], {
    stdout: 'pipe',
    stderr: 'pipe',
  });
  const stdout = await new Response(proc.stdout).text();
  await proc.exited;
  return stdout
    .trim()
    .split('\n')
    .filter((s) => s.length > 0);
}

describe('CLI auto-snapshot (AR_SNAPSHOT_ENABLED)', () => {
  let tmpDir: string;
  let repoPath: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'ar-cli-snap-'));
    repoPath = join(tmpDir, 'repo');
  });

  afterEach(() => {
    rmSync(tmpDir, {recursive: true, force: true});
  });

  test('default (no env var): no snapshot, no repo created', async () => {
    const result = await runCLI(['create-list', '--mock', 'My List']);
    expect(result.exitCode).toBe(0);
    expect(result.stderr).not.toContain('Auto-snapshot');
    expect(existsSync(repoPath)).toBe(false);
  });

  test('enabled + fresh repo: pre + post snapshots', async () => {
    const result = await runCLI(['create-list', '--mock', 'My List'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain('Auto-snapshot (pre create_list)');
    expect(result.stderr).toContain('Auto-snapshot (post create_list)');

    const messages = await gitLog(repoPath);
    // Initial commit + pre + post = 3 commits
    expect(messages).toHaveLength(3);
    expect(messages[0]).toMatch(/^Snapshot /); // most recent (post)
    expect(messages[1]).toMatch(/^Snapshot /); // pre
    expect(messages[2]).toBe('Initial commit'); // oldest
  });

  test('enabled + recent snapshot: post only', async () => {
    // First invocation creates the repo + first pair of snapshots.
    await runCLI(['create-list', '--mock', 'First'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    const before = await gitLog(repoPath);
    const beforeCount = before.length;

    // Second invocation right after — last snapshot is fresh, only post.
    const result = await runCLI(['create-list', '--mock', 'Second'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    expect(result.exitCode).toBe(0);
    expect(result.stderr).not.toContain('Auto-snapshot (pre');
    expect(result.stderr).toContain('Auto-snapshot (post create_list)');

    const after = await gitLog(repoPath);
    expect(after.length).toBe(beforeCount + 1);
  });

  test('enabled + stale repo (last snapshot > 7 days old): pre + post', async () => {
    // Seed the repo
    await runCLI(['create-list', '--mock', 'Initial'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });

    // Back-date HEAD by 8 days via amend with date env vars (fast — no filter-branch).
    const eightDaysAgo = new Date(Date.now() - 8 * 86400 * 1000)
      .toISOString()
      .replace(/\.\d+Z$/, '+00:00');
    const amendProc = spawn(
      [
        'git',
        '-C',
        repoPath,
        'commit',
        '--amend',
        '--no-edit',
        `--date=${eightDaysAgo}`,
      ],
      {
        stdout: 'pipe',
        stderr: 'pipe',
        env: {
          ...process.env,
          GIT_COMMITTER_DATE: eightDaysAgo,
        },
      },
    );
    await amendProc.exited;

    const before = await gitLog(repoPath);
    const beforeCount = before.length;

    const result = await runCLI(['create-list', '--mock', 'Stale Trigger'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain('Auto-snapshot (pre create_list)');
    expect(result.stderr).toContain('Auto-snapshot (post create_list)');

    const after = await gitLog(repoPath);
    expect(after.length).toBe(beforeCount + 2);
  });

  test('first snapshot writes snapshot-state.json with cutoff timestamp', async () => {
    const before = new Date();
    const result = await runCLI(['create-list', '--mock', 'My List'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    const after = new Date();
    expect(result.exitCode).toBe(0);

    const statePath = join(repoPath, 'snapshot-state.json');
    expect(existsSync(statePath)).toBe(true);

    const fileText = await Bun.file(statePath).text();
    const parsed = JSON.parse(fileText);
    expect(parsed.schemaVersion).toBe(2);
    expect(typeof parsed.lastSnapshotAt).toBe('string');

    // Cutoff was captured before fetch — should be at or after `before` and
    // before/equal to the current time after the run finished.
    const cutoff = new Date(parsed.lastSnapshotAt).getTime();
    // Allow 5s slop since the snapshot encloses the time window.
    expect(cutoff).toBeGreaterThanOrEqual(before.getTime() - 5000);
    expect(cutoff).toBeLessThanOrEqual(after.getTime() + 5000);
  });

  test('first snapshot logs mode = full (no previous snapshot state)', async () => {
    const result = await runCLI(['create-list', '--mock', 'My List'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    expect(result.exitCode).toBe(0);
    // The first auto-snapshot of a fresh repo has no prior state.
    expect(result.stderr).toContain('mode = full (no previous snapshot state)');
  });

  test('subsequent snapshot uses incremental mode (list changes no longer force full)', async () => {
    // First invocation creates state file + lists.json with one list.
    await runCLI(['create-list', '--mock', 'First'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });

    // Second invocation creates a different list. With listName no longer
    // embedded in reminder JSON files, list set/name changes don't force a
    // full re-export — mode stays incremental.
    const result = await runCLI(['create-list', '--mock', 'Second'], {
      AR_SNAPSHOT_ENABLED: '1',
      AR_SNAPSHOT_REPO: repoPath,
    });
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain('mode = incremental');
    expect(result.stderr).not.toContain('mode = full');
  });

  test('mutation succeeds even when snapshot fails', async () => {
    // Create the repo dir as a regular directory (no git init), and put a
    // file there that will conflict with .git initialization. We just write
    // a non-directory at the .git path to make `git init` choke.
    // Simpler: pass an unwritable repo path.
    const result = await runCLI(
      ['create-list', '--mock', 'Should Still Work'],
      {
        AR_SNAPSHOT_ENABLED: '1',
        AR_SNAPSHOT_REPO: '/nonexistent-readonly-dir-' + Date.now() + '/repo',
      },
    );
    // Mutation should still succeed; snapshot warns to stderr.
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain('auto-snapshot');
    // The created list JSON should appear on stdout.
    const parsed = JSON.parse(result.stdout);
    expect(parsed.name).toBe('Should Still Work');
  });
});
