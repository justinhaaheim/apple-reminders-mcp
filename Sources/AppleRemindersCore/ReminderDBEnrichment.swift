import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

// MARK: - Section info

/// A within-list section (kanban-style column) defined in
/// `ZREMCDBASESECTION`. Reminders 16+ surfaces these as columns inside a
/// list; EventKit doesn't expose them.
public struct SectionInfo: Codable, Equatable, Hashable {
    public let id: String       // ZCKIDENTIFIER
    public let name: String     // ZDISPLAYNAME
    public let canonicalName: String?  // ZCANONICALNAME (often nil)

    public init(id: String, name: String, canonicalName: String? = nil) {
        self.id = id
        self.name = name
        self.canonicalName = canonicalName
    }
}

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

// MARK: - Parent/child queries

extension ReminderDBReader {

    /// For each input UUID, returns the parent reminder's UUID if one
    /// exists in this store. Reminders without a parent (top-level) and
    /// reminders not present in this store simply don't appear in the
    /// output.
    ///
    /// `ZREMCDREMINDER.ZPARENTREMINDER` is an integer FK to the parent's
    /// `Z_PK`. UUIDs round-trip via `ZCKIDENTIFIER`. Tombstones filtered
    /// on both sides.
    public func parents(forReminderUUIDs uuids: [String]) throws -> [String: String] {
        guard !uuids.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: uuids.count).joined(separator: ", ")
        let sql = """
            SELECT child.ZCKIDENTIFIER, parent.ZCKIDENTIFIER
            FROM ZREMCDREMINDER child
            JOIN ZREMCDREMINDER parent ON parent.Z_PK = child.ZPARENTREMINDER
            WHERE child.ZMARKEDFORDELETION = 0
              AND parent.ZMARKEDFORDELETION = 0
              AND child.ZCKIDENTIFIER IN (\(placeholders))
            """

        var out: [String: String] = [:]
        try eachRow(
            sql: sql,
            bind: { stmt in
                for (i, uuid) in uuids.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), uuid, -1, Self.SQLITE_TRANSIENT)
                }
            }
        ) { stmt in
            guard let cPtr = sqlite3_column_text(stmt, 0),
                  let pPtr = sqlite3_column_text(stmt, 1) else { return }
            out[String(cString: cPtr)] = String(cString: pPtr)
        }
        return out
    }

    /// For each input UUID, returns the UUIDs of its direct children.
    /// Reminders with no children get an empty array. Reminders not
    /// present in this store don't appear in the output.
    public func children(forReminderUUIDs uuids: [String]) throws -> [String: [String]] {
        guard !uuids.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: uuids.count).joined(separator: ", ")
        let sql = """
            SELECT parent.ZCKIDENTIFIER, child.ZCKIDENTIFIER, child.ZICSDISPLAYORDER
            FROM ZREMCDREMINDER child
            JOIN ZREMCDREMINDER parent ON parent.Z_PK = child.ZPARENTREMINDER
            WHERE child.ZMARKEDFORDELETION = 0
              AND parent.ZMARKEDFORDELETION = 0
              AND parent.ZCKIDENTIFIER IN (\(placeholders))
            ORDER BY parent.ZCKIDENTIFIER, child.ZICSDISPLAYORDER ASC, child.Z_PK ASC
            """

        var out: [String: [String]] = [:]
        try eachRow(
            sql: sql,
            bind: { stmt in
                for (i, uuid) in uuids.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), uuid, -1, Self.SQLITE_TRANSIENT)
                }
            }
        ) { stmt in
            guard let pPtr = sqlite3_column_text(stmt, 0),
                  let cPtr = sqlite3_column_text(stmt, 1) else { return }
            out[String(cString: pPtr), default: []].append(String(cString: cPtr))
        }
        return out
    }
}

// MARK: - Section queries

extension ReminderDBReader {

