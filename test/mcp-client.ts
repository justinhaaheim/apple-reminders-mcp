/**
 * MCP Client utility for testing the Apple Reminders MCP server.
 * Spawns the server process and communicates via JSON-RPC over stdin/stdout.
 *
 * Updated for the new 6-tool API.
 *
 * Supports two modes:
 * - Mock mode (default): Uses in-memory storage, no EventKit access needed
 * - Real mode: Uses actual Apple Reminders via EventKit (requires macOS)
 *
 * Environment variables:
 * - AR_MCP_MOCK_MODE=1: Enable mock mode (in-memory storage)
 * - AR_MCP_TEST_MODE=1: Enable test mode (restricts writes to test lists)
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

interface MCPTool {
  name: string;
  description: string;
  inputSchema?: Record<string, unknown>;
}

interface MCPResponse {
  jsonrpc: '2.0';
  id: number;
  result?: {
    content?: Array<{type: string; text: string}>;
    tools?: MCPTool[];
    protocolVersion?: string;
    capabilities?: Record<string, unknown>;
    serverInfo?: {name: string; version: string};
    instructions?: string;
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

interface MCPClientOptions {
  /** Use mock mode (in-memory storage). Default: true */
  mockMode?: boolean;
  /** Use test mode (restricts writes to test lists). Default: true for real mode */
  testMode?: boolean;
}

export class MCPClient {
  private process: Subprocess<'pipe', 'pipe', 'pipe'>;
  private requestId = 0;
  private testListName: string | null = null;
  private createdReminderIds: string[] = [];
  private useMockMode: boolean;
  private initializeResult: MCPResponse['result'] | null = null;

  private constructor(
    proc: Subprocess<'pipe', 'pipe', 'pipe'>,
    useMockMode: boolean,
  ) {
    this.process = proc;
    this.useMockMode = useMockMode;
  }

  /**
   * Create a new MCP client.
   *
   * By default uses mock mode (in-memory storage) which:
   * - Works on any platform (no macOS/EventKit required)
   * - Provides fast, deterministic tests
   * - Starts with a clean slate each time
   *
   * For real EventKit testing, use: MCPClient.create({mockMode: false})
   */
  static async create(options: MCPClientOptions = {}): Promise<MCPClient> {
    const {mockMode = true, testMode} = options;

    // For real mode, default to test mode enabled for safety
    const useTestMode = testMode ?? !mockMode;

    const proc = spawn([EXECUTABLE_PATH], {
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        AR_MCP_MOCK_MODE: mockMode ? '1' : undefined,
        AR_MCP_TEST_MODE: useTestMode ? '1' : undefined,
      },
    });

    const client = new MCPClient(proc, mockMode);

    // Wait a bit for the server to start
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Initialize the connection
    await client.initialize();

    return client;
  }

  /**
   * Create a new MCP client with real EventKit (requires macOS).
   * Test mode is enabled by default to prevent accidental modification of real data.
   */
  static async createWithRealEventKit(
    options: {testMode?: boolean} = {},
  ): Promise<MCPClient> {
    return MCPClient.create({
      mockMode: false,
      testMode: options.testMode ?? true,
    });
  }

  /**
   * Create a new MCP client WITHOUT test mode (for testing that test mode works).
   * WARNING: This can modify real reminders if not in mock mode!
   */
  static async createWithoutTestMode(
    options: {mockMode?: boolean} = {},
  ): Promise<MCPClient> {
    return MCPClient.create({
      mockMode: options.mockMode ?? true,
      testMode: false,
    });
  }

  /**
   * Check if this client is using mock mode.
   */
  isMockMode(): boolean {
    return this.useMockMode;
  }

  private async initialize(): Promise<void> {
    const response = await this.sendRequest('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: {name: 'test-client', version: '1.0'},
    });
    this.initializeResult = response.result ?? null;
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
   * List available tools (name and description only).
   */
  async listTools(): Promise<Array<{name: string; description: string}>> {
    const response = await this.sendRequest('tools/list', {});
    return response.result?.tools ?? [];
  }

  /**
   * List available tools with full details including inputSchema.
   */
  async listToolsWithSchemas(): Promise<MCPTool[]> {
    const response = await this.sendRequest('tools/list', {});
    return response.result?.tools ?? [];
  }

  /**
   * Get the instructions text from the initialize response.
   */
  getInstructions(): string | null {
    return this.initializeResult?.instructions ?? null;
  }

  /**
   * Get server info from the initialize response.
   */
  getServerInfo(): {name: string; version: string} | null {
    return this.initializeResult?.serverInfo ?? null;
  }

  /**
   * Create a unique test list for this test run.
   * In mock mode, uses a simpler name since there's no conflict risk.
   * In real mode, uses the test prefix to comply with test mode restrictions.
   */
  async createTestList(): Promise<string> {
    const uuid = randomUUID().split('-')[0];

    // In mock mode, we can use simpler names since it's all in-memory
    // In real mode, we need the test prefix for test mode validation
    this.testListName = this.useMockMode
      ? `Test List (${uuid})`
      : `${TEST_LIST_PREFIX} - TMP (${uuid})`;

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
