/**
 * CLI priority tests — proves the CLI and MCP now share one priority
 * contract (Priority.parse): the CLI accepts the same inputs the MCP tool
 * does (low/medium/high, none, Apple integers 0/1/5/9) and fails loudly on
 * anything else. Each invocation uses a fresh mock store and prints the
 * created reminder as JSON.
 */

import {describe, test, expect} from 'bun:test';
import {spawn} from 'bun';

const CLI = '.build/release/reminders';

async function runCLI(
  args: string[],
): Promise<{stdout: string; stderr: string; exitCode: number}> {
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

async function createdPriority(priorityArg: string): Promise<unknown> {
  const {stdout, exitCode} = await runCLI([
    'create',
    '--mock',
    'CLI priority test',
    '--priority',
    priorityArg,
  ]);
  expect(exitCode).toBe(0);
  return (JSON.parse(stdout) as {priority?: string}).priority ?? null;
}

describe('reminders create --priority (CLI/MCP parity)', () => {
  test('accepts the word forms', async () => {
    expect(await createdPriority('high')).toBe('high');
    expect(await createdPriority('medium')).toBe('medium');
    expect(await createdPriority('low')).toBe('low');
  });

  test('accepts Apple integer constants (1/5/9)', async () => {
    expect(await createdPriority('1')).toBe('high');
    expect(await createdPriority('5')).toBe('medium');
    expect(await createdPriority('9')).toBe('low');
  });

  test('accepts "none" and 0 as no priority (canonical null)', async () => {
    expect(await createdPriority('none')).toBeNull();
    expect(await createdPriority('0')).toBeNull();
  });

  test('rejects a bogus priority loudly (exit 1 + stderr message)', async () => {
    const {stderr, exitCode} = await runCLI([
      'create',
      '--mock',
      'Bad',
      '--priority',
      'urgent',
    ]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain('Invalid priority');
  });
});
