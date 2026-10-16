/**
 * CRUD tests for the Apple Reminders MCP server.
 * All operations are isolated to a unique test list.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient, extractReminders} from './mcp-client';

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
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'Test Reminder 1', list: {name: testListName}}],
    });

    // New API returns array of created reminders
    expect(Array.isArray(result)).toBe(true);
    const reminders = result as Array<{id: string; title: string}>;
    expect(reminders.length).toBe(1);
    expect(reminders[0].id).toBeDefined();
    expect(reminders[0].title).toBe('Test Reminder 1');
  });

  test('creates a reminder with notes and due date', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [
        {
          title: 'Test Reminder with Details',
          list: {name: testListName},
          notes: 'These are test notes',
          dueDate: '2025-12-31T10:00:00-05:00',
        },
      ],
    });

    expect(Array.isArray(result)).toBe(true);
    const reminders = result as Array<{
      id: string;
      notes: string;
      dueDate: string;
    }>;
    expect(reminders.length).toBe(1);
    expect(reminders[0].id).toBeDefined();
    expect(reminders[0].notes).toBe('These are test notes');
    expect(reminders[0].dueDate).toBeDefined();
  });

  test('queries reminders in test list', async () => {
    // Create a reminder first
    await client.callTool('create_reminders', {
      reminders: [
        {title: 'Reminder for Query Test', list: {name: testListName}},
      ],
    });

    const result = await client.callTool('query_reminders', {
      list: {name: testListName},
      // default is incomplete-only
    });

    const reminders = extractReminders<{id: string; title: string}>(result);
    expect(reminders.length).toBeGreaterThan(0);
  });

  test('updates a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'Original Title', list: {name: testListName}}],
    });

    expect(Array.isArray(createResult)).toBe(true);
    const created = createResult as Array<{id: string}>;
    const reminderId = created[0].id;

    // Update it
    const updateResult = await client.callTool('update_reminders', {
      reminders: [
        {
          id: reminderId,
          title: 'Updated Title',
          notes: 'Added notes',
          priority: 'medium',
        },
      ],
    });

    expect(Array.isArray(updateResult)).toBe(true);
    const updated = updateResult as Array<{
      id: string;
      title: string;
      priority: string;
    }>;
    expect(updated.length).toBe(1);
    expect(updated[0].title).toBe('Updated Title');
    expect(updated[0].priority).toBe('medium');
  });

  test('accepts Apple native integer priority on create (1 → high)', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [
        {
          title: 'Numeric priority create',
          list: {name: testListName},
          priority: 1,
        },
      ],
    });

    expect(Array.isArray(result)).toBe(true);
    const reminders = result as Array<{id: string; priority: string}>;
    expect(reminders[0].priority).toBe('high');
  });

  test('accepts and clears integer priority on update (5 → medium, 0 → none)', async () => {
    const createResult = await client.callTool('create_reminders', {
      reminders: [
        {title: 'Numeric priority update', list: {name: testListName}},
      ],
    });
    const reminderId = (createResult as Array<{id: string}>)[0].id;

    const toMedium = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, priority: 5}],
    });
    expect((toMedium as Array<{priority: string}>)[0].priority).toBe('medium');

    // Integer 0 clears the priority (same as null).
    const cleared = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, priority: 0}],
    });
    expect((cleared as Array<{priority?: string}>)[0].priority).toBeUndefined();
  });

  test('accepts "none" on create and canonicalizes to no priority', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [
        {title: 'None priority', list: {name: testListName}, priority: 'none'},
      ],
    });

    expect(Array.isArray(result)).toBe(true);
    // "none" is accepted as input but canonicalizes to no-priority (null/omitted).
    expect((result as Array<{priority?: string}>)[0].priority).toBeUndefined();
  });

  test('accepts "none" on update to clear an existing priority', async () => {
    const createResult = await client.callTool('create_reminders', {
      reminders: [
        {title: 'None update', list: {name: testListName}, priority: 'high'},
      ],
    });
    const reminderId = (createResult as Array<{id: string}>)[0].id;

    const cleared = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, priority: 'none'}],
    });
    expect((cleared as Array<{priority?: string}>)[0].priority).toBeUndefined();
  });

  test('reports an out-of-range integer priority as a per-item failure', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [
        {title: 'Bad priority', list: {name: testListName}, priority: 2},
      ],
    });

    // Not silent and not a whole-batch abort: invalid values surface in the
    // failed[] array, the same way a bad dueDate or unknown list does.
    const failed = result.failed as Array<{index: number; error: string}>;
    expect(Array.isArray(failed)).toBe(true);
    expect(failed.length).toBe(1);
    expect(failed[0].error).toContain('Invalid priority');
    expect(result.created).toEqual([]);
  });

  test('reports an unknown priority string on update as a per-item failure', async () => {
    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'Bad priority update', list: {name: testListName}}],
    });
    const reminderId = (createResult as Array<{id: string}>)[0].id;

    const result = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, priority: 'urgent'}],
    });

    const failed = result.failed as Array<{id: string; error: string}>;
    expect(Array.isArray(failed)).toBe(true);
    expect(failed[0].error).toContain('Invalid priority');
  });

  test('reports a boolean priority as a per-item failure (no true → 1 coercion)', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [
        {title: 'Bool priority', list: {name: testListName}, priority: true},
      ],
    });

    const failed = result.failed as Array<{index: number; error: string}>;
    expect(Array.isArray(failed)).toBe(true);
    expect(failed[0].error).toContain('Invalid priority');
  });

  test('completes a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'To Be Completed', list: {name: testListName}}],
    });

    expect(Array.isArray(createResult)).toBe(true);
    const created = createResult as Array<{id: string}>;
    const reminderId = created[0].id;

    // Complete it using update_reminders
    const completeResult = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, completed: true}],
    });

    expect(Array.isArray(completeResult)).toBe(true);
    const completed = completeResult as Array<{
      id: string;
      isCompleted: boolean;
    }>;
    expect(completed[0].isCompleted).toBe(true);
  });

  test('deletes a reminder', async () => {
    // Create a reminder
    const createResult = await client.callTool('create_reminders', {
      reminders: [{title: 'To Be Deleted', list: {name: testListName}}],
    });

    expect(Array.isArray(createResult)).toBe(true);
    const created = createResult as Array<{id: string}>;
    const reminderId = created[0].id;

    // Delete it
    const deleteResult = await client.callTool('delete_reminders', {
      ids: [reminderId],
    });

    expect(deleteResult.deleted).toBeDefined();
    expect(Array.isArray(deleteResult.deleted)).toBe(true);
    expect(deleteResult.deleted).toContain(reminderId);
  });

  test('creates a test list with proper prefix', async () => {
    const prefix = MCPClient.getTestListPrefix();
    const result = await client.callTool('create_list', {
      name: `${prefix} - Another Test List`,
    });

    expect(result._isError).toBeUndefined();
    expect(result.id).toBeDefined();
    expect(result.name).toBe(`${prefix} - Another Test List`);
    expect(result.isDefault).toBe(false);
  });
});
