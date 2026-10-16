/**
 * CLI help-output tests.
 *
 * Regression guard for the HelpSystem flush bug: help content is printed and
 * then the process exits. Using _exit() skipped stdio flushing, so piped/
 * captured help output came back empty (it only "worked" on a TTY). These
 * tests capture stdout over a pipe, so they fail if help is ever swallowed
 * again.
 */

import {describe, test, expect} from 'bun:test';
import {spawn} from 'bun';

const CLI = '.build/release/reminders';

async function help(
  args: string[],
): Promise<{stdout: string; exitCode: number}> {
  const proc = spawn([CLI, ...args], {
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: 'pipe',
  });
  const stdout = await new Response(proc.stdout).text();
  const exitCode = await proc.exited;
  return {stdout, exitCode};
}

describe('CLI help output (piped)', () => {
  test('top-level --help prints', async () => {
    const {stdout, exitCode} = await help(['--help']);
    expect(exitCode).toBe(0);
    expect(stdout.trim().length).toBeGreaterThan(0);
    expect(stdout).toContain('reminders');
  });

  test('create-list --help prints concise help', async () => {
    const {stdout} = await help(['create-list', '--help']);
    expect(stdout).toContain('create-list');
  });

  test('delete-list --help prints concise help', async () => {
    const {stdout} = await help(['delete-list', '--help']);
    expect(stdout).toContain('delete-list');
    expect(stdout).toContain('--force');
  });

  test('delete-list --help --verbose prints verbose help', async () => {
    const {stdout} = await help(['delete-list', '--help', '--verbose']);
    expect(stdout).toContain('cannot be undone');
  });

  test('delete-list --help=skill prints strategic guidance', async () => {
    const {stdout} = await help(['delete-list', '--help=skill']);
    expect(stdout).toContain('Strategic Guidance');
  });
});
