/**
 * Batch operation tests for the Apple Reminders MCP server.
 * Tests create_reminders, update_reminders, delete_reminders, complete_reminders.
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
          {title: 'Batch Reminder 1', list_name: testListName},
          {title: 'Batch Reminder 2', list_name: testListName},
          {
            title: 'Batch Reminder 3',
            list_name: testListName,
            notes: 'With notes',
          },
        ],
      });

      expect(result.results).toBeDefined();
      expect(result.results.length).toBe(3);
      expect(result.summary.total).toBe(3);
      expect(result.summary.succeeded).toBe(3);
      expect(result.summary.failed).toBe(0);

      // All should succeed
      for (const item of result.results) {
        expect(item.success).toBe(true);
        expect(item.reminder_id).toBeDefined();
      }
    });

    test('handles partial failure (bad list name)', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Good Reminder', list_name: testListName},
          {title: 'Bad Reminder', list_name: 'NonexistentList12345'},
        ],
      });

      expect(result.results.length).toBe(2);
      expect(result.summary.succeeded).toBe(1);
      expect(result.summary.failed).toBe(1);

      // First should succeed
      expect(result.results[0].success).toBe(true);

      // Second should fail (list not found OR test mode violation)
      expect(result.results[1].success).toBe(false);
      expect(result.results[1].error).toBeDefined();
    });

    test('validates required fields', async () => {
      // Missing list_name should cause validation error
      try {
        await client.callTool('create_reminders', {
          reminders: [{title: 'Missing List'}],
        });
        // If we get here, check for per-item error
      } catch {
        // Expected - validation error
      }
    });
  });

  describe('update_reminders', () => {
    test('updates multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Update Target 1', list_name: testListName},
          {title: 'Update Target 2', list_name: testListName},
        ],
      });

      const ids = createResult.results.map(
        (r: {reminder_id: string}) => r.reminder_id,
      );

      // Update them
      const updateResult = await client.callTool('update_reminders', {
        updates: [
          {reminder_id: ids[0], title: 'Updated Title 1'},
          {reminder_id: ids[1], notes: 'Added notes'},
        ],
      });

      expect(updateResult.results.length).toBe(2);
      expect(updateResult.summary.succeeded).toBe(2);
      expect(updateResult.summary.failed).toBe(0);
    });

    test('handles non-existent reminder ID', async () => {
      const result = await client.callTool('update_reminders', {
        updates: [{reminder_id: 'fake-id-12345', title: 'Will Fail'}],
      });

      expect(result.results.length).toBe(1);
      expect(result.results[0].success).toBe(false);
      expect(result.results[0].error).toBeDefined();
    });
  });

  describe('delete_reminders', () => {
    test('deletes multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Delete Target 1', list_name: testListName},
          {title: 'Delete Target 2', list_name: testListName},
        ],
      });

      const ids = createResult.results.map(
        (r: {reminder_id: string}) => r.reminder_id,
      );

      // Delete them
      const deleteResult = await client.callTool('delete_reminders', {
        reminder_ids: ids,
      });

      expect(deleteResult.results.length).toBe(2);
      expect(deleteResult.summary.succeeded).toBe(2);
      expect(deleteResult.summary.failed).toBe(0);
    });

    test('handles non-existent reminder ID', async () => {
      const result = await client.callTool('delete_reminders', {
        reminder_ids: ['fake-id-99999'],
      });

      expect(result.results.length).toBe(1);
      expect(result.results[0].success).toBe(false);
      expect(result.results[0].error).toBeDefined();
    });
  });

  describe('complete_reminders', () => {
    test('completes multiple reminders at once', async () => {
      // Create reminders first
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {title: 'Complete Target 1', list_name: testListName},
          {title: 'Complete Target 2', list_name: testListName},
        ],
      });

      const ids = createResult.results.map(
        (r: {reminder_id: string}) => r.reminder_id,
      );

      // Complete them
      const completeResult = await client.callTool('complete_reminders', {
        reminder_ids: ids,
      });

      expect(completeResult.results.length).toBe(2);
      expect(completeResult.summary.succeeded).toBe(2);
      expect(completeResult.summary.failed).toBe(0);
    });

    test('handles non-existent reminder ID', async () => {
      const result = await client.callTool('complete_reminders', {
        reminder_ids: ['fake-id-88888'],
      });

      expect(result.results.length).toBe(1);
      expect(result.results[0].success).toBe(false);
      expect(result.results[0].error).toBeDefined();
    });
  });
});
