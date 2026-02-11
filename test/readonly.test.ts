/**
 * Read-only tests for the Apple Reminders MCP server.
 * These tests don't create or modify any reminders.
 *
 * Updated for the new 6-tool API.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('Read-only operations', () => {
  let client: MCPClient;

  beforeAll(async () => {
    client = await MCPClient.create();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('lists available tools', async () => {
    const tools = await client.listTools();

    expect(tools.length).toBe(6);

    const toolNames = tools.map((t) => t.name);
    expect(toolNames).toContain('query_reminders');
    expect(toolNames).toContain('get_lists');
    expect(toolNames).toContain('create_list');
    expect(toolNames).toContain('create_reminders');
    expect(toolNames).toContain('update_reminders');
    expect(toolNames).toContain('delete_reminders');
  });

  test('gets reminder lists', async () => {
    const result = await client.callTool('get_lists');

    expect(Array.isArray(result)).toBe(true);
    const lists = result as Array<{
      id: string;
      name: string;
      isDefault: boolean;
    }>;
    expect(lists.length).toBeGreaterThanOrEqual(1);

    // Should have at least one list with required fields
    for (const list of lists) {
      expect(list.id).toBeDefined();
      expect(list.name).toBeDefined();
      expect(typeof list.isDefault).toBe('boolean');
    }

    // Exactly one list should be default
    const defaultLists = lists.filter((l) => l.isDefault);
    expect(defaultLists.length).toBe(1);
  });

  // NOTE: We intentionally do NOT test query_reminders without a list filter
  // here, as that queries the default list which might contain user's personal
  // reminders. Those operations are tested in crud.test.ts using an isolated
  // test list.

  test('query_reminders with non-existent list returns error', async () => {
    const result = await client.callTool('query_reminders', {
      list: {name: 'NonExistent List That Should Not Exist 12345'},
    });

    // New API returns error response for non-existent list
    expect(result._isError).toBe(true);
    expect(result.error).toContain('No list found with name');
  });
});
