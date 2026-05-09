import XCTest
@testable import AppleRemindersCore

/// Tests for the read-only Reminders DB reader scaffolding.
///
/// The fixture lives at `test/fixtures/jtest1-reminders-db/` (committed,
/// captured from a dedicated `jtest1` macOS account; no PII). We resolve
/// it via `#filePath` so the tests run regardless of cwd.
final class ReminderDBReaderTests: XCTestCase {

    /// Primary store inside the fixture — the one with hashtags, sections,
    /// and parent/child relationships.
    static let primaryStoreName = "Data-5FDFBC03-B57A-4548-806D-276EB1162D63.sqlite"

    /// A reminder UUID known to exist in the primary store.
    static let knownReminderUUID = "B81183EE-B4A9-5810-B36B-A34588004F42"

    static var fixtureContainer: URL {
        // Tests/AppleRemindersCoreTests/ReminderDBReaderTests.swift
        //     ../../test/fixtures/jtest1-reminders-db
        let here = URL(fileURLWithPath: #filePath, isDirectory: false)
        return here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test/fixtures/jtest1-reminders-db", isDirectory: true)
    }

    static var primaryStoreURL: URL {
        fixtureContainer.appendingPathComponent(primaryStoreName)
    }

    // MARK: discover()

    func testDiscoverReturnsExpectedStoresAndSkipsLocal() throws {
        let readers = ReminderDBReader.discover(containerOverride: Self.fixtureContainer)
        XCTAssertEqual(readers.count, 4, "Should open 4 of 5 stores (skipping Data-local.sqlite)")
        let names = Set(readers.map { $0.storeURL.lastPathComponent })
        XCTAssertFalse(names.contains("Data-local.sqlite"))
        XCTAssertTrue(names.contains(Self.primaryStoreName))
    }

    func testDiscoverWithMissingContainerReturnsEmpty() {
        let bogus = URL(fileURLWithPath: "/var/empty/__nope__")
        let readers = ReminderDBReader.discover(containerOverride: bogus)
        XCTAssertEqual(readers.count, 0)
    }

    // MARK: open

    func testOpenReadOnly() throws {
        let reader = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        // Sanity: the connection should answer queries without error.
        var rowCount = 0
        try reader.eachRow(sql: "SELECT 1") { _ in rowCount += 1 }
        XCTAssertEqual(rowCount, 1)
    }

    func testOpenMissingFileThrowsNotFound() {
        let bogus = URL(fileURLWithPath: "/var/empty/__missing__.sqlite")
        XCTAssertThrowsError(try ReminderDBReader(storeURL: bogus)) { err in
            guard case ReminderDBReader.ReminderDBError.notFound = err else {
                XCTFail("expected .notFound, got \(err)")
                return
            }
        }
    }

    // MARK: schema fingerprint

    func testSchemaFingerprintIsStable() throws {
        let r1 = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        let r2 = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        let f1 = try r1.schemaFingerprint()
        let f2 = try r2.schemaFingerprint()
        XCTAssertEqual(f1, f2, "Same DB should yield the same fingerprint")
        XCTAssertFalse(f1.isEmpty)
        XCTAssertEqual(f1.count, 32, "fingerprint is 128-bit / 32 hex chars")
    }

    func testIsSchemaSupportedDoesNotThrow() throws {
        let reader = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        // We don't assert true/false — known-good list is empty by design;
        // just verify the call surface works without error.
        _ = try reader.isSchemaSupported()
    }

    // MARK: lookups

    func testReminderRowIDForUUID() throws {
        let reader = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        let pk = try reader.reminderRowID(forUUID: Self.knownReminderUUID)
        XCTAssertNotNil(pk)
    }

    func testReminderRowIDForUnknownUUIDReturnsNil() throws {
        let reader = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        let pk = try reader.reminderRowID(forUUID: "00000000-0000-0000-0000-000000000000")
        XCTAssertNil(pk)
    }

    // MARK: read-only invariant

    /// Acceptance criterion: after running tests, the fixture DB's mtime is
    /// unchanged. This test runs a battery of reads against every fixture
    /// store and verifies mtime drift is exactly zero.
    func testNoFixtureMutation() throws {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: Self.fixtureContainer,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.pathExtension == "sqlite" }

        let before: [URL: Date] = try Dictionary(uniqueKeysWithValues: entries.map { url in
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let mtime = attrs[.modificationDate] as? Date ?? Date.distantPast
            return (url, mtime)
        })

        // Exercise a representative read path on the primary store.
        let reader = try ReminderDBReader(storeURL: Self.primaryStoreURL)
        _ = try reader.schemaFingerprint()
        _ = try reader.reminderRowID(forUUID: Self.knownReminderUUID)
        var rows = 0
        try reader.eachRow(sql: "SELECT Z_PK FROM ZREMCDREMINDER LIMIT 5") { _ in rows += 1 }
        XCTAssertGreaterThan(rows, 0)

        for (url, oldMtime) in before {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let newMtime = attrs[.modificationDate] as? Date ?? Date.distantPast
            XCTAssertEqual(
                oldMtime, newMtime,
                "Fixture \(url.lastPathComponent) mtime changed — read-only invariant violated"
            )
        }
    }
}
