import XCTest
@testable import AppleRemindersCore

/// Minimal smoke test to verify the test target is wired up correctly
/// and the core library is importable from tests.
final class SmokeTest: XCTestCase {
    func testMockStoreInitializesWithDefaultList() {
        let store = MockReminderStore()
        XCTAssertEqual(store.calendars.count, 1)
        XCTAssertEqual(store.calendars.first?.name, "Reminders")
        XCTAssertNotNil(store.defaultCalendarId)
    }

    func testRemindersManagerCanResolveDefaultList() throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)
        let resolved = try manager.resolveList(nil)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.name, "Reminders")
    }
}
