/**
 * CLI tests for `reminders delete-list`.
 *
 * Each CLI invocation gets a fresh in-memory mock store seeded with only the
 * default "Reminders" list, so these cover the guard/validation paths that a
 * single invocation can exercise. The happy / force / ambiguous-name paths run
 * through the same RemindersManager.deleteList and are covered by the MCP
 * suite (test/delete-list.test.ts).
 */

import {describe, test, expect} from 'bun:test';
import {spawn} from 'bun';

const CLI = '.build/release/reminders';

interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

async function runCLI(args: string[]): Promise<RunResult> {
  const baseEnv = {...process.env};
  delete baseEnv.AR_MCP_TEST_MODE;
  delete baseEnv.AR_MCP_MOCK_MODE;

  const proc = spawn([CLI, ...args], {
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: 'pipe',
    env: baseEnv,
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  return {stdout, stderr, exitCode};
}

describe('reminders delete-list (mock)', () => {
  test('refuses to delete the default list', async () => {
    const r = await runCLI(['delete-list', '--mock', 'Reminders']);
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain('default list');
  });

  test('errors on a non-existent list name', async () => {
    const r = await runCLI(['delete-list', '--mock', 'No Such List']);
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain('No list found');
  });

  test('requires a selector', async () => {
    const r = await runCLI(['delete-list', '--mock']);
    expect(r.exitCode).not.toBe(0);
    expect(r.stderr).toContain('exactly one');
  });

  test('rejects both a name and --list-id', async () => {
    const r = await runCLI(['delete-list', '--mock', 'X', '--list-id', 'Y']);
    expect(r.exitCode).not.toBe(0);
    expect(r.stderr).toContain('exactly one');
  });
});