    /// Returns all sections defined within a given list, in display order.
    ///
    /// `ZREMCDBASESECTION` rows hold the section definitions. The bead's
    /// JSON schema-notes promise mentioned `ZSECTIONIDSORDERINGASDATA` as
    /// a per-list ordering blob — in the current fixture it's nil, so we
    /// fall back to ordering by display name. (When real users hit a
    /// list with explicit ordering, that hex blob can be decoded as JSON
    /// `["<uuid>", "<uuid>", ...]` and used as the primary sort key.)
    ///
    /// Tombstones filtered. List can be referenced by ZLIST (regular
    /// list), ZSMARTLIST, or ZTEMPLATE — current Reminders only uses
    /// ZLIST in practice; we follow that.
    public func sections(forListUUID listUUID: String) throws -> [SectionInfo] {
        let sql = """
            SELECT s.ZCKIDENTIFIER, s.ZDISPLAYNAME, s.ZCANONICALNAME, s.Z_PK
            FROM ZREMCDBASESECTION s
            JOIN ZREMCDBASELIST l ON l.Z_PK = s.ZLIST
            WHERE s.ZMARKEDFORDELETION = 0
              AND l.ZMARKEDFORDELETION = 0
              AND l.ZCKIDENTIFIER = ?1
            ORDER BY s.ZDISPLAYNAME COLLATE NOCASE ASC, s.Z_PK ASC
            """

        var out: [SectionInfo] = []
        try eachRow(
            sql: sql,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, listUUID, -1, Self.SQLITE_TRANSIENT)
            }
        ) { stmt in
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let namePtr = sqlite3_column_text(stmt, 1) else { return }
            let canonical = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            out.append(SectionInfo(
                id: String(cString: idPtr),
                name: String(cString: namePtr),
                canonicalName: canonical?.isEmpty == false ? canonical : nil
            ))
        }
        return out
    }

    /// Decodes the per-list section-membership JSON blobs and returns a
    /// map from reminder UUID → SectionInfo for every reminder that
    /// belongs to a section.
    ///
    /// The blob lives on `ZREMCDBASELIST.ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA`
    /// and has the verified shape:
    ///
    /// ```
    /// {"minimumSupportedVersion":20230430,
    ///  "memberships":[{"groupID":"<sectionUUID>",
    ///                  "memberID":"<reminderUUID>",
    ///                  "modifiedOn":<core-data-timestamp>}, …]}
    /// ```
    ///
    /// We resolve `groupID` against `ZREMCDBASESECTION` once per section
    /// to attach friendly names. Reminders not mentioned in any blob
    /// have no entry in the result (caller treats that as "no section").
    public func reminderSectionMap(forListUUIDs listUUIDs: [String])
        throws -> [String: SectionInfo]
    {
        guard !listUUIDs.isEmpty else { return [:] }

        // 1) Build a section UUID → SectionInfo lookup table for all
        //    requested lists in one query.
        var sectionsByID: [String: SectionInfo] = [:]
        let placeholders = Array(repeating: "?", count: listUUIDs.count).joined(separator: ", ")
        let sectionSQL = """
            SELECT s.ZCKIDENTIFIER, s.ZDISPLAYNAME, s.ZCANONICALNAME
            FROM ZREMCDBASESECTION s
            JOIN ZREMCDBASELIST l ON l.Z_PK = s.ZLIST
            WHERE s.ZMARKEDFORDELETION = 0
              AND l.ZMARKEDFORDELETION = 0
              AND l.ZCKIDENTIFIER IN (\(placeholders))
            """
        try eachRow(
            sql: sectionSQL,
            bind: { stmt in
                for (i, uuid) in listUUIDs.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), uuid, -1, Self.SQLITE_TRANSIENT)
                }
            }
        ) { stmt in
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let namePtr = sqlite3_column_text(stmt, 1) else { return }
            let canonical = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let id = String(cString: idPtr)
            sectionsByID[id] = SectionInfo(
                id: id,
                name: String(cString: namePtr),
                canonicalName: canonical?.isEmpty == false ? canonical : nil
            )
        }

        // 2) Read each list's membership blob and decode it. We don't
        //    care about modifiedOn — the latest data wins implicitly.
        let membershipSQL = """
            SELECT ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA
            FROM ZREMCDBASELIST
            WHERE ZMARKEDFORDELETION = 0
              AND ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA IS NOT NULL
              AND ZCKIDENTIFIER IN (\(placeholders))
            """

        var out: [String: SectionInfo] = [:]
        try eachRow(
            sql: membershipSQL,
            bind: { stmt in
                for (i, uuid) in listUUIDs.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), uuid, -1, Self.SQLITE_TRANSIENT)
                }
            }
        ) { stmt in
            guard let blobPtr = sqlite3_column_blob(stmt, 0) else { return }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: blobPtr, count: count)
            guard let parsed = try? JSONDecoder().decode(MembershipBlob.self, from: data) else {
                ReminderDBReader.warnOnce(
                    "section-blob-decode",
                    "Could not decode membership blob; section enrichment partial. (Possible Reminders schema change.)"
                )
                return
            }
            for entry in parsed.memberships {
                // groupID is nil when a reminder lives in a sectioned list
                // but is not in any section (free at the top of the list).
                guard let gid = entry.groupID, let info = sectionsByID[gid] else { continue }
                out[entry.memberID] = info
            }
        }
        return out
    }

    /// Internal Codable mirror of the membership JSON. `modifiedOn` is
    /// captured for completeness even though we don't currently use it.
    /// Internal (not private) so unit tests can construct synthetic blobs
    /// that exercise edge cases the static fixture doesn't cover.
    struct MembershipBlob: Codable {
        let memberships: [Membership]
        struct Membership: Codable {
            // groupID is OPTIONAL: real Reminders blobs include entries for
            // reminders that live in a sectioned list but aren't placed in
            // any section (free items at the top of the list). Those entries
            // contain only `memberID` + `modifiedOn`. Treating groupID as
            // required would throw `keyNotFound` for the whole blob and drop
            // all section info for that list.
            let groupID: String?
            let memberID: String
            let modifiedOn: Double?
        }
    }
}
