import Foundation
import XCTest
@testable import AppleRemindersCore

// MARK: - Environment helpers

/// Temporarily sets `AR_MCP_TEST_MODE=1` for the duration of the closure,
/// restoring the prior value afterward. Works at the C-stdlib level because
/// `TestModeConfig.isEnabled` reads via `getenv`, not `ProcessInfo`.
func withTestModeEnabled(_ body: () throws -> Void) rethrows {
    let key = TestModeConfig.envVar
    let prior = getenv(key).map { String(cString: $0) }
    setenv(key, "1", 1)
    defer {
        if let prior = prior {
            setenv(key, prior, 1)
        } else {
            unsetenv(key)
        }
    }
    try body()
}

/// Async variant of `withTestModeEnabled`.
func withTestModeEnabled(_ body: () async throws -> Void) async rethrows {
    let key = TestModeConfig.envVar
    let prior = getenv(key).map { String(cString: $0) }
    setenv(key, "1", 1)
    defer {
        if let prior = prior {
            setenv(key, prior, 1)
        } else {
            unsetenv(key)
        }
    }
    try await body()
}

// MARK: - Mock fixture builders

/// Builds a `MockReminderStore` seeded with the supplied lists and reminders.
/// The store starts with its own default "Reminders" list (added by the
/// `MockReminderStore` initializer); additional lists are appended.
///
/// - Parameters:
///   - lists: Calendars to add beyond the default "Reminders" list.
///           Each tuple is `(id, name)`; pass `nil` for id to auto-generate.
///   - reminders: Reminders to add. Each tuple is `(id, title, calendarId)`.
/// - Returns: The populated mock store.
func makeMockStore(
    lists: [(id: String?, name: String)] = [],
    reminders: [(id: String?, title: String, calendarId: String)] = []
) -> MockReminderStore {
    let store = MockReminderStore()
    for list in lists {
        let calendar = MockCalendar(id: list.id ?? UUID().uuidString, name: list.name)
        store.calendars.append(calendar)
    }
    for rem in reminders {
        let mock = MockReminder(
            id: rem.id ?? UUID().uuidString,
            title: rem.title,
            calendarId: rem.calendarId,
            store: store
        )
        store.reminders.append(mock)
    }
    return store
}

/// Looks up a calendar by name in the store (case-insensitive).
func calendarId(in store: MockReminderStore, name: String) -> String {
    guard let cal = store.calendars.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) else {
        XCTFail("Expected calendar '\(name)' in store")
        return ""
    }
    return cal.id
}
