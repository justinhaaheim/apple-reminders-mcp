import XCTest
@testable import AppleRemindersCore

/// Tests for the hashtag query helpers on ReminderDBReader. The fixture
/// has 3 hashtag labels (`Home`, `work`, `subtask-tag-test`) and 4
/// applications across reminders that contain `#home` / `#Home` / `#work`
/// in their titles.
final class HashtagEnrichmentTests: XCTestCase {

    /// UUIDs known to have hashtags in the primary fixture store.
    /// Verified via direct SQL inspection during fixture capture.
    /// 18 → "Repair the garden hose #home" (Z_PK 18 in fixture? no)
    /// Actually the table dump showed:
    ///   28 | hashtag=1 (Home)  reminder Z_PK=18  → "Repair the garden hose #home"-ish
    ///   29 | hashtag=1 (Home)  reminder Z_PK=39
    ///   30 | hashtag=2 (work)  reminder Z_PK=24  → "Read chapter 5 #work"
    ///   42 | hashtag=3 (subtask-tag-test) reminder Z_PK=68
    /// We don't hardcode UUIDs — discover them dynamically via a lookup.

    /// Returns the (uuid → expected hashtag names) map by querying the
    /// fixture directly. This avoids brittle hard-coded UUIDs.
    static func expectedHashtagsForFixture() throws -> [String: [String]] {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        var map: [String: [String]] = [:]
        try reader.eachRow(
            sql: """
                SELECT r.ZCKIDENTIFIER, h.ZNAME
                FROM ZREMCDOBJECT o
                JOIN ZREMCDHASHTAGLABEL h ON h.Z_PK = o.ZHASHTAGLABEL
                JOIN ZREMCDREMINDER r ON r.Z_PK = COALESCE(
                    o.ZREMINDER2, o.ZREMINDER1, o.ZREMINDER,
                    o.ZREMINDER3, o.ZREMINDER4, o.ZREMINDER5
                )
                WHERE o.Z_ENT = 32
                  AND o.ZMARKEDFORDELETION = 0
                  AND r.ZMARKEDFORDELETION = 0
                """
        ) { stmt in
            guard let uuidPtr = sqlite3_columnText(stmt, 0),
                  let namePtr = sqlite3_columnText(stmt, 1) else { return }
            map[String(cString: uuidPtr), default: []].append(String(cString: namePtr))
        }
        return map
    }

    func testHashtagInventoryReturnsKnownLabels() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let inventory = try reader.hashtagInventory(includeUnused: true)
        let names = inventory.map { $0.name }.sorted()
        XCTAssertEqual(names, ["Home", "subtask-tag-test", "work"])
    }

    func testHashtagInventoryUsageCounts() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let inventory = try reader.hashtagInventory(includeUnused: true)
        let byCanonical = Dictionary(uniqueKeysWithValues: inventory.map { ($0.canonicalName, $0.usageCount) })
        // Per the fixture readme: 3 hashtag-applications. Distribution:
        //   Home (label 1) — 2 applications
        //   work (label 2) — 1
        //   subtask-tag-test (label 3) — 1
        XCTAssertEqual(byCanonical["home"], 2)
        XCTAssertEqual(byCanonical["work"], 1)
        XCTAssertEqual(byCanonical["subtask-tag-test"], 1)
    }

    func testHashtagInventoryDefaultExcludesUnused() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        // Every fixture hashtag has at least one current application so
        // includeUnused: false should match true exactly. We assert the
        // contract: zero-usage labels never appear with the default.
        let included = try reader.hashtagInventory(includeUnused: false)
        XCTAssertTrue(included.allSatisfy { $0.usageCount > 0 })
    }

    func testHashtagInventoryDatesPopulated() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let inventory = try reader.hashtagInventory(includeUnused: true)
        for entry in inventory {
            XCTAssertNotNil(entry.firstSeen, "firstSeen missing for \(entry.name)")
            XCTAssertNotNil(entry.lastUsed, "lastUsed missing for \(entry.name)")
        }
    }

    func testHashtagsForReminderUUIDsBatched() throws {
        let expected = try Self.expectedHashtagsForFixture()
        XCTAssertEqual(expected.count, 4, "fixture should have 4 reminder rows with hashtags")

        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let uuids = Array(expected.keys)
        let actual = try reader.hashtags(forReminderUUIDs: uuids)

        XCTAssertEqual(actual.count, expected.count)
        for (uuid, expectedNames) in expected {
            let actualNames = actual[uuid] ?? []
            XCTAssertEqual(
                Set(actualNames), Set(expectedNames),
                "hashtags mismatch for reminder \(uuid)"
            )
        }
    }

    func testHashtagsForUnknownUUIDReturnsEmpty() throws {
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let bogus = ["00000000-0000-0000-0000-000000000000"]
        let result = try reader.hashtags(forReminderUUIDs: bogus)
        XCTAssertEqual(result.count, 0)
    }

    func testHashtagsOrderIsCanonicalSorted() throws {
        // Find a reminder with multiple hashtags if any exist, otherwise
        // verify the empty/single-tag case still returns sorted output.
        let expected = try Self.expectedHashtagsForFixture()
        let reader = try ReminderDBReader(storeURL: ReminderDBReaderTests.primaryStoreURL)
        let uuids = Array(expected.keys)
        let actual = try reader.hashtags(forReminderUUIDs: uuids)
        for (_, names) in actual {
            let sorted = names.sorted { $0.lowercased() < $1.lowercased() }
            XCTAssertEqual(names, sorted, "hashtag order should be canonical-sorted")
        }
    }
}

// MARK: - Cross-platform sqlite_column_text wrapper

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

/// Thin wrapper to keep the test code platform-agnostic — `sqlite3_column_text`
/// returns slightly different pointer types on Apple vs. Linux toolchains.
private func sqlite3_columnText(_ stmt: OpaquePointer, _ col: Int32) -> UnsafePointer<UInt8>? {
    return sqlite3_column_text(stmt, col)
}
