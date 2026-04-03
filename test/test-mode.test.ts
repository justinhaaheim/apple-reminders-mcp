/**
 * Tests to verify that test mode restrictions work correctly.
 * These tests verify that the server blocks operations on non-test lists.
 *
 * Note: These tests use mock mode WITH test mode enabled to test the
 * test mode restrictions logic.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Test mode restrictions', () => {
  let client: MCPClient;

  beforeAll(async () => {
    // Use mock mode but WITH test mode enabled to test restrictions
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

  test('blocks updating a reminder to move it to non-test list', async () => {
    // Create a reminder in a test list (allowed)
    const prefix = MCPClient.getTestListPrefix();
    const testListName = `${prefix} - Update Guard Test`;

    await client.callTool('create_list', {name: testListName});

    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'Guard Test Reminder', list: {name: testListName}}],
    });

    const reminders = createResult as Array<{id: string}>;
    expect(reminders.length).toBe(1);
    const reminderId = reminders[0].id;

    // Now try to move it to the default (non-test) list — should be blocked
    const result = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, list: {name: 'Reminders'}}],
    });

    const hasError =
      result._isError ||
      (result.failed && (result.failed as Array<unknown>).length > 0);
    expect(hasError).toBe(true);

    // Verify the error is specifically about test mode
    if (result.failed) {
      const failedItems = result.failed as Array<{error: string}>;
      expect(failedItems[0].error).toContain('TEST MODE');
    }
  });
});
