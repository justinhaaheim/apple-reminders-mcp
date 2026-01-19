/**
 * Batch operation tests for the Apple Reminders MCP server.
 * Tests create_reminders, update_reminders, delete_reminders.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Batch operations', () => {
  let client: MCPClient;
  let testListName: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  describe('create_reminders', () => {
    test('creates multiple reminders at once', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Batch Reminder 1', list: {name: testListName}},
          {title: 'Batch Reminder 2', list: {name: testListName}},
          {
            title: 'Batch Reminder 3',
            list: {name: testListName},
            notes: 'With notes',
          },
        ],
      });

      // Success returns array of reminders
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{id: string; title: string}>;
      expect(reminders.length).toBe(3);

      for (const reminder of reminders) {
        expect(reminder.id).toBeDefined();
        expect(reminder.title).toBeDefined();
      }
    });

    test('handles partial failure (bad list name)', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Good Reminder', list: {name: testListName}},
          {title: 'Bad Reminder', list: {name: 'NonexistentList12345'}},
        ],
      });

      // Partial failure returns {created, failed}
      expect(result.created).toBeDefined();
      expect(result.failed).toBeDefined();
      expect(Array.isArray(result.created)).toBe(true);
      expect(Array.isArray(result.failed)).toBe(true);
      expect(result.created.length).toBe(1);
      expect(result.failed.length).toBe(1);

      // Check the failure details
      const failure = result.failed[0] as {index: number; error: string};
      expect(failure.index).toBe(1);
      expect(failure.error).toBeDefined();
    });

    test('validates required fields', async () => {
      // Missing title should cause error
      const result = await client.callTool('create_reminders', {
        reminders: [{list: {name: testListName}}],
      });

      expect(result._isError).toBe(true);
      expect(result.error).toContain('title');
    });
  });

  describe('update_reminders', () => {
    test('updates multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Update Target 1', list: {name: testListName}},
          {title: 'Update Target 2', list: {name: testListName}},
        ],
      });

      expect(Array.isArray(createResult)).toBe(true);
      const created = createResult as Array<{id: string}>;
      const ids = created.map((r) => r.id);

      // Update them
      const updateResult = await client.callTool('update_reminders', {
        reminders: [
          {id: ids[0], title: 'Updated Title 1'},
          {id: ids[1], notes: 'Added notes'},
        ],
      });

      expect(Array.isArray(updateResult)).toBe(true);
      const updated = updateResult as Array<{id: string}>;
      expect(updated.length).toBe(2);
    });

    test('handles non-existent reminder ID', async () => {
      const result = await client.callTool('update_reminders', {
        reminders: [{id: 'fake-id-12345', title: 'Will Fail'}],
      });

      // Partial failure returns {updated, failed}
      expect(result.updated).toBeDefined();
      expect(result.failed).toBeDefined();
      expect(result.updated.length).toBe(0);
      expect(result.failed.length).toBe(1);

      const failure = result.failed[0] as {id: string; error: string};
      expect(failure.id).toBe('fake-id-12345');
      expect(failure.error).toContain('not found');
    });
  });

  describe('delete_reminders', () => {
    test('deletes multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Delete Target 1', list: {name: testListName}},
          {title: 'Delete Target 2', list: {name: testListName}},
        ],
      });

      expect(Array.isArray(createResult)).toBe(true);
      const created = createResult as Array<{id: string}>;
      const ids = created.map((r) => r.id);

      // Delete them
      const deleteResult = await client.callTool('delete_reminders', {
        ids,
      });

      expect(deleteResult.deleted).toBeDefined();
      expect(deleteResult.failed).toBeDefined();
      expect(deleteResult.deleted.length).toBe(2);
      expect(deleteResult.failed.length).toBe(0);
    });

    test('handles non-existent reminder ID', async () => {
      const result = await client.callTool('delete_reminders', {
        ids: ['fake-id-99999'],
      });

      expect(result.deleted.length).toBe(0);
      expect(result.failed.length).toBe(1);

      const failure = result.failed[0] as {id: string; error: string};
      expect(failure.id).toBe('fake-id-99999');
      expect(failure.error).toContain('not found');
    });
  });

  describe('complete via update_reminders', () => {
    test('completes multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Complete Target 1', list: {name: testListName}},
          {title: 'Complete Target 2', list: {name: testListName}},
        ],
      });

      expect(Array.isArray(createResult)).toBe(true);
      const created = createResult as Array<{id: string}>;
      const ids = created.map((r) => r.id);

      // Complete them using update_reminders
      const completeResult = await client.callTool('update_reminders', {
        reminders: ids.map((id) => ({id, completed: true})),
      });

      expect(Array.isArray(completeResult)).toBe(true);
      const completed = completeResult as Array<{
        id: string;
        isCompleted: boolean;
      }>;
      expect(completed.length).toBe(2);

      for (const reminder of completed) {
        expect(reminder.isCompleted).toBe(true);
      }
    });

    test('handles non-existent reminder ID for completion', async () => {
      const result = await client.callTool('update_reminders', {
        reminders: [{id: 'fake-id-88888', completed: true}],
      });

      expect(result.updated.length).toBe(0);
      expect(result.failed.length).toBe(1);

      const failure = result.failed[0] as {id: string; error: string};
      expect(failure.error).toContain('not found');
    });
  });
});
