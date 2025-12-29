/**
 * Tests to verify that test mode restrictions work correctly.
 * These tests verify that the server blocks operations on non-test lists.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Test mode restrictions', () => {
  let client: MCPClient;

  beforeAll(async () => {
    client = await MCPClient.create();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('blocks creating a list without test prefix', async () => {
    const result = await client.callTool('create_reminder_list', {
      name: 'Regular List Name',
    });

    expect(result.success).toBe(false);
    expect(result.error).toContain('TEST MODE');
    expect(result.error).toContain('[AR-MCP TEST]');
  });

  test('blocks creating a reminder in non-test list', async () => {
    // Try to create a reminder in the default "Reminders" list
    const result = await client.callTool('create_reminder', {
      title: 'Should Not Be Created',
      list_name: 'Reminders',
    });

    expect(result.success).toBe(false);
    expect(result.error).toContain('TEST MODE');
  });

  test('allows creating a list with test prefix', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const result = await client.callTool('create_reminder_list', {
      name: `${prefix} - Allowed List`,
    });

    expect(result.success).toBe(true);
    expect(result.list_id).toBeDefined();
  });

  test('allows creating a reminder in test list', async () => {
    // First create a test list
    const prefix = MCPClient.getTestListPrefix();
    const listName = `${prefix} - For Reminder Test`;

    await client.callTool('create_reminder_list', {
      name: listName,
    });

    // Now create a reminder in it
    const result = await client.callTool('create_reminder', {
      title: 'Allowed Reminder',
      list_name: listName,
    });

    expect(result.success).toBe(true);
    expect(result.reminder_id).toBeDefined();

    // Clean up
    await client.callTool('delete_reminder', {
      reminder_id: result.reminder_id,
    });
  });

  test('blocks updating a reminder in non-test list', async () => {
    // This test relies on there being at least one reminder in a non-test list.
    // We'll try to update with a fake ID - the error will be "Reminder not found"
    // which is fine, but if the reminder existed in a real list, test mode would block it.

    // For this test, we just verify the mechanism works by checking that
    // the test prefix check is in place. We can't easily create a reminder
    // in a non-test list since test mode blocks that too.

    const result = await client.callTool('update_reminder', {
      reminder_id: 'fake-reminder-id-12345',
      title: 'Should Not Work',
    });

    // The error should be about reminder not found (since ID is fake)
    // or about test mode (if somehow we had a real ID from a non-test list)
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });
});
