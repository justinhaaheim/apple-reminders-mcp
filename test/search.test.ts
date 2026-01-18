/**
 * Search operation tests for the Apple Reminders MCP server.
 * Tests search_reminders and search_reminder_lists tools.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Search operations', () => {
  let client: MCPClient;
  let testListName: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();

    // Create some test reminders with different properties
    await client.callTool('create_reminders', {
      reminders: [
        {
          title: 'Buy groceries',
          list_name: testListName,
          notes: 'Milk, eggs, bread',
        },
        {
          title: 'Call dentist',
          list_name: testListName,
          due_date: '2026-01-20',
        },
        {
          title: 'Finish report',
          list_name: testListName,
          notes: 'Q4 quarterly report',
          due_date: '2026-01-25',
        },
        {
          title: 'Buy birthday gift',
          list_name: testListName,
        },
      ],
    });
  });

  afterAll(async () => {
    await client.cleanup();
  });

  describe('search_reminders', () => {
    test('searches by text in title', async () => {
      const result = await client.callTool('search_reminders', {
        search_text: 'buy',
        list_name: testListName,
      });

      expect(result.reminders).toBeDefined();
      expect(result.count).toBe(2); // "Buy groceries" and "Buy birthday gift"

      const titles = result.reminders.map((r: {name: string}) => r.name);
      expect(titles).toContain('Buy groceries');
      expect(titles).toContain('Buy birthday gift');
    });

    test('searches by text in notes', async () => {
      const result = await client.callTool('search_reminders', {
        search_text: 'quarterly',
        list_name: testListName,
      });

      expect(result.count).toBe(1);
      expect(result.reminders[0].name).toBe('Finish report');
    });

    test('search is case-insensitive', async () => {
      const result = await client.callTool('search_reminders', {
        search_text: 'GROCERIES',
        list_name: testListName,
      });

      expect(result.count).toBe(1);
      expect(result.reminders[0].name).toBe('Buy groceries');
    });

    test('filters by list_name', async () => {
      const result = await client.callTool('search_reminders', {
        list_name: testListName,
      });

      expect(result.count).toBeGreaterThanOrEqual(4);

      // All results should be from our test list
      for (const reminder of result.reminders) {
        expect(reminder.listName).toBe(testListName);
      }
    });

    test('filters by date range', async () => {
      const result = await client.callTool('search_reminders', {
        list_name: testListName,
        date_from: '2026-01-19',
        date_to: '2026-01-21',
      });

      // Should only get "Call dentist" (due 2026-01-20)
      expect(result.count).toBe(1);
      expect(result.reminders[0].name).toBe('Call dentist');
    });

    test('respects limit parameter', async () => {
      const result = await client.callTool('search_reminders', {
        list_name: testListName,
        limit: 2,
      });

      expect(result.count).toBe(2);
    });

    test('filters completed reminders', async () => {
      // First, complete one reminder
      const searchResult = await client.callTool('search_reminders', {
        search_text: 'dentist',
        list_name: testListName,
      });
      const reminderId = searchResult.reminders[0].id;

      await client.callTool('complete_reminder', {
        reminder_id: reminderId,
      });

      // Search for completed reminders
      const completedResult = await client.callTool('search_reminders', {
        list_name: testListName,
        status: 'completed',
      });

      expect(completedResult.count).toBeGreaterThanOrEqual(1);

      const completedTitles = completedResult.reminders.map(
        (r: {name: string}) => r.name,
      );
      expect(completedTitles).toContain('Call dentist');
    });

    test('returns empty array for no matches', async () => {
      const result = await client.callTool('search_reminders', {
        search_text: 'xyznonexistent123',
        list_name: testListName,
      });

      expect(result.count).toBe(0);
      expect(result.reminders).toEqual([]);
    });

    test('includes listId and listName in results', async () => {
      const result = await client.callTool('search_reminders', {
        list_name: testListName,
        limit: 1,
      });

      expect(result.reminders[0].listId).toBeDefined();
      expect(result.reminders[0].listName).toBe(testListName);
    });
  });

  describe('search_reminder_lists', () => {
    test('returns all lists when no search text', async () => {
      const result = await client.callTool('search_reminder_lists', {});

      expect(result.lists).toBeDefined();
      expect(result.count).toBeGreaterThan(0);
    });

    test('filters lists by search text', async () => {
      const result = await client.callTool('search_reminder_lists', {
        search_text: 'AR-MCP TEST',
      });

      expect(result.count).toBeGreaterThanOrEqual(1);

      // All results should contain the search text
      for (const list of result.lists) {
        expect(list.name.toUpperCase()).toContain('AR-MCP TEST');
      }
    });

    test('search is case-insensitive', async () => {
      const result = await client.callTool('search_reminder_lists', {
        search_text: 'ar-mcp test',
      });

      expect(result.count).toBeGreaterThanOrEqual(1);
    });

    test('returns empty array for no matches', async () => {
      const result = await client.callTool('search_reminder_lists', {
        search_text: 'xyznonexistentlist999',
      });

      expect(result.count).toBe(0);
      expect(result.lists).toEqual([]);
    });

    test('includes id and name for each list', async () => {
      const result = await client.callTool('search_reminder_lists', {});

      for (const list of result.lists) {
        expect(list.id).toBeDefined();
        expect(list.name).toBeDefined();
      }
    });
  });
});
