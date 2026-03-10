import Foundation

// MARK: - Audit Logger

/// Append-only JSONL audit logger for all mutations.
/// Logs every create, update, and delete operation with timestamp, action,
/// arguments, result, and before-state (for updates/deletes).
///
/// Log files are stored per-day in ~/.config/apple-reminders-tools/logs/
/// as JSONL (one JSON object per line).
public class AuditLogger {

    /// Shared singleton instance. Initialized lazily on first use.
    public static let shared = AuditLogger()

    /// Session ID for correlating log entries within a single process lifetime.
    public let sessionId: String

    /// The source surface (cli or mcp).
    public var source: String = "cli"

    /// Base directory for log files.
    private let logDirectory: URL

    /// Date formatter for log file names (one file per day).
    private let fileDateFormatter: DateFormatter

    /// ISO 8601 formatter for timestamps.
    private let isoFormatter: ISO8601DateFormatter

    /// Whether audit logging is enabled. Defaults to true.
    public var isEnabled: Bool = true

    private init() {
        self.sessionId = UUID().uuidString.prefix(8).lowercased().description

        // ~/.config/apple-reminders-tools/logs/
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("apple-reminders-tools")
            .appendingPathComponent("logs")
        self.logDirectory = configDir

        self.fileDateFormatter = DateFormatter()
        self.fileDateFormatter.dateFormat = "yyyy-MM-dd"

        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    // MARK: - Public API

    /// Log a create operation.
    public func logCreate(
        action: String,
        args: [String: Any],
        result: AuditResult,
        response: [String: Any]? = nil
    ) {
        writeEntry(AuditEntry(
            timestamp: isoFormatter.string(from: Date()),
            action: action,
            args: args,
            result: result,
            response: response,
            beforeState: nil,
            context: makeContext()
        ))
    }

    /// Log an update operation with before-state.
    public func logUpdate(
        action: String,
        args: [String: Any],
        result: AuditResult,
        response: [String: Any]? = nil,
        beforeState: [String: Any]? = nil
    ) {
        writeEntry(AuditEntry(
            timestamp: isoFormatter.string(from: Date()),
            action: action,
            args: args,
            result: result,
            response: response,
            beforeState: beforeState,
            context: makeContext()
        ))
    }

    /// Log a delete operation with before-state.
    public func logDelete(
        action: String,
        args: [String: Any],
        result: AuditResult,
        beforeState: [String: Any]? = nil
    ) {
        writeEntry(AuditEntry(
            timestamp: isoFormatter.string(from: Date()),
            action: action,
            args: args,
            result: result,
            response: nil,
            beforeState: beforeState,
            context: makeContext()
        ))
    }

    /// Get recent audit log entries. Returns entries from the last N days (default: 7).
    public func getRecentEntries(days: Int = 7) -> [String] {
        var allLines: [String] = []
        let calendar = Calendar.current

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let filename = fileDateFormatter.string(from: date) + ".jsonl"
            let fileURL = logDirectory.appendingPathComponent(filename)

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            allLines.append(contentsOf: lines)
        }

        return allLines
    }

    /// Get log file paths that exist.
    public func getLogFiles() -> [(path: String, date: String, sizeBytes: Int)] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> (path: String, date: String, sizeBytes: Int)? in
                let filename = url.deletingPathExtension().lastPathComponent
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return (path: url.path, date: filename, sizeBytes: size)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Private

    private func makeContext() -> [String: String] {
        return [
            "source": source,
            "sessionId": sessionId,
        ]
    }

    private func writeEntry(_ entry: AuditEntry) {
        guard isEnabled else { return }

        do {
            // Ensure log directory exists
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

            // Determine file for today
            let filename = fileDateFormatter.string(from: Date()) + ".jsonl"
            let fileURL = logDirectory.appendingPathComponent(filename)

            // Serialize entry to JSON
            let jsonData = try JSONSerialization.data(
                withJSONObject: entry.toDictionary(),
                options: [.sortedKeys]
            )

            guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
            jsonString += "\n"

            // Append to file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                if let data = jsonString.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Audit logging should never crash the app — log to stderr and continue
            logError("Audit log write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Audit Types

public enum AuditResult: String {
    case success
    case failure
}

/// Internal representation of a single audit log entry.
private struct AuditEntry {
    let timestamp: String
    let action: String
    let args: [String: Any]
    let result: AuditResult
    let response: [String: Any]?
    let beforeState: [String: Any]?
    let context: [String: String]

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": timestamp,
            "action": action,
            "args": sanitizeForJSON(args),
            "result": result.rawValue,
            "context": context,
        ]

        if let response = response {
            dict["response"] = sanitizeForJSON(response)
        }

        if let beforeState = beforeState {
            dict["beforeState"] = sanitizeForJSON(beforeState)
        }

        return dict
    }

    /// Recursively sanitize a dictionary for JSON serialization.
    /// Replaces non-JSON-compatible types with string representations.
    private func sanitizeForJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { sanitizeForJSON($0) }
        }
        if let array = value as? [Any] {
            return array.map { sanitizeForJSON($0) }
        }
        if value is String || value is Int || value is Double || value is Bool || value is NSNull {
            return value
        }
        // Fall back to string representation
        return String(describing: value)
    }
}
