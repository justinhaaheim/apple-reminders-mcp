import XCTest
@testable import AppleRemindersCore

/// Tests for the test-mode guards in `RemindersManager`.
///
/// When `AR_MCP_TEST_MODE=1`, the manager must refuse any mutation that would
/// touch a list whose name doesn't start with `[AR-MCP TEST]`. This covers
/// all five guard paths:
///
///   1. `createList` blocks non-test list names
///   2. `createReminders` blocks creation in a non-test list
///   3. `updateReminders` blocks updates to reminders in a non-test list
///   4. `updateReminders` blocks moves to non-test lists
///   5. `deleteReminders` blocks deletion of reminders in non-test lists
///
/// Fixtures are built by populating `MockReminderStore` directly — no
/// `_seed_mock_data` hack required.
final class TestModeGuardTests: XCTestCase {
    private let testPrefix = TestModeConfig.testListPrefix

    // MARK: - createList

    func testCreateListBlocksNonTestName() throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        try withTestModeEnabled {
            do {
                _ = try manager.createList(name: "Regular List")
                XCTFail("Expected TEST MODE guard to throw")
            } catch let err as RemindersError {
                XCTAssertTrue(err.message.contains("TEST MODE"), "Got: \(err.message)")
                XCTAssertTrue(err.message.contains(self.testPrefix))
            }
        }
    }

    func testCreateListAllowsTestPrefixedName() throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        try withTestModeEnabled {
            let output = try manager.createList(name: "\(self.testPrefix) - Allowed")
            XCTAssertEqual(output.name, "\(self.testPrefix) - Allowed")
            XCTAssertFalse(output.id.isEmpty)
        }
    }

    // MARK: - createReminders

    func testCreateReminderBlocksNonTestList() {
        // Store has default "Reminders" list (non-test).
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        withTestModeEnabled {
            let (created, failed) = manager.createReminders(inputs: [
                CreateReminderInput(title: "Should Not Be Created"),
            ])
            XCTAssertTrue(created.isEmpty)
            XCTAssertEqual(failed.count, 1)
            XCTAssertTrue(failed[0].error.contains("TEST MODE"), "Got: \(failed[0].error)")
            // Make sure it wasn't persisted to the store.
            XCTAssertTrue(store.reminders.isEmpty)
        }
    }

    func testCreateReminderAllowsTestList() {
        let store = makeMockStore(
            lists: [(id: "test-list-id", name: "\(testPrefix) - Work")]
        )
        let manager = RemindersManager(store: store)

        withTestModeEnabled {
            let (created, failed) = manager.createReminders(inputs: [
                CreateReminderInput(
                    title: "Allowed Reminder",
                    list: ListSelector(name: "\(self.testPrefix) - Work")
                ),
            ])
            XCTAssertEqual(created.count, 1)
            XCTAssertTrue(failed.isEmpty)
            XCTAssertEqual(store.reminders.count, 1)
        }
    }

    // MARK: - updateReminders (source list guard)

    func testUpdateReminderBlocksNonTestSourceList() async {
        // Reminder lives in the default "Reminders" list (non-test).
        let store = MockReminderStore()
        let defaultId = store.defaultCalendarId!
        let mock = MockReminder(id: "rem-001", title: "Seeded", calendarId: defaultId, store: store)
        store.reminders.append(mock)

        let manager = RemindersManager(store: store)

        await withTestModeEnabled {
            let (updated, failed) = await manager.updateReminders(inputs: [
                UpdateReminderInput(id: "rem-001", title: "Should Not Change"),
            ])
            XCTAssertTrue(updated.isEmpty)
            XCTAssertEqual(failed.count, 1)
            XCTAssertTrue(failed[0].error.contains("TEST MODE"), "Got: \(failed[0].error)")
            // Verify the title wasn't changed.
            XCTAssertEqual(store.reminders[0].title, "Seeded")
        }
    }

    // MARK: - updateReminders (target list guard on move)

    func testUpdateReminderBlocksMoveToNonTestList() async {
        // Create a test-prefixed source list and a non-test target list.
        let store = makeMockStore(
            lists: [
                (id: "test-src", name: "\(testPrefix) - Source"),
                (id: "non-test-dst", name: "Non Test Target"),
            ]
        )
        let mock = MockReminder(
            id: "rem-002",
            title: "Original",
            calendarId: "test-src",
            store: store
        )
        store.reminders.append(mock)

        let manager = RemindersManager(store: store)

        await withTestModeEnabled {
            let (updated, failed) = await manager.updateReminders(inputs: [
                UpdateReminderInput(
                    id: "rem-002",
                    list: ListSelector(name: "Non Test Target")
                ),
            ])
            XCTAssertTrue(updated.isEmpty)
            XCTAssertEqual(failed.count, 1)
            XCTAssertTrue(failed[0].error.contains("TEST MODE"), "Got: \(failed[0].error)")
            // Verify the reminder's calendarId wasn't changed.
            XCTAssertEqual(store.reminders[0].calendarId, "test-src")
        }
    }

    // MARK: - deleteReminders

    func testDeleteReminderBlocksNonTestList() async {
        let store = MockReminderStore()
        let defaultId = store.defaultCalendarId!
        let mock = MockReminder(id: "rem-003", title: "Do not delete", calendarId: defaultId, store: store)
        store.reminders.append(mock)

        let manager = RemindersManager(store: store)

        await withTestModeEnabled {
            let (deleted, failed) = await manager.deleteReminders(ids: ["rem-003"])
            XCTAssertTrue(deleted.isEmpty)
            XCTAssertEqual(failed.count, 1)
            XCTAssertTrue(failed[0].error.contains("TEST MODE"), "Got: \(failed[0].error)")
            // Verify the reminder is still in the store.
            XCTAssertEqual(store.reminders.count, 1)
        }
    }

    // MARK: - Sanity: guards are off when test mode is disabled

    func testCreateListAllowsAnyNameWhenTestModeDisabled() throws {
        // Defensive: make sure the env isn't contaminated from a prior test.
        unsetenv(TestModeConfig.envVar)
        XCTAssertFalse(TestModeConfig.isEnabled)

        let store = MockReminderStore()
        let manager = RemindersManager(store: store)
        let output = try manager.createList(name: "Plain List Name")
        XCTAssertEqual(output.name, "Plain List Name")
    }
}
