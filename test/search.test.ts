/**
 * Query operation tests for the Apple Reminders MCP server.
 * Tests query_reminders with various filters and JMESPath expressions.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient, extractReminders} from './mcp-client';

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

      // JMESPath returns raw array
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

      // JMESPath returns raw array
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

      const reminders = extractReminders<{listName: string}>(result);
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

      // JMESPath returns raw array
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

      // JMESPath returns raw array
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{priority: string}>;
      // Should have "Finish report" (high) and "Buy birthday gift" (medium)
      expect(reminders.length).toBe(2);

      for (const reminder of reminders) {
        expect(reminder.priority).not.toBe('none');
      }
    });

    test('respects perPage parameter', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 2,
      });

      const reminders = extractReminders(result);
      expect(reminders.length).toBe(2);
    });

    test('filters completed reminders', async () => {
      // First, complete one reminder using JMESPath to find it
      const queryResult = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(title, 'dentist')]",
      });

      // JMESPath returns raw array
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

      const completed = extractReminders<{title: string}>(completedResult);
      expect(completed.length).toBeGreaterThanOrEqual(1);

      const completedTitles = completed.map((r) => r.title);
      expect(completedTitles).toContain('Call dentist');
    });

    test('returns empty array for no matches', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        query: "[?contains(title, 'xyznonexistent123')]",
      });

      // JMESPath returns raw array
      expect(Array.isArray(result)).toBe(true);
      expect((result as Array<unknown>).length).toBe(0);
    });

    test('includes listId and listName in results with full detail', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        outputDetail: 'full',
      });

      const reminders = extractReminders<{
        listId: string;
        listName: string;
      }>(result);
      expect(reminders[0].listId).toBeDefined();
      expect(reminders[0].listName).toBe(testListName);
    });

    test('compact detail omits listName for single-list queries', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        outputDetail: 'compact',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      // listName should be omitted since we queried a single list
      expect(reminders[0].listName).toBeUndefined();
      // But title, id, priority should still be present
      expect(reminders[0].id).toBeDefined();
      expect(reminders[0].title).toBeDefined();
    });

    test('compact detail omits isCompleted for status-specific queries', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        status: 'incomplete',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
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

      const reminders = extractReminders<Record<string, unknown>>(result);
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

      const reminders = extractReminders<Record<string, unknown>>(result);
      expect(reminders.length).toBeGreaterThanOrEqual(1);
      // dueDate should be present and null in full mode
      expect('dueDate' in reminders[0]).toBe(true);
      expect(reminders[0].dueDate).toBeNull();
    });

    test('minimal detail returns only id and title', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        outputDetail: 'minimal',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      expect(reminders[0].id).toBeDefined();
      expect(reminders[0].title).toBeDefined();
      // These should NOT be present in minimal
      expect(reminders[0].notes).toBeUndefined();
      expect(reminders[0].priority).toBeUndefined();
      expect(reminders[0].createdDate).toBeUndefined();
    });

    test('compact includes isCompleted when status is "all"', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        status: 'all',
        outputDetail: 'compact',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      // isCompleted should be present since status is "all" (value isn't implied)
      expect(reminders[0].isCompleted).toBeDefined();
      expect(typeof reminders[0].isCompleted).toBe('boolean');
    });

    test('compact includes listName when searching all lists', async () => {
      const result = await client.callTool('query_reminders', {
        list: {all: true},
        perPage: 1,
        outputDetail: 'compact',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      // listName should be present since we searched all lists
      expect(reminders[0].listName).toBeDefined();
      expect(typeof reminders[0].listName).toBe('string');
    });

    test('JMESPath ignores outputDetail and receives full fields', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        // Even with "minimal", JMESPath should get full fields
        outputDetail: 'minimal',
        query:
          '[*].{id: id, list: listName, created: createdDate, modified: lastModifiedDate}',
      });

      // JMESPath returns raw array
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<Record<string, unknown>>;
      expect(reminders.length).toBeGreaterThan(0);
      // JMESPath should have access to all fields regardless of outputDetail
      expect(reminders[0].id).toBeDefined();
      expect(reminders[0].list).toBeDefined();
      expect(reminders[0].created).toBeDefined();
      expect(reminders[0].modified).toBeDefined();
    });

    test('field names use createdDate and lastModifiedDate', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        outputDetail: 'full',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      // New field names should be present
      expect(reminders[0].createdDate).toBeDefined();
      expect(reminders[0].lastModifiedDate).toBeDefined();
      // Old field names should NOT be present
      expect(reminders[0].creationDate).toBeUndefined();
      expect(reminders[0].modificationDate).toBeUndefined();
    });

    test('default outputDetail (omitted) behaves like compact', async () => {
      // Query without specifying outputDetail
      const defaultResult = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
      });

      // Query with explicit compact
      const compactResult = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 1,
        outputDetail: 'compact',
      });

      const defaultReminders =
        extractReminders<Record<string, unknown>>(defaultResult);
      const compactReminders =
        extractReminders<Record<string, unknown>>(compactResult);

      // Both should have the same set of keys
      const defaultKeys = Object.keys(defaultReminders[0]).sort();
      const compactKeys = Object.keys(compactReminders[0]).sort();
      expect(defaultKeys).toEqual(compactKeys);
    });

    test('full detail includes all expected fields', async () => {
      // Create a reminder with many fields set
      await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Full detail test',
            list: {name: testListName},
            notes: 'test notes',
            dueDate: '2026-06-15T14:00:00-05:00',
            priority: 'high',
            url: 'https://example.com',
          },
        ],
      });

      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'Full detail test',
        outputDetail: 'full',
      });

      const reminders = extractReminders<Record<string, unknown>>(result);
      expect(reminders.length).toBeGreaterThanOrEqual(1);

      const reminder = reminders[0];
      // All fields should be present (some may be null)
      const expectedFields = [
        'id',
        'title',
        'notes',
        'listId',
        'listName',
        'isCompleted',
        'priority',
        'dueDate',
        'dueDateIncludesTime',
        'completionDate',
        'createdDate',
        'lastModifiedDate',
        'url',
        'alarms',
        'recurrenceRules',
      ];
      for (const field of expectedFields) {
        expect(
          field in reminder,
          `Expected field "${field}" to be present`,
        ).toBe(true);
      }
    });

    test('sorts by priority', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        sortBy: 'priority',
        status: 'incomplete',
      });

      const reminders = extractReminders<{priority: string}>(result);

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

      // JMESPath returns raw array
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

    test('response includes pagination metadata', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
      });

      // Verify wrapper structure
      const wrapper = result as {
        reminders: unknown[];
        totalCount: number;
        pageInfo: {
          hasNextPage: boolean;
          endCursor: string | null;
        };
      };
      expect(wrapper.reminders).toBeDefined();
      expect(Array.isArray(wrapper.reminders)).toBe(true);
      expect(typeof wrapper.totalCount).toBe('number');
      expect(wrapper.totalCount).toBeGreaterThanOrEqual(4);
      expect(wrapper.pageInfo).toBeDefined();
      expect(typeof wrapper.pageInfo.hasNextPage).toBe('boolean');
    });

    test('cursor-based page traversal returns all results without overlap', async () => {
      // Page 1: get first 2 results
      const page1 = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 2,
      });

      const wrapper1 = page1 as {
        reminders: Array<{id: string; title: string}>;
        totalCount: number;
        pageInfo: {hasNextPage: boolean; endCursor: string | null};
      };
      expect(wrapper1.reminders.length).toBe(2);
      expect(wrapper1.totalCount).toBeGreaterThanOrEqual(4);
      expect(wrapper1.pageInfo.hasNextPage).toBe(true);
      expect(wrapper1.pageInfo.endCursor).not.toBeNull();

      // Page 2: use endCursor to get next 2
      const page2 = await client.callTool('query_reminders', {
        list: {name: testListName},
        perPage: 2,
        cursor: wrapper1.pageInfo.endCursor,
      });

      const wrapper2 = page2 as {
        reminders: Array<{id: string; title: string}>;
        totalCount: number;
        pageInfo: {hasNextPage: boolean; endCursor: string | null};
      };
      expect(wrapper2.reminders.length).toBeGreaterThanOrEqual(1);
      expect(wrapper2.totalCount).toBe(wrapper1.totalCount);

      // Verify no overlap between pages
      const page1Ids = new Set(wrapper1.reminders.map((r) => r.id));
      for (const r of wrapper2.reminders) {
        expect(page1Ids.has(r.id)).toBe(false);
      }
    });
  });

  describe('per-field date filtering', () => {
    let dateClient: MCPClient;
    const seedListId = 'date-list-default';
    const seedListName = 'Date Range Test List';

    beforeAll(async () => {
      dateClient = await MCPClient.create({mockMode: true, testMode: false});

      // Seed reminders with explicit createdDate / lastModifiedDate / dueDate so we
      // can exercise each per-field flag in isolation without time-of-day flakes.
      // Use a unique list name so it doesn't collide with the mock store's
      // auto-created default "Reminders" list.
      await dateClient.callTool('_seed_mock_data', {
        lists: [{id: seedListId, name: seedListName, isDefault: false}],
        reminders: [
          {
            id: 'date001',
            title: 'Old reminder',
            listId: seedListId,
            createdDate: '2026-01-15T10:00:00Z',
            lastModifiedDate: '2026-01-15T10:00:00Z',
            dueDate: '2026-02-15T10:00:00Z',
          },
          {
            id: 'date002',
            title: 'Mid reminder',
            listId: seedListId,
            createdDate: '2026-03-15T10:00:00Z',
            lastModifiedDate: '2026-04-01T10:00:00Z',
            dueDate: '2026-05-15T10:00:00Z',
          },
          {
            id: 'date003',
            title: 'New reminder Meeting',
            listId: seedListId,
            createdDate: '2026-05-01T10:00:00Z',
            lastModifiedDate: '2026-05-01T10:00:00Z',
            dueDate: '2026-08-15T10:00:00Z',
          },
          {
            id: 'date004',
            title: 'No due date reminder',
            listId: seedListId,
            createdDate: '2026-04-01T10:00:00Z',
            lastModifiedDate: '2026-04-01T10:00:00Z',
          },
        ],
      });
    });

    afterAll(async () => {
      await dateClient.cleanup();
    });

    test('createdFrom filters by createdDate', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        createdFrom: '2026-04-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      // 003 (May) and 004 (April) qualify; 001 (Jan) and 002 (Mar) do not.
      expect(ids).toEqual(['date003', 'date004']);
    });

    test('createdTo filters by createdDate upper bound', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        createdTo: '2026-02-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      expect(ids).toEqual(['date001']);
    });

    test('modifiedFrom filters by lastModifiedDate (not createdDate)', async () => {
      // Reminder 002 has createdDate=2026-03-15 but lastModifiedDate=2026-04-01.
      // A modifiedFrom of 2026-04-01 must include 002 even though its created date
      // is earlier — proves we filter on the right field. 003 (modified May) and
      // 004 (modified April) also qualify; only 001 (modified January) does not.
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        modifiedFrom: '2026-04-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      expect(ids).toEqual(['date002', 'date003', 'date004']);
    });

    test('modifiedTo filters by lastModifiedDate upper bound', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        modifiedTo: '2026-03-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      expect(ids).toEqual(['date001']);
    });

    test('dueFrom filters by dueDate, excluding reminders without one', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        status: 'all',
        dueFrom: '2026-04-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      // 002 (May), 003 (Aug). 001 (Feb) is too early. 004 has no due date.
      expect(ids).toEqual(['date002', 'date003']);
    });

    test('dueTo filters by dueDate upper bound', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        status: 'all',
        dueTo: '2026-03-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      expect(ids).toEqual(['date001']);
    });

    test('combining flags narrows the result intersectively', async () => {
      const result = await dateClient.callTool('query_reminders', {
        list: {name: seedListName},
        status: 'all',
        createdFrom: '2026-03-01',
        dueTo: '2026-06-01',
      });
      const reminders = extractReminders<{id: string}>(result);
      const ids = reminders.map((r) => r.id).sort();
      // 002: created Mar 15, due May 15 → matches both. 003: created May 1, due Aug 15 → fails dueTo.
      expect(ids).toEqual(['date002']);
    });
  });

  describe('positional JMESPath via the `query` field', () => {
    let qClient: MCPClient;
    const seedListId = 'q-list-default';
    const seedListName = 'JMES Test List';

    beforeAll(async () => {
      qClient = await MCPClient.create({mockMode: true, testMode: false});
      await qClient.callTool('_seed_mock_data', {
        lists: [{id: seedListId, name: seedListName, isDefault: false}],
        reminders: [
          {
            id: 'q-1',
            title: 'Team Meeting today',
            listId: seedListId,
            priority: 'high',
          },
          {id: 'q-2', title: 'BUY MILK', listId: seedListId, priority: 'low'},
          {
            id: 'q-3',
            title: 'plain task',
            listId: seedListId,
            priority: 'none',
          },
        ],
      });
    });

    afterAll(async () => {
      await qClient.cleanup();
    });

    test('query field accepts a JMESPath filter expression', async () => {
      const result = await qClient.callTool('query_reminders', {
        list: {name: seedListName},
        query: "[?priority == 'high']",
      });
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{id: string}>;
      expect(reminders.map((r) => r.id)).toEqual(['q-1']);
    });

    test('lower() makes contains() case-insensitive', async () => {
      const result = await qClient.callTool('query_reminders', {
        list: {name: seedListName},
        query: "[?contains(lower(title), 'meeting')]",
      });
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{id: string}>;
      expect(reminders.map((r) => r.id)).toEqual(['q-1']);
    });

    test('upper() makes uppercase comparisons trivial', async () => {
      const result = await qClient.callTool('query_reminders', {
        list: {name: seedListName},
        query: "[?contains(upper(title), 'MILK')]",
      });
      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{id: string}>;
      expect(reminders.map((r) => r.id)).toEqual(['q-2']);
    });

    test('CLI flags + JMESPath compose: flags filter first, JMESPath second', async () => {
      // Flags narrow to a single list (no-op here since there is only one), then
      // JMESPath picks high priority. Same flags + same expression must always
      // produce the same result, regardless of which is "specified first".
      const result = await qClient.callTool('query_reminders', {
        list: {name: seedListName},
        query: "[?priority == 'high' || priority == 'low'].id",
      });
      expect(Array.isArray(result)).toBe(true);
      const ids = result as string[];
      expect(ids.sort()).toEqual(['q-1', 'q-2']);
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
