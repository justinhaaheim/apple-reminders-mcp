/**
 * Query operation tests for the Apple Reminders MCP server.
 * Tests query_reminders with various filters and JMESPath expressions.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Query operations', () => {
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
          list: {name: testListName},
          notes: 'Milk, eggs, bread',
        },
        {
          title: 'Call dentist',
          list: {name: testListName},
          dueDate: '2026-01-20T10:00:00-05:00',
        },
        {
          title: 'Finish report',
          list: {name: testListName},
          notes: 'Q4 quarterly report',
          dueDate: '2026-01-25T10:00:00-05:00',
          priority: 'high',
        },
        {
          title: 'Buy birthday gift',
          list: {name: testListName},
          priority: 'medium',
        },
      ],
    });
  });

  afterAll(async () => {
    await client.cleanup();
  });

  describe('query_reminders', () => {
    test('searches by text in title using JMESPath', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(title, 'Buy')]",
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      expect(reminders.length).toBe(2); // "Buy groceries" and "Buy birthday gift"

      const titles = reminders.map((r) => r.title);
      expect(titles).toContain('Buy groceries');
      expect(titles).toContain('Buy birthday gift');
    });

    test('searches by text in notes using JMESPath', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(notes || '', 'quarterly')]",
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      expect(reminders.length).toBe(1);
      expect(reminders[0].title).toBe('Finish report');
    });

    test('filters by list name', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        outputDetail: 'full',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{listName: string}>;
      expect(reminders.length).toBeGreaterThanOrEqual(4);

      // All results should be from our test list
      for (const reminder of reminders) {
        expect(reminder.listName).toBe(testListName);
      }
    });

    test('filters by priority using JMESPath', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?priority == 'high']",
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string; priority: string}>;
      expect(reminders.length).toBe(1);
      expect(reminders[0].title).toBe('Finish report');
      expect(reminders[0].priority).toBe('high');
    });

    test('filters reminders with any priority set', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?priority != 'none']",
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{priority: string}>;
      // Should have "Finish report" (high) and "Buy birthday gift" (medium)
      expect(reminders.length).toBe(2);

      for (const reminder of reminders) {
        expect(reminder.priority).not.toBe('none');
      }
    });

    test('respects limit parameter', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        limit: 2,
      });

      expect(Array.isArray(result)).toBe(true);
      expect((result as Array<unknown>).length).toBe(2);
    });

    test('filters completed reminders', async () => {
      // First, complete one reminder
      const queryResult = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(title, 'dentist')]",
      });

      expect(Array.isArray(queryResult)).toBe(true);
      const found = queryResult as Array<{id: string}>;
      const reminderId = found[0].id;

      // Complete it
      await client.callTool('update_reminders', {
        reminders: [{id: reminderId, completed: true}],
      });

      // Search for completed reminders
      const completedResult = await client.callTool('query_reminders', {
        list: {name: testListName},
        status: 'completed',
      });

      expect(Array.isArray(completedResult)).toBe(true);
      const completed = completedResult as Array<{title: string}>;
      expect(completed.length).toBeGreaterThanOrEqual(1);

      const completedTitles = completed.map((r) => r.title);
      expect(completedTitles).toContain('Call dentist');
    });

    test('returns empty array for no matches', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(title, 'xyznonexistent123')]",
      });

      expect(Array.isArray(result)).toBe(true);
      expect((result as Array<unknown>).length).toBe(0);
    });

    test('includes listId and listName in results with full detail', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        limit: 1,
        outputDetail: 'full',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{listId: string; listName: string}>;
      expect(reminders[0].listId).toBeDefined();
      expect(reminders[0].listName).toBe(testListName);
    });

    test('compact detail omits listName for single-list queries', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        limit: 1,
        outputDetail: 'compact',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      // listName should be omitted since we queried a single list
      expect(reminders[0].listName).toBeUndefined();
      // But title, id, priority should still be present
      expect(reminders[0].id).toBeDefined();
      expect(reminders[0].title).toBeDefined();
    });

    test('compact detail omits isCompleted for status-specific queries', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        limit: 1,
        status: 'incomplete',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      // isCompleted should be omitted since we queried incomplete
      expect(reminders[0].isCompleted).toBeUndefined();
    });

    test('compact detail omits null fields', async () => {
      // Create a reminder without a due date
      await client.callTool('create_reminders', {
        reminders: [
          {title: 'No Due Date Compact Test', list: {name: testListName}},
        ],
      });

      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'No Due Date Compact Test',
        outputDetail: 'compact',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      expect(reminders.length).toBeGreaterThanOrEqual(1);
      // dueDate should be omitted (not present) since it's null and compact strips nulls
      expect(reminders[0].dueDate).toBeUndefined();
    });

    test('full detail includes null fields explicitly', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'No Due Date Compact Test',
        outputDetail: 'full',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      expect(reminders.length).toBeGreaterThanOrEqual(1);
      // dueDate should be present and null in full mode
      expect('dueDate' in reminders[0]).toBe(true);
      expect(reminders[0].dueDate).toBeNull();
    });

    test('minimal detail returns only id and title', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        limit: 1,
        outputDetail: 'minimal',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      expect(reminders[0].id).toBeDefined();
      expect(reminders[0].title).toBeDefined();
      // These should NOT be present in minimal
      expect(reminders[0].notes).toBeUndefined();
      expect(reminders[0].priority).toBeUndefined();
      expect(reminders[0].createdDate).toBeUndefined();
    });

    test('sorts by priority', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        sortBy: 'priority',
        status: 'incomplete',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{priority: string}>;

      // High priority should come first
      if (reminders.length > 0 && reminders[0].priority !== 'none') {
        // First non-none priority should be high
        const priorities = reminders.map((r) => r.priority);
        const highIndex = priorities.indexOf('high');
        const mediumIndex = priorities.indexOf('medium');
        const lowIndex = priorities.indexOf('low');

        if (highIndex !== -1 && mediumIndex !== -1) {
          expect(highIndex).toBeLessThan(mediumIndex);
        }
        if (mediumIndex !== -1 && lowIndex !== -1) {
          expect(mediumIndex).toBeLessThan(lowIndex);
        }
      }
    });

    test('projects fields using JMESPath', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: '[*].{name: title, due: dueDate}',
      });

      expect(Array.isArray(result)).toBe(true);
      const projected = result as Array<{name: string; due: string | null}>;
      expect(projected.length).toBeGreaterThan(0);

      // Should only have name and due fields
      for (const item of projected) {
        expect(item.name).toBeDefined();
        // due may be null for reminders without due date
        expect('due' in item).toBe(true);
      }
    });
  });

  describe('get_lists', () => {
    test('returns all lists', async () => {
      const result = await client.callTool('get_lists', {});

      expect(Array.isArray(result)).toBe(true);
      const lists = result as Array<{
        id: string;
        name: string;
        isDefault: boolean;
      }>;
      expect(lists.length).toBeGreaterThan(0);
    });

    test('includes id, name, and isDefault for each list', async () => {
      const result = await client.callTool('get_lists', {});

      expect(Array.isArray(result)).toBe(true);
      const lists = result as Array<{
        id: string;
        name: string;
        isDefault: boolean;
      }>;

      for (const list of lists) {
        expect(list.id).toBeDefined();
        expect(list.name).toBeDefined();
        expect(typeof list.isDefault).toBe('boolean');
      }
    });

    test('exactly one list is marked as default', async () => {
      const result = await client.callTool('get_lists', {});

      expect(Array.isArray(result)).toBe(true);
      const lists = result as Array<{isDefault: boolean}>;
      const defaultLists = lists.filter((l) => l.isDefault);
      expect(defaultLists.length).toBe(1);
    });
  });
});
