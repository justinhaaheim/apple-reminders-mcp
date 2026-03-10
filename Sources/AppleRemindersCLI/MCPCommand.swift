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

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        if globals.mock {
            setenv(MockModeConfig.envVar, "1", 1)
        }
        if globals.testMode {
            setenv(TestModeConfig.envVar, "1", 1)
        }
        let server = MCPServer()
        await server.start()
    }
}
