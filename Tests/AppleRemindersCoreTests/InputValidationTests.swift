import XCTest
@testable import AppleRemindersCore

/// Input validation edge cases for `RemindersManager`.
///
/// Exercises the error paths that the MCP/CLI layers rely on:
/// - Empty/whitespace titles are rejected at create time.
/// - Invalid priority strings are rejected.
/// - Invalid ISO 8601 dates are rejected.
/// - Nonexistent list name/id yield a helpful error (the message lists
///   available lists for name lookups).
/// - Nonexistent reminder IDs yield an error on update/delete.
/// - Abbreviated ID resolution finds a unique prefix match.
final class InputValidationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        unsetenv(TestModeConfig.envVar)
    }

    // MARK: - Title validation

    func testEmptyTitleRejected() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: ""),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(
            failed[0].error.lowercased().contains("title"),
            "Expected title-related error, got: \(failed[0].error)"
        )
    }

    func testWhitespaceOnlyTitleRejected() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "   \n\t  "),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.lowercased().contains("title"))
    }

    // MARK: - Priority validation

    func testInvalidPriorityRejectedOnCreate() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task", priority: "urgent"),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(
            failed[0].error.contains("Invalid priority"),
            "Got: \(failed[0].error)"
        )
    }

    func testInvalidPriorityRejectedOnUpdate() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task"),
        ])
        let id = created[0].id

        let (updated, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, priority: "bogus"),
        ])
        XCTAssertTrue(updated.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.contains("Invalid priority"))
    }

    // MARK: - Date validation

    func testInvalidDueDateFormatRejectedOnCreate() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task", dueDate: "not-a-date"),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(
            failed[0].error.contains("Invalid date format"),
            "Got: \(failed[0].error)"
        )
    }

    func testInvalidDueDateFormatRejectedOnUpdate() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task"),
        ])
        let id = created[0].id

        let (updated, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, dueDate: .value("bad date")),
        ])
        XCTAssertTrue(updated.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.contains("Invalid date format"))
    }

    // MARK: - List resolution errors

    func testUnknownListNameIncludesAvailableLists() {
        let store = makeMockStore(
            lists: [
                (id: nil, name: "Work"),
                (id: nil, name: "Personal"),
            ]
        )
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task", list: ListSelector(name: "Nonexistent")),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        let err = failed[0].error
        XCTAssertTrue(err.contains("Nonexistent"), "Got: \(err)")
        XCTAssertTrue(err.contains("Available lists"), "Got: \(err)")
        // Available lists are included in the message.
        XCTAssertTrue(err.contains("Work"))
        XCTAssertTrue(err.contains("Personal"))
    }

    func testUnknownListIdError() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task", list: ListSelector(id: "nonexistent-list-id")),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.contains("nonexistent-list-id"))
    }

    // MARK: - Reminder ID resolution

    func testNonexistentReminderIdOnUpdate() async {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (updated, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: "does-not-exist", title: "X"),
        ])
        XCTAssertTrue(updated.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].id, "does-not-exist")
        XCTAssertTrue(failed[0].error.contains("No reminder found"), "Got: \(failed[0].error)")
    }

    func testNonexistentReminderIdOnDelete() async {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (deleted, failed) = await manager.deleteReminders(ids: ["does-not-exist"])
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.contains("No reminder found"))
    }

    func testAbbreviatedIdResolvesUniquePrefix() async throws {
        let store = MockReminderStore()
        let defaultId = store.defaultCalendarId!
        // Use distinct IDs so any 7-char uppercase-no-dash prefix is unique.
        let mock = MockReminder(
            id: "AAAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            title: "Unique",
            calendarId: defaultId,
            store: store
        )
        store.reminders.append(mock)

        let manager = RemindersManager(store: store)

        let resolved = try await manager.resolveReminder(id: "aaaaaaa")
        XCTAssertEqual(resolved.id, "AAAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }

    func testAmbiguousAbbreviatedIdThrows() async {
        let store = MockReminderStore()
        let defaultId = store.defaultCalendarId!
        store.reminders.append(MockReminder(id: "AAAAAAA-BBBB", title: "One", calendarId: defaultId, store: store))
        store.reminders.append(MockReminder(id: "AAAAAAA-CCCC", title: "Two", calendarId: defaultId, store: store))

        let manager = RemindersManager(store: store)

        do {
            _ = try await manager.resolveReminder(id: "aaaaaaa")
            XCTFail("Expected ambiguous prefix error")
        } catch let err as RemindersError {
            XCTAssertTrue(err.message.lowercased().contains("ambiguous"), "Got: \(err.message)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - dueDateIncludesTime guard

    func testDueDateIncludesTimeRequiresDueDateOnCreate() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task", dueDateIncludesTime: true),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(
            failed[0].error.contains("dueDateIncludesTime requires a dueDate"),
            "Got: \(failed[0].error)"
        )
    }

    // MARK: - Alarm validation

    func testRelativeAlarmRejectsNegativeOffset() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(
                title: "Task",
                dueDate: "2026-05-07T09:00:00-08:00",
                alarms: [AlarmInput(type: "relative", date: nil, offset: -60)]
            ),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(
            failed[0].error.contains("positive number of seconds"),
            "Got: \(failed[0].error)"
        )
    }

    func testAbsoluteAlarmRequiresDate() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, failed) = manager.createReminders(inputs: [
            CreateReminderInput(
                title: "Task",
                alarms: [AlarmInput(type: "absolute", date: nil, offset: nil)]
            ),
        ])
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(failed[0].error.contains("Absolute alarm requires 'date'"))
    }
}
