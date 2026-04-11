import XCTest
@testable import AppleRemindersCore

/// Happy-path CRUD lifecycle tests for `RemindersManager` — create a list,
/// create reminders with various fields, query them, update fields (including
/// clearable fields), toggle completion, move between lists, and delete.
///
/// Runs against a `MockReminderStore` (no EventKit / no Apple Reminders).
/// Test mode is explicitly disabled at the start of each test so these
/// exercise the normal mutation paths, not the test-mode guards.
final class CRUDLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure test mode is not leaking from a prior test in another file.
        unsetenv(TestModeConfig.envVar)
    }

    // MARK: - Lists

    func testCreateListAddsCalendarToStore() throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let output = try manager.createList(name: "Project Alpha")
        XCTAssertEqual(output.name, "Project Alpha")
        XCTAssertFalse(output.isDefault)

        // The store gained a calendar with this name.
        XCTAssertTrue(store.calendars.contains(where: { $0.name == "Project Alpha" }))
    }

    func testGetAllListsMarksDefault() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let lists = manager.getAllLists()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, "Reminders")
        XCTAssertTrue(lists[0].isDefault)
    }

    // MARK: - Create reminders

    func testCreateReminderWithAllCommonFields() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let input = CreateReminderInput(
            title: "Team standup",
            notes: "Weekly sync",
            list: nil,  // default list
            dueDate: "2026-05-07T09:00:00-08:00",
            priority: "high",
            url: "https://example.com/meeting",
            dueDateIncludesTime: true
        )
        let (created, failed) = manager.createReminders(inputs: [input])
        XCTAssertTrue(failed.isEmpty, "Got failures: \(failed)")
        XCTAssertEqual(created.count, 1)

        let out = created[0]
        XCTAssertEqual(out.title, "Team standup")
        XCTAssertEqual(out.notes, "Weekly sync")
        XCTAssertEqual(out.priority, "high")
        XCTAssertEqual(out.url, "https://example.com/meeting")
        XCTAssertNotNil(out.dueDate)
        XCTAssertEqual(out.dueDateIncludesTime, true)
        XCTAssertFalse(out.isCompleted)
        XCTAssertEqual(out.listName, "Reminders")

        // Store should have one reminder now.
        XCTAssertEqual(store.reminders.count, 1)
    }

    func testBatchCreateReturnsBothSuccessesAndFailures() {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let inputs = [
            CreateReminderInput(title: "Valid 1"),
            CreateReminderInput(title: ""),  // should fail — empty title
            CreateReminderInput(title: "Valid 2", priority: "bogus"),  // should fail — bad priority
            CreateReminderInput(title: "Valid 3"),
        ]

        let (created, failed) = manager.createReminders(inputs: inputs)
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(failed.count, 2)
        XCTAssertEqual(failed[0].index, 1)
        XCTAssertEqual(failed[1].index, 2)
        XCTAssertEqual(store.reminders.count, 2)
    }

    // MARK: - Query

    func testQueryReturnsCreatedReminders() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        _ = manager.createReminders(inputs: [
            CreateReminderInput(title: "First task"),
            CreateReminderInput(title: "Second task"),
            CreateReminderInput(title: "Third task"),
        ])

        let result = try await manager.queryReminders(
            list: nil,
            status: "incomplete",
            sortBy: nil,
            query: nil,
            perPage: nil,
            cursor: nil,
            searchText: nil,
            dateFrom: nil,
            dateTo: nil,
            outputDetail: "compact"
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dict response, got: \(result)")
            return
        }
        XCTAssertEqual(dict["totalCount"] as? Int, 3)
        let reminders = dict["reminders"] as? [[String: Any]] ?? []
        XCTAssertEqual(reminders.count, 3)
        let titles = Set(reminders.compactMap { $0["title"] as? String })
        XCTAssertEqual(titles, Set(["First task", "Second task", "Third task"]))
    }

    func testQueryFiltersBySearchText() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        _ = manager.createReminders(inputs: [
            CreateReminderInput(title: "Buy groceries", notes: "milk, eggs"),
            CreateReminderInput(title: "Book flight", notes: nil),
            CreateReminderInput(title: "Read book", notes: nil),
        ])

        let result = try await manager.queryReminders(
            list: nil,
            status: "incomplete",
            sortBy: nil,
            query: nil,
            perPage: nil,
            cursor: nil,
            searchText: "book",
            dateFrom: nil,
            dateTo: nil,
            outputDetail: "compact"
        )

        guard let dict = result as? [String: Any],
              let reminders = dict["reminders"] as? [[String: Any]] else {
            XCTFail("Expected reminders array")
            return
        }
        let titles = Set(reminders.compactMap { $0["title"] as? String })
        XCTAssertEqual(titles, Set(["Book flight", "Read book"]))
    }

    // MARK: - Update: scalar fields and clearable fields

    func testUpdateChangesTitleAndPriority() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Original", priority: "low"),
        ])
        let id = created[0].id

        let (updated, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, title: "Renamed", priority: "high"),
        ])
        XCTAssertTrue(failed.isEmpty, "Got failures: \(failed)")
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].title, "Renamed")
        XCTAssertEqual(updated[0].priority, "high")

        // Store reflects the change.
        XCTAssertEqual(store.reminders[0].title, "Renamed")
    }

    func testUpdateClearsNotesAndDueDate() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(
                title: "With notes",
                notes: "Some notes",
                dueDate: "2026-05-10T12:00:00-08:00"
            ),
        ])
        let id = created[0].id
        XCTAssertNotNil(created[0].notes)
        XCTAssertNotNil(created[0].dueDate)

        let (updated, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(
                id: id,
                notes: .clear,
                dueDate: .clear
            ),
        ])
        XCTAssertTrue(failed.isEmpty)
        XCTAssertNil(updated[0].notes)
        XCTAssertNil(updated[0].dueDate)
    }

    // MARK: - Update: completion toggle

    func testUpdateMarksCompleteAndIncomplete() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Task"),
        ])
        let id = created[0].id
        XCTAssertFalse(created[0].isCompleted)

        // Mark complete
        let (completed, failed1) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, completed: true),
        ])
        XCTAssertTrue(failed1.isEmpty)
        XCTAssertTrue(completed[0].isCompleted)
        XCTAssertNotNil(completed[0].completionDate)

        // Unmark
        let (reopened, failed2) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, completed: false),
        ])
        XCTAssertTrue(failed2.isEmpty)
        XCTAssertFalse(reopened[0].isCompleted)
        XCTAssertNil(reopened[0].completionDate)
    }

    // MARK: - Update: move between lists

    func testUpdateMovesReminderBetweenLists() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)
        _ = try manager.createList(name: "Personal")
        _ = try manager.createList(name: "Work")

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Move me", list: ListSelector(name: "Personal")),
        ])
        let id = created[0].id
        let personalId = calendarId(in: store, name: "Personal")
        let workId = calendarId(in: store, name: "Work")
        XCTAssertEqual(store.reminders[0].calendarId, personalId)

        let (moved, failed) = await manager.updateReminders(inputs: [
            UpdateReminderInput(id: id, list: ListSelector(name: "Work")),
        ])
        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(moved[0].listName, "Work")
        XCTAssertEqual(store.reminders[0].calendarId, workId)
    }

    // MARK: - Delete

    func testDeleteRemovesFromStore() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Keep"),
            CreateReminderInput(title: "Delete me"),
        ])
        let keepId = created[0].id
        let deleteId = created[1].id
        XCTAssertEqual(store.reminders.count, 2)

        let (deleted, failed) = await manager.deleteReminders(ids: [deleteId])
        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(deleted, [deleteId])
        XCTAssertEqual(store.reminders.count, 1)
        XCTAssertEqual(store.reminders[0].id, keepId)
    }

    func testBatchDeleteReportsPartialFailures() async throws {
        let store = MockReminderStore()
        let manager = RemindersManager(store: store)

        let (created, _) = manager.createReminders(inputs: [
            CreateReminderInput(title: "Real"),
        ])
        let realId = created[0].id

        let (deleted, failed) = await manager.deleteReminders(
            ids: [realId, "nonexistent-id-xyz"]
        )
        XCTAssertEqual(deleted, [realId])
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].id, "nonexistent-id-xyz")
        XCTAssertTrue(store.reminders.isEmpty)
    }
}
