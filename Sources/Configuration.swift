import Foundation

// MARK: - Test Mode Configuration

struct TestModeConfig {
    static let envVar = "AR_MCP_TEST_MODE"
    static let testListPrefix = "[AR-MCP TEST]"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }

    static func isTestList(_ name: String) -> Bool {
        name.hasPrefix(testListPrefix)
    }
}

// MARK: - Mock Mode Configuration

struct MockModeConfig {
    static let envVar = "AR_MCP_MOCK_MODE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }
}
