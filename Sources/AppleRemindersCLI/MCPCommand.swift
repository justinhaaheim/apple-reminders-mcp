import ArgumentParser
import AppleRemindersCore
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the MCP (Model Context Protocol) server on stdio",
        discussion: """
        Starts a JSON-RPC 2.0 server on stdin/stdout for use with Claude Desktop \
        and other MCP clients.

        For Claude Desktop, configure with:
          {"command": "reminders", "args": ["mcp"]}
        """
    )

    func run() async throws {
        let server = MCPServer()
        await server.start()
    }
}
