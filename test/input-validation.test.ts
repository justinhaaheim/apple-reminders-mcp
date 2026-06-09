/**
 * Input-validation tests: present-but-wrong-type fields must fail LOUDLY
 * rather than being silently dropped. A silent no-op reads as success to an
 * LLM caller, which is the worst failure mode.
 */

import {describe, test, expect, beforeAll, afterAll} from 'bun:test';
import {MCPClient} from './mcp-client';

describe('input validation (no silent type drops)', () => {
  let client: MCPClient;
  let testListName: string;
  let reminderId: string;

  beforeAll(async () => {
    client = await MCPClient.create();
    testListName = await client.createTestList();
    const created = await client.callTool('create_reminders', {
      reminders: [{title: 'validation target', list: {name: testListName}}],
    });
    reminderId = (created as Array<{id: string}>)[0].id;
  });

  afterAll(async () => {
    await client.cleanup();
  });

  test('create rejects a non-string notes instead of dropping it', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'x', list: {name: testListName}, notes: 123}],
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain("Field 'notes'");
  });

  test('create rejects a non-object list selector instead of silently using the default list', async () => {
    const result = await client.callTool('create_reminders', {
      reminders: [{title: 'x', list: 'Work'}],
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain("Field 'list'");
  });

  test('update rejects a non-string url instead of dropping it', async () => {
    const result = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, url: 123}],
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain("Field 'url'");
  });

  test('update rejects a non-boolean completed instead of dropping it', async () => {
    const result = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, completed: 'yes'}],
    });
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain("Field 'completed'");
  });

  test('null is still a valid clear (not a type error)', async () => {
    const result = await client.callTool('update_reminders', {
      reminders: [{id: reminderId, notes: null}],
    });
    // Clears notes and succeeds — returns the updated reminder array.
    expect(Array.isArray(result)).toBe(true);
  });

  test('JMESPath comparing priority to a non-canonical value fails loudly', async () => {
    const result = await client.callTool('query_reminders', {
      list: {name: testListName},
      query: "[?priority == 'none']",
    });
    // Would silently return [] otherwise — instead it errors with a hint.
    expect(result._isError).toBe(true);
    expect(result.error as string).toContain('priority');
  });

  test('JMESPath with a valid priority literal still works', async () => {
    const result = await client.callTool('query_reminders', {
      list: {name: testListName},
      query: "[?priority == 'high']",
    });
    expect(result._isError).toBeUndefined();
    expect(Array.isArray(result)).toBe(true);
  });

  test('JMESPath comparing priority to null is allowed', async () => {
    const result = await client.callTool('query_reminders', {
      list: {name: testListName},
      query: '[?priority == null]',
    });
    expect(result._isError).toBeUndefined();
    expect(Array.isArray(result)).toBe(true);
  });
});
