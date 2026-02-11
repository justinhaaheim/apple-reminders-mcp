/**
 * Export tests for the Apple Reminders MCP server.
 * Tests the export_reminders tool in mock mode.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('export_reminders', () => {
  let client: MCPClient;
  let testListName: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();

    // Create some test reminders
    await client.callTool('create_reminders', {
      reminders: [
        {title: 'Export Test 1', list: {name: testListName}},
        {
          title: 'Export Test 2',
          list: {name: testListName},
          notes: 'Has notes',
          priority: 'high',
        },
        {
          title: 'Export Test 3',
          list: {name: testListName},
          dueDate: '2026-06-15T09:00:00-05:00',
        },
      ],
    });

    // Complete one reminder so we have both completed and incomplete
    const queryResult = await client.callTool('query_reminders', {
      list: {name: testListName},
      query: "[?title == 'Export Test 1']",
    });
    const reminders = queryResult as Array<{id: string}>;
    await client.callTool('update_reminders', {
      reminders: [{id: reminders[0].id, completed: true}],
    });
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('exports all reminders to temp directory', async () => {
    const result = await client.callTool('export_reminders', {});

    expect(result.success).toBe(true);
    expect(result.path).toBeDefined();
    expect(typeof result.path).toBe('string');
    expect(result.exportDate).toBeDefined();
    expect(result.fileSizeBytes).toBeGreaterThan(0);
    expect(result.note).toBeDefined();

    // Stats should reflect our test data
    const stats = result.stats as {
      lists: number;
      reminders: number;
      completed: number;
      incomplete: number;
    };
    expect(stats.lists).toBeGreaterThanOrEqual(1);
    expect(stats.reminders).toBeGreaterThanOrEqual(3);
    expect(stats.completed).toBeGreaterThanOrEqual(1);
    expect(stats.incomplete).toBeGreaterThanOrEqual(2);
  });

  test('exports only incomplete reminders when includeCompleted is false', async () => {
    const result = await client.callTool('export_reminders', {
      includeCompleted: false,
    });

    expect(result.success).toBe(true);

    const stats = result.stats as {
      reminders: number;
      completed: number;
      incomplete: number;
    };
    expect(stats.completed).toBe(0);
    expect(stats.incomplete).toBeGreaterThanOrEqual(2);
    expect(stats.reminders).toBe(stats.incomplete);
  });

  test('exports specific lists only', async () => {
    const result = await client.callTool('export_reminders', {
      lists: [{name: testListName}],
    });

    expect(result.success).toBe(true);

    const stats = result.stats as {
      lists: number;
      reminders: number;
    };
    expect(stats.lists).toBe(1);
    expect(stats.reminders).toBeGreaterThanOrEqual(3);
  });

  test('exports to custom path', async () => {
    const result = await client.callTool('export_reminders', {
      path: '/tmp/claude/test-export.json',
    });

    expect(result.success).toBe(true);
    expect(result.path).toBe('/tmp/claude/test-export.json');
  });
});
