# Testing

## Automated tests

```bash
bun run build      # tests run the binaries in .build/release/
bun test ./test    # this repo's tests only
```

- The tests use the in-memory mock store (`--mock` / `AR_MCP_MOCK_MODE=1`), so they never touch real reminders.
- A test client created with real EventKit (`MCPClient.createWithRealEventKit()` in `test/mcp-client.ts`) defaults to test mode (`AR_MCP_TEST_MODE=1`), which only allows writes to lists whose names start with `[AR-MCP TEST]`. `bun run test:cleanup` deletes leftover test lists after asking.
- Plain `bun test` also runs justin-sdk's own tests from the install cache in `tmp/`; use `bun test ./test`.
- In the Claude Code sandbox, the export and auto-snapshot tests fail because the binary's temp-file and git writes are blocked. Run the suite outside the sandbox.

## Talking to the MCP server by hand

```bash
./test/interactive.sh
```

Or pipe one JSON-RPC request into the server, using the mock store so nothing real changes:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | .build/release/reminders mcp --mock
```

## Trying a dev build in Claude Desktop or another tool

Run `bun run install:local` and point the tool at `~/.local/bin/reminders`; roll back with `mv ~/.local/bin/reminders.prev ~/.local/bin/reminders`. Do not point tools at `.build/`: a later rebuild or branch switch would change what they run.
