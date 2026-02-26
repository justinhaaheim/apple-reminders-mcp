/**
 * API Parity tests for features added to match the Claude iOS Reminders API.
 * Tests: url, dueDateIncludesTime, alarms, recurrence, searchText, dateFrom/dateTo.
 *
 * All operations are isolated to a unique test list using mock mode.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('API Parity features', () => {
  let client: MCPClient;
  let testListName: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  describe('url field', () => {
    test('creates a reminder with url', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Check website',
            list: {name: testListName},
            url: 'https://example.com',
          },
        ],
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{id: string; url: string}>;
      expect(reminders[0].url).toBe('https://example.com');
    });

    test('updates reminder url', async () => {
      const createResult = await client.callTool('create_reminders', {
        reminders: [{title: 'URL update test', list: {name: testListName}}],
      });

      const created = createResult as Array<{id: string}>;
      const id = created[0].id;

      const updateResult = await client.callTool('update_reminders', {
        reminders: [{id, url: 'https://updated.example.com'}],
      });

      const updated = updateResult as Array<{id: string; url: string}>;
      expect(updated[0].url).toBe('https://updated.example.com');
    });

    test('clears reminder url with null', async () => {
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'URL clear test',
            list: {name: testListName},
            url: 'https://example.com',
          },
        ],
      });

      const created = createResult as Array<{id: string}>;
      const id = created[0].id;

      const updateResult = await client.callTool('update_reminders', {
        reminders: [{id, url: null}],
      });

      const updated = updateResult as Array<{id: string; url?: string}>;
      // url is omitted (undefined) rather than null since encodableArray strips nil fields
      expect(updated[0].url).toBeUndefined();
    });
  });

  describe('dueDateIncludesTime field', () => {
    test('creates reminder with dueDateIncludesTime=true', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Timed reminder',
            list: {name: testListName},
            dueDate: '2026-06-15T14:00:00-05:00',
            dueDateIncludesTime: true,
          },
        ],
      });

      const reminders = result as Array<{
        dueDateIncludesTime: boolean;
        dueDate: string;
      }>;
      expect(reminders[0].dueDateIncludesTime).toBe(true);
      expect(reminders[0].dueDate).toBeDefined();
    });

    test('creates reminder with dueDateIncludesTime=false (all-day)', async () => {
      // Use a non-midnight time to verify that time components are stripped
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'All-day reminder',
            list: {name: testListName},
            dueDate: '2026-06-15T14:30:00-05:00',
            dueDateIncludesTime: false,
          },
        ],
      });

      const reminders = result as Array<{
        dueDateIncludesTime: boolean;
        dueDate: string;
      }>;
      expect(reminders[0].dueDateIncludesTime).toBe(false);
      // The returned dueDate should not contain the original 14:30 time
      // since isAllDay strips hour/minute/second from dueDateComponents
      expect(reminders[0].dueDate).not.toContain('T14:30:00');
    });

    test('dueDateIncludesTime is null when no due date set', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {title: 'No due date reminder', list: {name: testListName}},
        ],
      });

      const reminders = result as Array<{
        dueDateIncludesTime?: boolean;
        dueDate?: string;
      }>;
      // Fields are omitted (undefined) rather than null since encodableArray strips nil fields
      expect(reminders[0].dueDate).toBeUndefined();
      expect(reminders[0].dueDateIncludesTime).toBeUndefined();
    });
  });

  describe('alarms', () => {
    test('creates reminder with relative alarm', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Alarm test - relative',
            list: {name: testListName},
            dueDate: '2026-06-15T14:00:00-05:00',
            alarms: [{type: 'relative', offset: 3600}],
          },
        ],
      });

      const reminders = result as Array<{
        alarms: Array<{type: string; offset: number}>;
      }>;
      expect(reminders[0].alarms).toBeDefined();
      expect(reminders[0].alarms.length).toBe(1);
      expect(reminders[0].alarms[0].type).toBe('relative');
      expect(reminders[0].alarms[0].offset).toBe(3600);
    });

    test('creates reminder with absolute alarm', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Alarm test - absolute',
            list: {name: testListName},
            alarms: [{type: 'absolute', date: '2026-06-15T13:00:00-05:00'}],
          },
        ],
      });

      const reminders = result as Array<{
        alarms: Array<{type: string; date: string}>;
      }>;
      expect(reminders[0].alarms).toBeDefined();
      expect(reminders[0].alarms.length).toBe(1);
      expect(reminders[0].alarms[0].type).toBe('absolute');
      expect(reminders[0].alarms[0].date).toBeDefined();
    });

    test('creates reminder with multiple alarms', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Multiple alarms test',
            list: {name: testListName},
            dueDate: '2026-06-15T14:00:00-05:00',
            alarms: [
              {type: 'relative', offset: 3600},
              {type: 'relative', offset: 1800},
            ],
          },
        ],
      });

      const reminders = result as Array<{
        alarms: Array<{type: string; offset: number}>;
      }>;
      expect(reminders[0].alarms.length).toBe(2);
    });

    test('clears alarms with null on update', async () => {
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Clear alarms test',
            list: {name: testListName},
            dueDate: '2026-06-15T14:00:00-05:00',
            alarms: [{type: 'relative', offset: 3600}],
          },
        ],
      });

      const created = createResult as Array<{id: string}>;
      const id = created[0].id;

      const updateResult = await client.callTool('update_reminders', {
        reminders: [{id, alarms: null}],
      });

      const updated = updateResult as Array<{
        alarms: Array<unknown> | null;
      }>;
      // alarms should be null or empty after clearing
      expect(
        updated[0].alarms === null || updated[0].alarms === undefined,
      ).toBe(true);
    });
  });

  describe('recurrence', () => {
    test('creates daily recurring reminder', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Daily recurrence test',
            list: {name: testListName},
            dueDate: '2026-06-15T09:00:00-05:00',
            recurrenceRule: {frequency: 'daily', interval: 1},
          },
        ],
      });

      const reminders = result as Array<{
        recurrenceRules: Array<{frequency: string; interval: number}>;
      }>;
      expect(reminders[0].recurrenceRules).toBeDefined();
      expect(reminders[0].recurrenceRules.length).toBe(1);
      expect(reminders[0].recurrenceRules[0].frequency).toBe('daily');
      expect(reminders[0].recurrenceRules[0].interval).toBe(1);
    });

    test('creates weekly recurring reminder with specific days', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Weekly recurrence test',
            list: {name: testListName},
            dueDate: '2026-06-15T09:00:00-05:00',
            recurrenceRule: {
              frequency: 'weekly',
              interval: 1,
              daysOfWeek: [2, 4, 6], // Mon, Wed, Fri
            },
          },
        ],
      });

      const reminders = result as Array<{
        recurrenceRules: Array<{
          frequency: string;
          interval: number;
          daysOfWeek: number[];
        }>;
      }>;
      expect(reminders[0].recurrenceRules[0].frequency).toBe('weekly');
      expect(reminders[0].recurrenceRules[0].daysOfWeek).toEqual([2, 4, 6]);
    });

    test('creates monthly recurring reminder', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Monthly recurrence test',
            list: {name: testListName},
            dueDate: '2026-06-15T09:00:00-05:00',
            recurrenceRule: {
              frequency: 'monthly',
              interval: 1,
              daysOfMonth: [15],
            },
          },
        ],
      });

      const reminders = result as Array<{
        recurrenceRules: Array<{
          frequency: string;
          daysOfMonth: number[];
        }>;
      }>;
      expect(reminders[0].recurrenceRules[0].frequency).toBe('monthly');
      expect(reminders[0].recurrenceRules[0].daysOfMonth).toEqual([15]);
    });

    test('creates recurrence with end count', async () => {
      const result = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Recurrence with end count',
            list: {name: testListName},
            dueDate: '2026-06-15T09:00:00-05:00',
            recurrenceRule: {
              frequency: 'daily',
              interval: 1,
              endCount: 10,
            },
          },
        ],
      });

      const reminders = result as Array<{
        recurrenceRules: Array<{endCount: number}>;
      }>;
      expect(reminders[0].recurrenceRules[0].endCount).toBe(10);
    });

    test('clears recurrence rule with null on update', async () => {
      const createResult = await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Clear recurrence test',
            list: {name: testListName},
            dueDate: '2026-06-15T09:00:00-05:00',
            recurrenceRule: {frequency: 'daily'},
          },
        ],
      });

      const created = createResult as Array<{id: string}>;
      const id = created[0].id;

      const updateResult = await client.callTool('update_reminders', {
        reminders: [{id, recurrenceRule: null}],
      });

      const updated = updateResult as Array<{
        recurrenceRules: Array<unknown> | null;
      }>;
      expect(
        updated[0].recurrenceRules === null ||
          updated[0].recurrenceRules === undefined,
      ).toBe(true);
    });
  });

  describe('searchText parameter', () => {
    beforeAll(async () => {
      // Create reminders for search testing
      await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Meeting with John',
            list: {name: testListName},
            notes: 'Discuss project timeline',
          },
          {
            title: 'Buy groceries',
            list: {name: testListName},
            notes: 'Milk, bread, coffee',
          },
          {
            title: 'Review PR',
            list: {name: testListName},
            notes: 'John submitted a fix for the meeting scheduler',
          },
        ],
      });
    });

    test('searches by title text', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'Meeting',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      expect(reminders.length).toBeGreaterThanOrEqual(1);

      const titles = reminders.map((r) => r.title);
      expect(titles).toContain('Meeting with John');
    });

    test('searches by notes text', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'coffee',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      expect(reminders.length).toBeGreaterThanOrEqual(1);

      const titles = reminders.map((r) => r.title);
      expect(titles).toContain('Buy groceries');
    });

    test('search is case-insensitive', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'MEETING',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      expect(reminders.length).toBeGreaterThanOrEqual(1);
    });

    test('returns empty array for no matches', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'xyznonexistent999',
      });

      expect(Array.isArray(result)).toBe(true);
      expect((result as Array<unknown>).length).toBe(0);
    });

    test('searches across both title and notes', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        searchText: 'John',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;
      // Should find "Meeting with John" (title) and "Review PR" (notes mention John)
      expect(reminders.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('dateFrom/dateTo parameters', () => {
    beforeAll(async () => {
      // Create reminders with specific due dates for range testing
      await client.callTool('create_reminders', {
        reminders: [
          {
            title: 'Date range - Jan 10',
            list: {name: testListName},
            dueDate: '2026-01-10T10:00:00-05:00',
          },
          {
            title: 'Date range - Jan 20',
            list: {name: testListName},
            dueDate: '2026-01-20T10:00:00-05:00',
          },
          {
            title: 'Date range - Feb 5',
            list: {name: testListName},
            dueDate: '2026-02-05T10:00:00-05:00',
          },
          {
            title: 'Date range - no date',
            list: {name: testListName},
          },
        ],
      });
    });

    test('filters by dateFrom', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        dateFrom: '2026-01-15T00:00:00-05:00',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string; dueDate: string}>;

      // Should include Jan 20 and Feb 5 but not Jan 10
      const titles = reminders.map((r) => r.title);
      expect(titles).not.toContain('Date range - Jan 10');
      // Should not include reminders without dates
      expect(titles).not.toContain('Date range - no date');
    });

    test('filters by dateTo', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        dateTo: '2026-01-25T23:59:59-05:00',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string; dueDate: string}>;

      // Should include Jan 10 and Jan 20 but not Feb 5
      const titles = reminders.map((r) => r.title);
      expect(titles).not.toContain('Date range - Feb 5');
    });

    test('filters by dateFrom and dateTo together', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        dateFrom: '2026-01-15T00:00:00-05:00',
        dateTo: '2026-01-25T23:59:59-05:00',
      });

      expect(Array.isArray(result)).toBe(true);
      const reminders = result as Array<{title: string}>;

      // Should only include Jan 20
      const titles = reminders.map((r) => r.title);
      expect(titles).toContain('Date range - Jan 20');
      expect(titles).not.toContain('Date range - Jan 10');
      expect(titles).not.toContain('Date range - Feb 5');
    });

    test('rejects invalid dateFrom format', async () => {
      const result = await client.callTool('query_reminders', {
        list: {name: testListName},
        dateFrom: 'not-a-date',
      });

      expect(result._isError).toBe(true);
    });
  });

  describe('tool schema includes new fields', () => {
    test('tools/list includes new parameters', async () => {
      const tools = await client.listTools();

      const queryTool = tools.find((t) => t.name === 'query_reminders');
      expect(queryTool).toBeDefined();
      expect(queryTool!.description).toContain('searchText');
      expect(queryTool!.description).toContain('dateFrom');
      expect(queryTool!.description).toContain('outputDetail');

      const createTool = tools.find((t) => t.name === 'create_reminders');
      expect(createTool).toBeDefined();
      expect(createTool!.description).toContain('url');
      expect(createTool!.description).toContain('alarms');
      expect(createTool!.description).toContain('recurrenceRule');
      expect(createTool!.description).toContain('dueDateIncludesTime');
    });
  });
});
