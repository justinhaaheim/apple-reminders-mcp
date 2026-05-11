import XCTest
@testable import AppleRemindersCore

/// Tests for the parent/child query helpers on ReminderDBReader. The
/// fixture has 1 parent ("Test parent reminder", UUID
/// 4B5196E4-8234-433C-943F-C54F51EA0CC3) with 5 children.
final class ParentChildEnrichmentTests: XCTestCase {

    static let parentUUID = "4B5196E4-8234-433C-943F-C54F51EA0CC3"
    static let expectedChildUUIDs: Set<String> = [
        "50EF07BC-504C-4C16-A33C-1103072BBCF3",
        "B58F2C6B-E86F-4C22-9311-D836C3627AE3",
        "0C495646-BEFE-462B-8BEB-731B594553B2",
        "39DE74A0-D19C-4CD2-8629-D25D932669EC",
        "1F55D25D-E968-4755-ABD5-879ECA7C996F",
    ]

    func testChildrenOfKnownParent() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.children(forReminderUUIDs: [Self.parentUUID])
        let children = map[Self.parentUUID] ?? []
        XCTAssertEqual(Set(children), Self.expectedChildUUIDs)
    }

    func testParentOfKnownChildren() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.parents(forReminderUUIDs: Array(Self.expectedChildUUIDs))
        for child in Self.expectedChildUUIDs {
            XCTAssertEqual(map[child], Self.parentUUID, "child \(child) should map to parent \(Self.parentUUID)")
        }
    }

    func testParentOfTopLevelReminderIsAbsent() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        // The known reminder used in ReminderDBReaderTests is a top-level
        // (no parent). Its parents() lookup should return an empty map.
        let map = try reader.parents(forReminderUUIDs: [ReminderDBReaderTests.knownReminderUUID])
        XCTAssertNil(map[ReminderDBReaderTests.knownReminderUUID])
    }

    func testChildrenOfReminderWithoutChildrenReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let map = try reader.children(forReminderUUIDs: [ReminderDBReaderTests.knownReminderUUID])
        XCTAssertNil(map[ReminderDBReaderTests.knownReminderUUID])
    }

    func testRoundTripConsistency() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        // For every parent, every reported child reports the parent back.
        let parentMap = try reader.parents(forReminderUUIDs: Array(Self.expectedChildUUIDs))
        let childMap = try reader.children(forReminderUUIDs: [Self.parentUUID])

        for child in childMap[Self.parentUUID] ?? [] {
            XCTAssertEqual(parentMap[child], Self.parentUUID,
                           "round-trip failed for child \(child)")
        }
    }

    func testEmptyInputReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        XCTAssertEqual(try reader.parents(forReminderUUIDs: []).count, 0)
        XCTAssertEqual(try reader.children(forReminderUUIDs: []).count, 0)
    }
}
