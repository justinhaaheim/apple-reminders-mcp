import Foundation

// MARK: - Test Mode Configuration

public struct TestModeConfig {
    public static let envVar = "AR_MCP_TEST_MODE"
    public static let testListPrefix = "[AR-MCP TEST]"

    /// Uses getenv() (C stdlib) instead of ProcessInfo.processInfo.environment
    /// because ProcessInfo snapshots the environment at process startup and
    /// does not reflect subsequent setenv() calls (e.g. from --test-mode flag).
    public static var isEnabled: Bool {
        getenv(envVar).map { String(cString: $0) == "1" } ?? false
    }

    public static func isTestList(_ name: String) -> Bool {
        name.hasPrefix(testListPrefix)
    }
}

// MARK: - Mock Mode Configuration

public struct MockModeConfig {
    public static let envVar = "AR_MCP_MOCK_MODE"

    /// Uses getenv() for the same reason as TestModeConfig.isEnabled.
    public static var isEnabled: Bool {
        getenv(envVar).map { String(cString: $0) == "1" } ?? false
    }
}
