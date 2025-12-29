/**
 * CRUD tests for the Apple Reminders MCP server.
 * All operations are isolated to a unique test list.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('CRUD operations (isolated to test list)', () => {
  let client: MCPClient;
  let testListName: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('creates a reminder in test list', async () => {
    const result = await client.callTool('create_reminder', {
      title: 'Test Reminder 1',
      list_name: testListName,
    });

    expect(result.success).toBe(true);
    expect(result.reminder_id).toBeDefined();
    expect(result.title).toBe('Test Reminder 1');
  });

  test('creates a reminder with notes and due date', async () => {
    const result = await client.callTool('create_reminder', {
      title: 'Test Reminder with Details',
      list_name: testListName,
      notes: 'These are test notes',
      due_date: '2025-12-31',
    });

    expect(result.success).toBe(true);
    expect(result.reminder_id).toBeDefined();
  });

  test('lists reminders in test list', async () => {
    // Create a reminder first
    await client.callTool('create_reminder', {
      title: 'Reminder for List Test',
      list_name: testListName,
    });

    const result = await client.callTool('list_reminders', {
      list_name: testListName,
      completed: false,
    });

    expect(result.reminders).toBeDefined();
    expect(Array.isArray(result.reminders)).toBe(true);
    expect(result.count).toBeGreaterThan(0);
  });

  test('updates a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminder', {
      title: 'Original Title',
      list_name: testListName,
    });

    expect(createResult.success).toBe(true);
    const reminderId = createResult.reminder_id as string;

    // Update it
    const updateResult = await client.callTool('update_reminder', {
      reminder_id: reminderId,
      title: 'Updated Title',
      notes: 'Added notes',
      priority: '5',
    });

    expect(updateResult.success).toBe(true);
  });

  test('completes a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminder', {
      title: 'To Be Completed',
      list_name: testListName,
    });

    expect(createResult.success).toBe(true);
    const reminderId = createResult.reminder_id as string;

    // Complete it
    const completeResult = await client.callTool('complete_reminder', {
      reminder_id: reminderId,
    });

    expect(completeResult.success).toBe(true);
  });

  test('deletes a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminder', {
      title: 'To Be Deleted',
      list_name: testListName,
    });

    expect(createResult.success).toBe(true);
    const reminderId = createResult.reminder_id as string;

    // Delete it
    const deleteResult = await client.callTool('delete_reminder', {
      reminder_id: reminderId,
    });

    expect(deleteResult.success).toBe(true);
  });

  test('creates a test list with proper prefix', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const result = await client.callTool('create_reminder_list', {
      name: `${prefix} - Another Test List`,
    });

    expect(result.success).toBe(true);
    expect(result.list_id).toBeDefined();
  });
});
