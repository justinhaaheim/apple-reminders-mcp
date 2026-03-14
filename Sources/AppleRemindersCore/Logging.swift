import Foundation

// MARK: - Logging

/// Format a timestamp for log output.
/// Creates a new ISO8601DateFormatter per call to avoid thread-safety issues —
/// ISO8601DateFormatter inherits from Formatter which is not thread-safe,
/// and log()/logError() are called from async contexts.
private func logTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: Date())
}

public func log(_ message: String) {
    let timestamp = logTimestamp()
    fputs("[\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

public func logError(_ message: String) {
    let timestamp = logTimestamp()
    fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
    fflush(stderr)
}
