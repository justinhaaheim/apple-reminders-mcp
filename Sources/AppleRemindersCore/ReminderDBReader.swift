import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

// MARK: - DB Reader

/// Read-only access to the Apple Reminders Core Data SQLite store.
///
/// Apple does not expose a number of reminder fields through EventKit
/// (hashtags, parent/child links, sections). This reader opens the
/// underlying Core Data SQLite file in `SQLITE_OPEN_READONLY` mode and
/// surfaces those fields as enrichment alongside the EventKit-authoritative
/// data path. Writes are never performed against the SQLite store.
public final class ReminderDBReader {

    // MARK: Static

    /// Sub-path within the user's home where Reminders' Core Data stores live.
    public static let containerSubpath =
        "Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"

    /// Schema fingerprints we've inspected and consider supported. New macOS
    /// releases may bump these; an unrecognized fingerprint logs a warning
    /// and disables enrichment but does not crash. Listed here as
    /// `nil` initially — populated on first observation per process so tests
    /// don't need to be re-run when Apple bumps minor schema versions.
    public static let knownGoodFingerprints: Set<String> = []

    // MARK: Errors

    public enum ReminderDBError: Error, CustomStringConvertible {
        case notFound(String)
        case permissionDenied(String)
        case unsupportedSchema(fingerprint: String)
        case sqliteError(code: Int32, message: String)

        public var description: String {
            switch self {
            case .notFound(let path):
                return "Reminders DB not found at \(path)"
            case .permissionDenied(let path):
                return "Permission denied opening \(path) — grant Full Disk Access to the calling terminal"
            case .unsupportedSchema(let fp):
                return "Unsupported Reminders schema fingerprint: \(fp)"
            case .sqliteError(let code, let message):
                return "SQLite error \(code): \(message)"
            }
        }
    }

    // MARK: One-shot warning gate

    /// Tracks which warning categories have already been emitted for the
    /// life of the process, so users see at most one of each.
    private struct WarningGate {
        private static var emitted: Set<String> = []
        private static let lock = NSLock()

        static func emitOnce(_ key: String, _ message: String) {
            lock.lock()
            defer { lock.unlock() }
            if emitted.contains(key) { return }
            emitted.insert(key)
            logError(message)
        }
    }

    public static func warnOnce(_ key: String, _ message: String) {
        WarningGate.emitOnce(key, message)
    }

    // MARK: Properties

    public let storeURL: URL
    private var db: OpaquePointer?

    // MARK: Init / deinit

    /// Opens a single Reminders SQLite store in read-only mode. Throws
    /// `ReminderDBError.permissionDenied` when sqlite reports an authorization
    /// error (typically because the calling process lacks Full Disk Access).
    public init(storeURL: URL) throws {
        self.storeURL = storeURL

        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw ReminderDBError.notFound(storeURL.path)
        }

