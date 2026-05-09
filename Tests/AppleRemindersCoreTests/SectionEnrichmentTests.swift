import XCTest
@testable import AppleRemindersCore

/// Tests for the section query helpers on ReminderDBReader. The fixture
/// has 4 sections across 2 lists:
///   - Reminders list (UUID 50D33C25-3A77-C960-744C-4AA79DC0F46A):
///       Test Column 1 (E930361F-2ADE-4BD6-AAF5-3F694C3CC4B6)
///       Test Column 2 (7334579D-2710-4269-803F-6E2B1F6B5F09)
///   - Groceries list (UUID 040CAD09-9437-44BD-84A1-9E14EECB4375):
///       Breads & Cereals (71CF691B-D80F-4A31-8A85-F868AA45822B)
///       Sauces & Condiments (EF456A06-151A-4AF0-901D-40F7D9404EBD)
///   - Work list — no sections.
final class SectionEnrichmentTests: XCTestCase {

    static let remindersListUUID = "50D33C25-3A77-C960-744C-4AA79DC0F46A"
    static let groceriesListUUID = "040CAD09-9437-44BD-84A1-9E14EECB4375"
    static let workListUUID = "2364B738-DFAD-4135-9F7A-D00F3F05960A"

    static let testColumn1ID = "E930361F-2ADE-4BD6-AAF5-3F694C3CC4B6"
    static let breadsID = "71CF691B-D80F-4A31-8A85-F868AA45822B"
    static let saucesID = "EF456A06-151A-4AF0-901D-40F7D9404EBD"

    func testSectionsForRemindersList() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let sections = try reader.sections(forListUUID: Self.remindersListUUID)
        let names = Set(sections.map { $0.name })
        XCTAssertEqual(names, ["Test Column 1", "Test Column 2"])
    }

    func testSectionsForGroceriesList() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let sections = try reader.sections(forListUUID: Self.groceriesListUUID)
        let names = Set(sections.map { $0.name })
        XCTAssertEqual(names, ["Breads & Cereals", "Sauces & Condiments"])
    }

    func testSectionsForListWithNoSectionsReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let sections = try reader.sections(forListUUID: Self.workListUUID)
        XCTAssertEqual(sections.count, 0)
    }

    func testReminderSectionMapForRemindersList() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.reminderSectionMap(forListUUIDs: [Self.remindersListUUID])
        // From the verified fixture blob: 5 reminders all in "Test Column 1".
        XCTAssertGreaterThanOrEqual(map.count, 5,
                                    "expected at least 5 reminder→section mappings in Reminders list")
        // Every entry should resolve to one of the known sections.
        for (_, section) in map {
            XCTAssertTrue(section.id == Self.testColumn1ID
                           || section.name == "Test Column 1"
                           || section.name == "Test Column 2",
                          "unexpected section: \(section)")
        }
    }

    func testReminderSectionMapForGroceries() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.reminderSectionMap(forListUUIDs: [Self.groceriesListUUID])
        // Verified fixture: 2 reminders, one in "Sauces & Condiments"
        // (EF456A06...), one in "Breads & Cereals" (71CF691B...).
        XCTAssertEqual(map.count, 2)
        let sectionIDs = Set(map.values.map { $0.id })
        XCTAssertEqual(sectionIDs, [Self.breadsID, Self.saucesID])
    }

    func testReminderSectionMapBatchedAcrossLists() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.reminderSectionMap(forListUUIDs: [
            Self.remindersListUUID, Self.groceriesListUUID, Self.workListUUID
        ])
        // Should aggregate Reminders + Groceries memberships; Work has none.
        XCTAssertGreaterThanOrEqual(map.count, 7)
    }

    func testReminderSectionMapForListWithNoMembershipReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.reminderSectionMap(forListUUIDs: [Self.workListUUID])
        XCTAssertEqual(map.count, 0)
    }

    func testReminderSectionMapEmptyInputReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.reminderSectionMap(forListUUIDs: [])
        XCTAssertEqual(map.count, 0)
    }
}
