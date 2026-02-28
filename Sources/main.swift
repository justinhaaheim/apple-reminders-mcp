import Foundation

// MARK: - Logging

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

func logError(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
    fflush(stderr)
}

// MARK: - Main

let server = MCPServer()
await server.start()
