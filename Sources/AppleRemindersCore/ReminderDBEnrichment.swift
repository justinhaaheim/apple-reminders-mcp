import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

// MARK: - Hashtag info

/// One entry in the master hashtag inventory. Mirrors the data Apple stores
/// in `ZREMCDHASHTAGLABEL`. `usageCount` is computed at query time from
/// `ZREMCDOBJECT` rows where `Z_ENT = 32` (REMCDHashtag).
public struct HashtagInfo: Codable, Equatable {
    public let name: String
    public let canonicalName: String
    public let usageCount: Int
    public let lastUsed: Date?
    public let firstSeen: Date?

    public init(
        name: String,
        canonicalName: String,
        usageCount: Int,
        lastUsed: Date?,
        firstSeen: Date?
    ) {
        self.name = name
        self.canonicalName = canonicalName
        self.usageCount = usageCount
        self.lastUsed = lastUsed
        self.firstSeen = firstSeen
    }
}

// MARK: - Hashtag queries

extension ReminderDBReader {

    /// Returns a map from reminder UUID → hashtag names for all hashtag
    /// applications in this store. Names use the user-visible `ZNAME`
    /// (case-preserving), sorted by canonical (lowercase) form. Reminders
    /// not in this store simply don't appear in the result.
    ///
    /// `Z_ENT = 32` identifies `REMCDHashtag` rows in the union table
    /// `ZREMCDOBJECT`. The reminder FK has migrated across columns over
    /// schema versions — `ZREMINDER2` is current; we `COALESCE` the older
    /// variants for forward-compat. `ZMARKEDFORDELETION = 0` filters
    /// tombstones on both sides.
    public func hashtags(forReminderUUIDs uuids: [String]) throws -> [String: [String]] {
        guard !uuids.isEmpty else { return [:] }

        var result: [String: [(canonical: String, name: String)]] = [:]

        let placeholders = Array(repeating: "?", count: uuids.count).joined(separator: ", ")
        let sql = """
            SELECT r.ZCKIDENTIFIER AS reminder_uuid, h.ZNAME, h.ZCANONICALNAME
            FROM ZREMCDOBJECT o
            JOIN ZREMCDHASHTAGLABEL h ON h.Z_PK = o.ZHASHTAGLABEL
            JOIN ZREMCDREMINDER r ON r.Z_PK = COALESCE(
                o.ZREMINDER2, o.ZREMINDER1, o.ZREMINDER,
                o.ZREMINDER3, o.ZREMINDER4, o.ZREMINDER5
            )
            WHERE o.Z_ENT = 32
              AND o.ZMARKEDFORDELETION = 0
              AND r.ZMARKEDFORDELETION = 0
              AND r.ZCKIDENTIFIER IN (\(placeholders))
            """

        try eachRow(
            sql: sql,
            bind: { stmt in
                for (i, uuid) in uuids.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), uuid, -1, Self.SQLITE_TRANSIENT)
                }
            }
        ) { stmt in
            guard let uuidPtr = sqlite3_column_text(stmt, 0),
                  let namePtr = sqlite3_column_text(stmt, 1) else {
                return
            }
            let uuid = String(cString: uuidPtr)
            let name = String(cString: namePtr)
            let canonical: String
            if let canonPtr = sqlite3_column_text(stmt, 2) {
                canonical = String(cString: canonPtr)
            } else {
                canonical = name.lowercased()
            }
            result[uuid, default: []].append((canonical: canonical, name: name))
        }

        // Sort by canonical name (case-insensitive, deterministic) and
        // dedupe per-reminder so a tag applied multiple times appears once.
        var out: [String: [String]] = [:]
        for (uuid, items) in result {
            let sorted = items.sorted { $0.canonical < $1.canonical }
            var seen: Set<String> = []
            var names: [String] = []
            for item in sorted where seen.insert(item.canonical).inserted {
                names.append(item.name)
            }
            out[uuid] = names
        }
        return out
    }

    /// Returns the master hashtag list with usage counts. When
    /// `includeUnused` is false (default), labels with zero current
    /// applications are filtered out — matching the behaviour the
    /// Reminders.app sidebar would show.
    public func hashtagInventory(includeUnused: Bool = false) throws -> [HashtagInfo] {
        let sql = """
            SELECT
                h.ZNAME,
                h.ZCANONICALNAME,
                h.ZRECENCYDATE,
                h.ZFIRSTOCCURRENCECREATIONDATE,
                (
                    SELECT COUNT(*)
                    FROM ZREMCDOBJECT o
                    JOIN ZREMCDREMINDER r ON r.Z_PK = COALESCE(
                        o.ZREMINDER2, o.ZREMINDER1, o.ZREMINDER,
                        o.ZREMINDER3, o.ZREMINDER4, o.ZREMINDER5
                    )
                    WHERE o.Z_ENT = 32
                      AND o.ZMARKEDFORDELETION = 0
                      AND r.ZMARKEDFORDELETION = 0
                      AND o.ZHASHTAGLABEL = h.Z_PK
                ) AS usage_count
            FROM ZREMCDHASHTAGLABEL h
            ORDER BY h.ZCANONICALNAME COLLATE NOCASE ASC
            """

        var out: [HashtagInfo] = []
        try eachRow(sql: sql) { stmt in
            guard let namePtr = sqlite3_column_text(stmt, 0) else { return }
            let name = String(cString: namePtr)
            let canonical = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? name.lowercased()
            let lastUsed = Self.coreDataDate(sqlite3_column_double(stmt, 2),
                                             nullCheck: sqlite3_column_type(stmt, 2))
            let firstSeen = Self.coreDataDate(sqlite3_column_double(stmt, 3),
                                              nullCheck: sqlite3_column_type(stmt, 3))
            let usage = Int(sqlite3_column_int64(stmt, 4))
            if !includeUnused && usage == 0 { return }
            out.append(HashtagInfo(
                name: name,
                canonicalName: canonical,
                usageCount: usage,
                lastUsed: lastUsed,
                firstSeen: firstSeen
            ))
        }
        return out
    }

    // MARK: - Helpers

    /// Core Data stores timestamps as seconds since 2001-01-01 UTC, in a
    /// REAL column. SQLite reports NULL via `sqlite3_column_type`. Apple's
    /// epoch matches `Date.timeIntervalSinceReferenceDate`.
    static func coreDataDate(_ value: Double, nullCheck: Int32) -> Date? {
        if nullCheck == SQLITE_NULL { return nil }
        return Date(timeIntervalSinceReferenceDate: value)
    }
}
