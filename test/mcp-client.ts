/**
 * MCP Client utility for testing the Apple Reminders MCP server.
 * Spawns the server process and communicates via JSON-RPC over stdin/stdout.
 *
 * Updated for the new 6-tool API.
 */

import {spawn, type Subprocess} from 'bun';
import {randomUUID} from 'crypto';

const EXECUTABLE_PATH = '.build/release/apple-reminders-mcp';
const TEST_LIST_PREFIX = '[AR-MCP TEST]';

interface MCPRequest {
  jsonrpc: '2.0';
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

interface MCPResponse {
  jsonrpc: '2.0';
  id: number;
  result?: {
    content?: Array<{type: string; text: string}>;
    tools?: Array<{name: string; description: string}>;
    protocolVersion?: string;
    isError?: boolean;
  };
  error?: {
    code: number;
    message: string;
  };
}

interface ToolResult {
  [key: string]: unknown;
}

export class MCPClient {
  private process: Subprocess<'pipe', 'pipe', 'pipe'>;
  private requestId = 0;
  private testListName: string | null = null;
  private createdReminderIds: string[] = [];

  private constructor(proc: Subprocess<'pipe', 'pipe', 'pipe'>) {
    this.process = proc;
  }

  /**
   * Create a new MCP client with test mode enabled.
   */
  static async create(): Promise<MCPClient> {
    const proc = spawn([EXECUTABLE_PATH], {
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        AR_MCP_TEST_MODE: '1',
      },
    });

    const client = new MCPClient(proc);

    // Wait a bit for the server to start
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Initialize the connection
    await client.initialize();

    return client;
  }

  /**
   * Create a new MCP client WITHOUT test mode (for testing that test mode works).
   */
  static async createWithoutTestMode(): Promise<MCPClient> {
    const proc = spawn([EXECUTABLE_PATH], {
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        AR_MCP_TEST_MODE: undefined,
      },
    });

    const client = new MCPClient(proc);
    await new Promise((resolve) => setTimeout(resolve, 500));
    await client.initialize();
    return client;
  }

  private async initialize(): Promise<void> {
    await this.sendRequest('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: {name: 'test-client', version: '1.0'},
    });
  }

  /**
   * Send a JSON-RPC request and get the response.
   * Handles large responses by reading until we have a complete JSON object.
   */
  async sendRequest(
    method: string,
    params?: Record<string, unknown>,
  ): Promise<MCPResponse> {
    const request: MCPRequest = {
      jsonrpc: '2.0',
      id: ++this.requestId,
      method,
      params,
    };

    const requestLine = JSON.stringify(request) + '\n';
    this.process.stdin.write(requestLine);
    await this.process.stdin.flush();

    // Read response from stdout, buffering until we have complete JSON
    const reader = this.process.stdout.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    const maxAttempts = 100; // Safety limit
    let attempts = 0;

    while (attempts < maxAttempts) {
      const {value, done} = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, {stream: true});

      // Try to find a complete JSON line
      const lines = buffer.split('\n');
      for (const line of lines) {
        if (line.startsWith('{')) {
          try {
            const parsed = JSON.parse(line) as MCPResponse;
            reader.releaseLock();
            return parsed;
          } catch {
            // Not complete yet, keep reading
          }
        }
      }

      attempts++;
    }

    reader.releaseLock();
    throw new Error(
      `Failed to get complete response after ${maxAttempts} attempts. Buffer: ${buffer.slice(0, 500)}...`,
    );
  }

  /**
   * Call an MCP tool and return the parsed result.
   * The new API returns tool errors with isError: true rather than success: false.
   */
  async callTool(
    toolName: string,
    args: Record<string, unknown> = {},
  ): Promise<ToolResult> {
    const response = await this.sendRequest('tools/call', {
      name: toolName,
      arguments: args,
    });

    if (response.error) {
      return {_isError: true, error: response.error.message};
    }

    const content = response.result?.content?.[0];
    if (!content || content.type !== 'text') {
      return {_isError: true, error: 'No content in response'};
    }

    // Check if this is an error response (plain text error message with isError: true)
    if (response.result?.isError) {
      return {_isError: true, error: content.text};
    }

    try {
      return JSON.parse(content.text) as ToolResult;
    } catch {
      // If parsing fails, it might be a plain text error
      return {_isError: true, error: content.text};
    }
  }

  /**
   * List available tools.
   */
  async listTools(): Promise<Array<{name: string; description: string}>> {
    const response = await this.sendRequest('tools/list', {});
    return response.result?.tools ?? [];
  }

  /**
   * Create a unique test list for this test run.
   */
  async createTestList(): Promise<string> {
    const uuid = randomUUID().split('-')[0];
    this.testListName = `${TEST_LIST_PREFIX} - TMP (${uuid})`;

    const result = await this.callTool('create_list', {
      name: this.testListName,
    });

    if (result._isError) {
      throw new Error(`Failed to create test list: ${result.error}`);
    }

    return this.testListName;
  }

  /**
   * Get the name of the test list for this client.
   */
  getTestListName(): string {
    if (!this.testListName) {
      throw new Error('Test list not created yet');
    }
    return this.testListName;
  }

  /**
   * Create a reminder in the test list and track it for cleanup.
   * Uses the new create_reminders batch API.
   */
  async createTestReminder(
    title: string,
    options: {notes?: string; dueDate?: string; priority?: string} = {},
  ): Promise<string> {
    if (!this.testListName) {
      throw new Error('Test list not created yet');
    }

    const result = await this.callTool('create_reminders', {
      reminders: [
        {
          title,
          list: {name: this.testListName},
          ...options,
        },
      ],
    });

    // New API returns array of created reminders or {created, failed}
    let reminderId: string | undefined;

    if (Array.isArray(result)) {
      // Success - array of created reminders
      reminderId = (result[0] as {id: string})?.id;
    } else if (result.created && Array.isArray(result.created)) {
      // Partial success - some created, some failed
      reminderId = (result.created[0] as {id: string})?.id;
    }

    if (!reminderId) {
      const error = result._isError
        ? result.error
        : result.failed
          ? JSON.stringify(result.failed)
          : 'Unknown error';
      throw new Error(`Failed to create reminder: ${error}`);
    }

    this.createdReminderIds.push(reminderId);
    return reminderId;
  }

  /**
   * Clean up all test reminders and close the server.
   */
  async cleanup(): Promise<void> {
    // Delete all created reminders using batch delete
    if (this.createdReminderIds.length > 0) {
      try {
        await this.callTool('delete_reminders', {ids: this.createdReminderIds});
      } catch {
        // Ignore errors during cleanup
      }
    }

    // Kill the server process
    this.process.kill();
  }

  /**
   * Get the test list prefix used by the server.
   */
  static getTestListPrefix(): string {
    return TEST_LIST_PREFIX;
  }
}
