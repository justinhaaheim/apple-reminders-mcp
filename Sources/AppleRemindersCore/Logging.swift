import Foundation

// MARK: - Logging

private let logDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()

public func log(_ message: String) {
    let timestamp = logDateFormatter.string(from: Date())
    fputs("[\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

public func logError(_ message: String) {
    let timestamp = logDateFormatter.string(from: Date())
    fputs("[\(timestamp)] ERROR: \(message)\n", stderr)
    fflush(stderr)
}
