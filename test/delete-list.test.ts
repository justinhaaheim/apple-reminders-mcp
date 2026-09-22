/**
 * Tests for the delete_list tool.
 *
 * Runs in mock mode (in-memory, test mode off), so lists can be created and
 * destroyed freely without touching real reminders.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('delete_list (isolated to mock store)', () => {
  let client: MCPClient;

  beforeAll(async () => {
    client = await MCPClient.create();
  });

  afterAll(async () => {
    await client.cleanup();
  });

  async function createList(name: string): Promise<string> {
    const result = await client.callTool('create_list', {name});
    const id = (result as {id?: string}).id;
    if (!id) {
      throw new Error(`Failed to create list: ${JSON.stringify(result)}`);
    }
    return id;
  }

  async function listIds(): Promise<string[]> {
    const result = await client.callTool('get_lists', {});
    return (result as Array<{id: string}>).map((l) => l.id);
  }

  test('deletes an empty list by id', async () => {
    const id = await createList('DeleteList Empty');

    const result = await client.callTool('delete_list', {id});
    expect(result.deleted).toEqual([id]);
    expect(result.failed).toEqual([]);

    expect(await listIds()).not.toContain(id);
  });

  test('deletes a list by name', async () => {
    const id = await createList('DeleteList ByName Unique');

    const result = await client.callTool('delete_list', {
      name: 'DeleteList ByName Unique',
    });
    expect(result.deleted).toEqual([id]);

    expect(await listIds()).not.toContain(id);
  });

  test('refuses a non-empty list without force, then deletes with force', async () => {
    const id = await createList('DeleteList NonEmpty');
    await client.callTool('create_reminders', {
      reminders: [{title: 'a child reminder', list: {id}}],
    });

    // Without force: refused, list survives.
    const refused = await client.callTool('delete_list', {id});
    expect(refused._isError).toBe(true);
    expect(refused.error as string).toContain('contains 1 reminder');
    expect(await listIds()).toContain(id);

    // With force: deleted.
    const forced = await client.callTool('delete_list', {id, force: true});
    expect(forced.deleted).toEqual([id]);
    expect(await listIds()).not.toContain(id);
  });

  test('refuses an ambiguous name (multiple lists share it)', async () => {
    await createList('DeleteList Dup');
    await createList('DeleteList Dup');

    const result = await client.callTool('delete_list', {
      name: 'DeleteList Dup',
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain('Multiple lists named');
  });

  test('refuses to delete the default list', async () => {
    // The mock store seeds a default list named "Reminders".
    const result = await client.callTool('delete_list', {name: 'Reminders'});
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain('default list');
  });

  test('errors on a non-existent list', async () => {
    const result = await client.callTool('delete_list', {
      id: 'no-such-list-id',
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain('No list found');
  });
});
