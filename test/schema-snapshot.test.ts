/**
 * Schema snapshot tests for the Apple Reminders MCP server.
 *
 * These tests snapshot the server's API contract: tool names, descriptions,
 * input schemas, and initialization instructions. Any change to these surfaces
 * will cause a snapshot mismatch, catching accidental regressions like field
 * renames, removed examples, or schema drift.
 *
 * To update snapshots after intentional changes:
 *   bun test --update-snapshots
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('MCP schema snapshots', () => {
  let client: MCPClient;

  beforeAll(async () => {
    client = await MCPClient.create();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  describe('initialize response', () => {
    test('instructions text', () => {
      const instructions = client.getInstructions();
      expect(instructions).toMatchSnapshot();
    });

    test('server info', () => {
      const serverInfo = client.getServerInfo();
      expect(serverInfo).toMatchSnapshot();
    });
  });

  describe('tool schemas', () => {
    test('query_reminders', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'query_reminders');
      expect(tool).toMatchSnapshot();
    });

    test('get_lists', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'get_lists');
      expect(tool).toMatchSnapshot();
    });

    test('create_list', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'create_list');
      expect(tool).toMatchSnapshot();
    });

    test('create_reminders', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'create_reminders');
      expect(tool).toMatchSnapshot();
    });

    test('update_reminders', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'update_reminders');
      expect(tool).toMatchSnapshot();
    });

    test('delete_reminders', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'delete_reminders');
      expect(tool).toMatchSnapshot();
    });

    test('export_reminders', async () => {
      const tools = await client.listToolsWithSchemas();
      const tool = tools.find((t) => t.name === 'export_reminders');
      expect(tool).toMatchSnapshot();
    });

    test('tool count has not changed', async () => {
      const tools = await client.listToolsWithSchemas();
      const names = tools.map((t) => t.name).sort();
      expect(names).toMatchSnapshot();
    });
  });
});
