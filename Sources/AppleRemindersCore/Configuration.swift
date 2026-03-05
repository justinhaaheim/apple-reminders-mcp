import Foundation

// MARK: - Test Mode Configuration

public struct TestModeConfig {
    public static let envVar = "AR_MCP_TEST_MODE"
    public static let testListPrefix = "[AR-MCP TEST]"

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }

    public static func isTestList(_ name: String) -> Bool {
        name.hasPrefix(testListPrefix)
    }
}

// MARK: - Mock Mode Configuration

public struct MockModeConfig {
    public static let envVar = "AR_MCP_MOCK_MODE"

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envVar] == "1"
    }
}
