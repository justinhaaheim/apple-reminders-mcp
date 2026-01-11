/**
 * Read-only tests for the Apple Reminders MCP server.
 * These tests don't create or modify any reminders.
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

    expect(tools.length).toBe(12);

    const toolNames = tools.map((t) => t.name);
    expect(toolNames).toContain('list_reminder_lists');
    expect(toolNames).toContain('create_reminder_list');
    expect(toolNames).toContain('list_today_reminders');
    expect(toolNames).toContain('list_reminders');
    expect(toolNames).toContain('create_reminder');
    expect(toolNames).toContain('complete_reminder');
    expect(toolNames).toContain('delete_reminder');
    expect(toolNames).toContain('update_reminder');
    // Batch operations
    expect(toolNames).toContain('create_reminders');
    expect(toolNames).toContain('update_reminders');
    expect(toolNames).toContain('delete_reminders');
    expect(toolNames).toContain('complete_reminders');
  });

  test('lists reminder lists', async () => {
    const result = await client.callTool('list_reminder_lists');

    expect(result.lists).toBeDefined();
    expect(Array.isArray(result.lists)).toBe(true);
    expect(result.count).toBeGreaterThanOrEqual(0);
  });

  // NOTE: We intentionally do NOT test list_today_reminders or list_reminders
  // without a list filter here, as that would query all the user's personal
  // reminders. Those operations are tested in crud.test.ts using the isolated
  // test list.

  test('lists reminders from non-existent list returns empty', async () => {
    const result = await client.callTool('list_reminders', {
      list_name: 'NonExistent List That Should Not Exist 12345',
      completed: false,
    });

    expect(result.reminders).toBeDefined();
    expect(Array.isArray(result.reminders)).toBe(true);
    expect(result.count).toBe(0);
  });
});
