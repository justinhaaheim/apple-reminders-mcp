import Foundation

// MARK: - Reminders Error

public struct RemindersError: Error, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        return message
    }
}