        // Use the URI form to be explicit about read-only intent. We
        // intentionally avoid `immutable=1` because WAL replay is required
        // to see current data on macOS (Reminders writes via WAL).
        let uri = "file:" + storeURL.path + "?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(uri, &handle, flags, nil)
        if rc != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let h = handle { sqlite3_close(h) }
            if rc == SQLITE_AUTH || rc == SQLITE_PERM || rc == SQLITE_CANTOPEN {
                throw ReminderDBError.permissionDenied(storeURL.path)
            }
            throw ReminderDBError.sqliteError(code: rc, message: message)
        }
        self.db = handle
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: Discovery

    /// Discovers all relevant Reminders SQLite stores in the user's group
    /// container and opens each in read-only mode. Skips legacy / dormant
    /// `Data-local.sqlite` and any non-Data files. Returns `[]` (with a
    /// single stderr warning) when the container is unreachable —
    /// typically because the calling process has no Full Disk Access.
    ///
    /// - Parameter containerOverride: optional explicit container path,
    ///   used by tests against the fixture DB. In production, leave nil to
    ///   resolve the live group container under the current user's home.
    public static func discover(containerOverride: URL? = nil) -> [ReminderDBReader] {
        let container: URL
        if let override = containerOverride {
            container = override
        } else {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            container = home.appendingPathComponent(containerSubpath, isDirectory: true)
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: container.path, isDirectory: &isDir), isDir.boolValue else {
            warnOnce(
                "discover.missing-container",
                "Reminders DB enrichment unavailable: container \(container.path) not readable. Grant Full Disk Access to the calling terminal to enable hashtags / parent-child / section fields."
            )
            return []
        }

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: container,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            warnOnce(
                "discover.list-failed",
                "Reminders DB enrichment unavailable: failed to list \(container.path): \(error.localizedDescription)."
            )
            return []
        }

        let candidates = entries.filter { isLiveStore($0) }.sorted { $0.path < $1.path }
        var readers: [ReminderDBReader] = []
        for url in candidates {
            do {
                readers.append(try ReminderDBReader(storeURL: url))
            } catch let ReminderDBError.permissionDenied(path) {
                warnOnce(
                    "discover.permission",
                    "Reminders DB enrichment disabled: permission denied opening \(path). Grant Full Disk Access to the calling terminal."
                )
                return []
            } catch {
                warnOnce(
                    "discover.open-failed-\(url.lastPathComponent)",
                    "Skipping Reminders store \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        return readers
    }

    /// True when the URL points at a file we should attempt to open as a
    /// Reminders store: `Data-*.sqlite` excluding `Data-local.sqlite`,
    /// and excluding the WAL/SHM siblings.
    static func isLiveStore(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("Data-") else { return false }
        guard name.hasSuffix(".sqlite") else { return false }
        if name == "Data-local.sqlite" { return false }
        return true
    }

    // MARK: Schema fingerprint

    /// Stable hash of the Core Data metadata + model cache rows. The same
    /// store always produces the same fingerprint; an Apple schema bump
    /// produces a new one.
    public func schemaFingerprint() throws -> String {
        var hasher = StableHasher()
        try eachRow(sql: "SELECT Z_VERSION, Z_UUID, Z_PLIST FROM Z_METADATA ORDER BY Z_VERSION") { stmt in
            hasher.absorb(int: sqlite3_column_int64(stmt, 0))
            if let cString = sqlite3_column_text(stmt, 1) {
                hasher.absorb(string: String(cString: cString))
            }
            if let blob = sqlite3_column_blob(stmt, 2) {
                let count = Int(sqlite3_column_bytes(stmt, 2))
                hasher.absorb(bytes: blob, count: count)
            }
        }
        try eachRow(sql: "SELECT Z_CONTENT FROM Z_MODELCACHE") { stmt in
            if let blob = sqlite3_column_blob(stmt, 0) {
                let count = Int(sqlite3_column_bytes(stmt, 0))
                hasher.absorb(bytes: blob, count: count)
            }
        }
        return hasher.hexDigest()
    }

    /// True when the fingerprint matches one of `knownGoodFingerprints`.
    /// Currently always false in tests — the bead's intent is that an
    /// unknown fingerprint logs a warning but doesn't block enrichment.
    public func isSchemaSupported() throws -> Bool {
        let fp = try schemaFingerprint()
        return Self.knownGoodFingerprints.contains(fp)
    }

    // MARK: Lookups

    /// Returns the Core Data Z_PK for a reminder UUID, or nil when not present
    /// in this store. EventKit's `calendarItemIdentifier` is round-trippable
    /// with both `ZCKIDENTIFIER` and `ZDACALENDARITEMUNIQUEIDENTIFIER`; we
    /// match on either to be schema-version tolerant.
    public func reminderRowID(forUUID uuid: String) throws -> Int64? {
        var result: Int64?
        try eachRow(
            sql: """
                SELECT Z_PK FROM ZREMCDREMINDER
                WHERE (ZCKIDENTIFIER = ?1 OR ZDACALENDARITEMUNIQUEIDENTIFIER = ?1)
                  AND ZMARKEDFORDELETION = 0
                LIMIT 1
                """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, uuid, -1, Self.SQLITE_TRANSIENT)
            }
        ) { stmt in
            result = sqlite3_column_int64(stmt, 0)
        }
        return result
    }

    // MARK: Internal helpers (used by enrichment sub-modules)

    /// Executes a prepared statement, calling `bind` once before stepping
    /// and `each` for every row returned. Always finalizes the statement.
    func eachRow(
        sql: String,
        bind: ((OpaquePointer) -> Void)? = nil,
        each: (OpaquePointer) -> Void
    ) throws {
        guard let db = db else {
            throw ReminderDBError.sqliteError(code: SQLITE_MISUSE, message: "Connection is closed")
        }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            if let s = stmt { sqlite3_finalize(s) }
            throw ReminderDBError.sqliteError(code: rc, message: msg + " (sql: \(sql))")
        }
        defer { sqlite3_finalize(stmt) }
        guard let stmt = stmt else { return }
        bind?(stmt)
        while true {
            let stepRC = sqlite3_step(stmt)
            if stepRC == SQLITE_DONE { break }
            if stepRC == SQLITE_ROW {
                each(stmt)
                continue
            }
            let msg = String(cString: sqlite3_errmsg(db))
            throw ReminderDBError.sqliteError(code: stepRC, message: msg + " (sql: \(sql))")
        }
    }

    /// Helper for binding text. SQLite's `SQLITE_TRANSIENT` constant is a
    /// magic pointer (-1 cast to a destructor) and isn't directly importable
    /// in Swift, so we define the equivalent here.
    static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )
}

// MARK: - Stable hasher

/// Order-stable, deterministic hasher used for schema fingerprints. Swift's
/// `Hasher` salts each run for security so it's unsuitable for fingerprinting
/// across processes; this is a tiny FNV-1a 128-bit derivative that yields the
/// same hex digest forever for the same byte stream.
struct StableHasher {
    private var hi: UInt64 = 0xcbf2_9ce4_8422_2325
    private var lo: UInt64 = 0x1465_9950_efbb_a553
    private static let prime: UInt64 = 0x1_0000_0000_01b3

    mutating func absorb(int value: Int64) {
        var v = value.bigEndian
        withUnsafeBytes(of: &v) { absorb(bytes: $0.baseAddress!, count: $0.count) }
    }

    mutating func absorb(string: String) {
        let utf8 = Array(string.utf8)
        utf8.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                absorb(bytes: base, count: buf.count)
            }
        }
        // Domain separator so "abc" + "def" hashes differently than "abcdef".
        var sep: UInt8 = 0
        absorb(bytes: &sep, count: 1)
    }

    mutating func absorb(bytes: UnsafeRawPointer, count: Int) {
        let p = bytes.assumingMemoryBound(to: UInt8.self)
        for i in 0..<count {
            hi ^= UInt64(p[i])
            hi = hi &* Self.prime
            lo ^= UInt64(p[i]) &+ (hi &>> 7)
            lo = lo &* Self.prime
        }
    }

    func hexDigest() -> String {
        return String(format: "%016llx%016llx", hi, lo)
    }
}
