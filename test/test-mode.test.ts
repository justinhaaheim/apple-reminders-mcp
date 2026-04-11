/**
 * Tests to verify that test mode restrictions work correctly at the MCP
 * protocol layer.
 *
 * The deep test-mode guard coverage lives in the Swift unit tests
 * (Tests/AppleRemindersCoreTests/TestModeGuardTests.swift), which exercise
 * RemindersManager directly with MockReminderStore. These TypeScript tests
 * only verify the end-to-end happy paths and a few error paths that don't
 * require pre-seeding the mock store with reminders in non-test lists.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Test mode restrictions', () => {
  let client: MCPClient;

  beforeAll(async () => {
    client = await MCPClient.create({
      mockMode: true,
      testMode: true,
    });
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('blocks creating a list without test prefix', async () => {
    const result = await client.callTool('create_list', {
      name: 'Regular List Name',
    });

    expect(result._isError).toBe(true);
    expect(result.error).toContain('TEST MODE');
    expect(result.error).toContain('[AR-MCP TEST]');
  });

  test('blocks creating a reminder in the default (non-test) list', async () => {
    // In mock mode, the default list is "Reminders" — not test-prefixed.
    // Omitting `list` should route to the default and hit the test-mode guard.
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'Should Not Be Created'}],
    });

    const hasError =
      result._isError ||
      (result.failed && (result.failed as Array<unknown>).length > 0);
    expect(hasError).toBe(true);

    if (result.failed) {
      const failedItems = result.failed as Array<{error: string}>;
      expect(failedItems[0].error).toContain('TEST MODE');
    }
  });

  test('allows creating a list with test prefix', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const result = await client.callTool('create_list', {
      name: `${prefix} - Allowed List`,
    });

    expect(result._isError).toBeUndefined();
    expect(result.id).toBeDefined();
  });

  test('allows full CRUD lifecycle inside a test-prefixed list', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const listName = `${prefix} - CRUD Lifecycle`;

    // 1. Create the list
    const listResult = await client.callTool('create_list', {name: listName});
    expect(listResult._isError).toBeUndefined();
    expect(listResult.id).toBeDefined();

    // 2. Create a reminder in it
    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'Allowed Reminder', list: {name: listName}}],
    });
    expect(Array.isArray(createResult)).toBe(true);
    const created = createResult as Array<{id: string}>;
    expect(created.length).toBe(1);
    const reminderId = created[0].id;
    expect(reminderId).toBeDefined();

    // 3. Update it
    const updateResult = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, title: 'Updated Reminder'}],
    });
    expect(updateResult._isError).toBeUndefined();

    // 4. Delete it
    const deleteResult = await client.callTool('delete_reminders', {
      ids: [reminderId],
    });
    expect(deleteResult._isError).toBeUndefined();
  });
});
