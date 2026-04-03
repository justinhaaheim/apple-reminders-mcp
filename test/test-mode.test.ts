/**
 * Tests to verify that test mode restrictions work correctly.
 * These tests verify that the server blocks operations on non-test lists.
 *
 * Uses mock mode WITH test mode enabled, plus a seed file to pre-populate
 * the mock store with reminders in non-test lists. This allows us to test
 * that the test-mode guard actually fires (not just "not found" errors).
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';
import {writeFileSync, unlinkSync} from 'fs';
import {tmpdir} from 'os';
import {join} from 'path';

// Seed data: reminders in a non-test list that test mode should protect
const SEED_DATA = {
  lists: [
    {id: 'seed-list-default', name: 'Reminders', isDefault: true},
    {id: 'seed-list-work', name: 'Work', isDefault: false},
  ],
  reminders: [
    {
      id: 'seed-rem-001',
      title: 'Seeded Reminder A',
      notes: 'In default list',
      listId: 'seed-list-default',
      listName: 'Reminders',
      isCompleted: false,
      priority: 'none',
      dueDate: null,
      dueDateIncludesTime: null,
      completionDate: null,
      createdDate: '2026-01-01T00:00:00Z',
      lastModifiedDate: '2026-01-01T00:00:00Z',
      url: null,
      alarms: null,
      recurrenceRules: null,
    },
    {
      id: 'seed-rem-002',
      title: 'Seeded Reminder B',
      notes: null,
      listId: 'seed-list-work',
      listName: 'Work',
      isCompleted: false,
      priority: 'high',
      dueDate: null,
      dueDateIncludesTime: null,
      completionDate: null,
      createdDate: '2026-01-01T00:00:00Z',
      lastModifiedDate: '2026-01-01T00:00:00Z',
      url: null,
      alarms: null,
      recurrenceRules: null,
    },
  ],
};

const SEED_FILE_PATH = join(tmpdir(), 'test-mode-seed.json');

describe('Test mode restrictions', () => {
  let client: MCPClient;

  beforeAll(async () => {
    // Write seed file
    writeFileSync(SEED_FILE_PATH, JSON.stringify(SEED_DATA));

    // Use mock mode + test mode + seed data
    client = await MCPClient.create({
      mockMode: true,
      testMode: true,
      mockSeedPath: SEED_FILE_PATH,
    });
  });

  afterAll(async () => {
    await client.cleanup();
    try {
      unlinkSync(SEED_FILE_PATH);
    } catch {
      // ignore
    }
  });

  test('blocks creating a list without test prefix', async () => {
    const result = await client.callTool('create_list', {
      name: 'Regular List Name',
    });

    expect(result._isError).toBe(true);
    expect(result.error).toContain('TEST MODE');
    expect(result.error).toContain('[AR-MCP TEST]');
  });

  test('blocks creating a reminder in non-test list', async () => {
    // Try to create a reminder in the default list (without specifying a list)
    // Since test mode blocks writes to non-test lists, this should fail
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'Should Not Be Created'}],
    });

    // Either returns {created:[], failed:[...]} or error
    const hasError =
      result._isError ||
      (result.failed && (result.failed as Array<unknown>).length > 0);
    expect(hasError).toBe(true);
  });

  test('allows creating a list with test prefix', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const result = await client.callTool('create_list', {
      name: `${prefix} - Allowed List`,
    });

    expect(result._isError).toBeUndefined();
    expect(result.id).toBeDefined();
  });

  test('allows creating a reminder in test list', async () => {
    // First create a test list
    const prefix = MCPClient.getTestListPrefix();
    const listName = `${prefix} - For Reminder Test`;

    await client.callTool('create_list', {
      name: listName,
    });

    // Now create a reminder in it
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'Allowed Reminder', list: {name: listName}}],
    });

    expect(Array.isArray(result)).toBe(true);
    const reminders = result as Array<{id: string}>;
    expect(reminders.length).toBe(1);
    expect(reminders[0].id).toBeDefined();

    // Clean up
    await client.callTool('delete_reminders', {
      ids: [reminders[0].id],
    });
  });

  test('blocks updating a reminder in non-test list', async () => {
    // Use the seeded reminder in the "Reminders" (non-test) list
    const result = await client.callTool('update_reminders', {
      reminders: [{id: 'seed-rem-001', title: 'Should Not Work'}],
    });

    const hasError =
      result._isError ||
      (result.failed && (result.failed as Array<unknown>).length > 0);
    expect(hasError).toBe(true);

    // Verify the error is specifically about test mode, not "not found"
    if (result.failed) {
      const failedItems = result.failed as Array<{error: string}>;
      expect(failedItems[0].error).toContain('TEST MODE');
    }
  });

  test('blocks deleting a reminder in non-test list', async () => {
    // Use the seeded reminder in the "Work" (non-test) list
    const result = await client.callTool('delete_reminders', {
      ids: ['seed-rem-002'],
    });

    const hasError =
      result._isError ||
      (result.failed && (result.failed as Array<unknown>).length > 0);
    expect(hasError).toBe(true);

    // Verify the error is specifically about test mode, not "not found"
    if (result.failed) {
      const failedItems = result.failed as Array<{error: string}>;
      expect(failedItems[0].error).toContain('TEST MODE');
    }
  });
});
