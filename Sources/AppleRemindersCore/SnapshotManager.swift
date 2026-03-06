import Foundation

// MARK: - Snapshot Manager

/// Manages git-backed snapshots of Apple Reminders data.
/// Each snapshot fetches all reminders, writes them as individual JSON files,
/// and commits the state to a local git repository.
public class SnapshotManager {
    private let repoPath: String
    private let store: ReminderStore

    /// Default snapshot repository location
    public static let defaultRepoPath = "~/.config/apple-reminders-data"

    public init(repoPath: String? = nil, store: ReminderStore) {
        let path = repoPath
            ?? ProcessInfo.processInfo.environment["AR_SNAPSHOT_REPO"]
            ?? Self.defaultRepoPath
        self.repoPath = NSString(string: path).expandingTildeInPath
        self.store = store
    }

    // MARK: - Public API

    /// Take a full snapshot of all reminders.
    /// Returns a summary of what changed.
    public func takeSnapshot() async throws -> SnapshotResult {
        let startTime = Date()

        // 1. Ensure repo exists and is initialized
        try ensureRepoExists()

        // 2. Check for uncommitted changes
        try checkCleanState()

        // 3. Fetch all reminders from all lists
        let calendars = store.getAllCalendars()
        let defaultCalendar = store.getDefaultCalendar()
        let allReminders = await store.fetchReminders(in: calendars, status: .all)

        // 4. Build list metadata
        let listOutputs = calendars.map { calendar in
            ReminderListOutput(
                id: calendar.id,
                name: calendar.name,
                isDefault: calendar.id == defaultCalendar?.id
            )
        }

        // 5. Clear data/id/ directory (clean slate)
        let dataDir = (repoPath as NSString).appendingPathComponent("data/id")
        if FileManager.default.fileExists(atPath: dataDir) {
            try FileManager.default.removeItem(atPath: dataDir)
        }
        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true
        )

        // 6. Write each reminder as individual JSON file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        for reminder in allReminders {
            let output = convertToSnapshotOutput(reminder, calendars: calendars, defaultCalendar: defaultCalendar)
            let jsonData = try encoder.encode(output)
            let filePath = (dataDir as NSString).appendingPathComponent("\(reminder.id).json")
            try jsonData.write(to: URL(fileURLWithPath: filePath))
        }

        // 7. Write lists.json
        let listsPath = (repoPath as NSString).appendingPathComponent("lists.json")
        let listsData = try encoder.encode(listOutputs)
        try listsData.write(to: URL(fileURLWithPath: listsPath))

        // 8. Git add + commit
        let timestamp = Date().toISO8601WithTimezone()
        let commitMessage = "Snapshot \(timestamp) — \(allReminders.count) reminders, \(calendars.count) lists"
        let diffSummary = try gitAddAndCommit(message: commitMessage)

        let elapsed = Date().timeIntervalSince(startTime)

        return SnapshotResult(
            timestamp: timestamp,
            reminderCount: allReminders.count,
            listCount: calendars.count,
            commitMessage: commitMessage,
            diffSummary: diffSummary,
            elapsedSeconds: elapsed,
            repoPath: repoPath
        )
    }

    /// Get status of the snapshot repository.
    public func getStatus() throws -> SnapshotStatus {
        let repoExists = FileManager.default.fileExists(
            atPath: (repoPath as NSString).appendingPathComponent(".git")
        )

        guard repoExists else {
            return SnapshotStatus(
                repoPath: repoPath,
                initialized: false,
                lastSnapshotDate: nil,
                lastCommitMessage: nil,
                totalCommits: 0,
                reminderFileCount: 0
            )
        }

        let lastCommit = try? runGit("log", "-1", "--format=%aI|||%s")
        let parts = lastCommit?.split(separator: "|||", maxSplits: 1)
        let lastDate = parts?.first.map(String.init)
        let lastMessage = parts?.last.map(String.init)

        let commitCount = Int(try runGit("rev-list", "--count", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        let dataDir = (repoPath as NSString).appendingPathComponent("data/id")
        let fileCount: Int
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dataDir) {
            fileCount = files.filter { $0.hasSuffix(".json") }.count
        } else {
            fileCount = 0
        }

        return SnapshotStatus(
            repoPath: repoPath,
            initialized: true,
            lastSnapshotDate: lastDate,
            lastCommitMessage: lastMessage,
            totalCommits: commitCount,
            reminderFileCount: fileCount
        )
    }

    /// Show what changed since the last snapshot (git diff summary).
    public func getDiff() throws -> String {
        return try runGit("diff", "--stat", "HEAD")
    }

    // MARK: - Private Helpers

    private func ensureRepoExists() throws {
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")

        if !FileManager.default.fileExists(atPath: repoPath) {
            try FileManager.default.createDirectory(
                atPath: repoPath,
                withIntermediateDirectories: true
            )
        }

        if !FileManager.default.fileExists(atPath: gitDir) {
            try runGit("init")
            log("Initialized snapshot repository at \(repoPath)")

            // Create .gitignore
            let gitignorePath = (repoPath as NSString).appendingPathComponent(".gitignore")
            try ".DS_Store\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
            try runGit("add", ".gitignore")
            try runGit("commit", "-m", "Initial commit")
        }
    }

    private func checkCleanState() throws {
        let status = try runGit("status", "--porcelain")
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RemindersError(
                "Snapshot repository has uncommitted changes. " +
                "Please commit or discard changes before taking a snapshot."
            )
        }
    }

    @discardableResult
    private func runGit(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            // git diff --stat returns exit 0 even with no changes;
            // git commit returns exit 1 when nothing to commit — handle gracefully
            if args.first == "commit" && output.contains("nothing to commit") {
                return "nothing to commit"
            }
            throw RemindersError("git \(args.joined(separator: " ")) failed: \(output)")
        }

        return output
    }

    private func gitAddAndCommit(message: String) throws -> String {
        try runGit("add", "-A")

        // Check if there are actually changes to commit
        let status = try runGit("status", "--porcelain")
        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "no changes"
        }

        let output = try runGit("commit", "-m", message)

        // Extract diff summary (files changed, insertions, deletions)
        let diffStat = try runGit("diff", "--stat", "HEAD~1..HEAD")
        return diffStat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertToSnapshotOutput(
        _ reminder: Reminder,
        calendars: [ReminderCalendar],
        defaultCalendar: ReminderCalendar?
    ) -> SnapshotReminderOutput {
        let listName = reminder.getCalendarName(from: store)

        let alarmOutputs: [AlarmOutput]? = reminder.alarms.isEmpty ? nil : reminder.alarms.map { alarm in
            if let absoluteDate = alarm.absoluteDate {
                return AlarmOutput(type: "absolute", date: absoluteDate.toISO8601WithTimezone(), offset: nil)
            } else {
                return AlarmOutput(type: "relative", date: nil, offset: Int(-(alarm.relativeOffset ?? 0)))
            }
        }

        let recurrenceOutputs: [RecurrenceRuleOutput]? = reminder.recurrenceRules.isEmpty ? nil : reminder.recurrenceRules.map { rule in
            RecurrenceRuleOutput(
                frequency: rule.frequency.rawValue,
                interval: rule.interval,
                daysOfWeek: rule.daysOfWeek,
                daysOfMonth: rule.daysOfMonth,
                monthsOfYear: rule.monthsOfYear,
                weekPosition: rule.weekPosition,
                endDate: rule.endDate?.toISO8601WithTimezone(),
                endCount: rule.endCount
            )
        }

        let dueDate: String? = {
            guard var components = reminder.dueDateComponents else { return nil }
            if components.calendar == nil { components.calendar = Calendar.current }
            return components.date?.toISO8601WithTimezone()
        }()

        let dueDateMS: Int64? = {
            guard var components = reminder.dueDateComponents else { return nil }
            if components.calendar == nil { components.calendar = Calendar.current }
            return components.date.map { Int64($0.timeIntervalSince1970 * 1000) }
        }()

        return SnapshotReminderOutput(
            id: reminder.id,
            title: reminder.title,
            notes: reminder.notes,
            listId: reminder.calendarId,
            listName: listName,
            isCompleted: reminder.isCompleted,
            priority: Priority.fromInternal(reminder.priority).rawValue,
            dueDate: dueDate,
            dueDateIncludesTime: reminder.dueDateComponents != nil ? !reminder.isAllDay : nil,
            dueDateMS: dueDateMS,
            completionDate: reminder.completionDate?.toISO8601WithTimezone(),
            completionDateMS: reminder.completionDate.map { Int64($0.timeIntervalSince1970 * 1000) },
            createdDate: reminder.creationDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            createdDateMS: Int64((reminder.creationDate ?? Date()).timeIntervalSince1970 * 1000),
            lastModifiedDate: reminder.lastModifiedDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            lastModifiedDateMS: Int64((reminder.lastModifiedDate ?? Date()).timeIntervalSince1970 * 1000),
            url: reminder.url?.absoluteString,
            alarms: alarmOutputs,
            recurrenceRules: recurrenceOutputs
        )
    }
}

// MARK: - Snapshot Output Types

/// Extended reminder output with millisecond epoch timestamps for snapshots.
public struct SnapshotReminderOutput: Codable {
    public let id: String
    public let title: String
    public let notes: String?
    public let listId: String
    public let listName: String
    public let isCompleted: Bool
    public let priority: String
    public let dueDate: String?
    public let dueDateIncludesTime: Bool?
    public let dueDateMS: Int64?
    public let completionDate: String?
    public let completionDateMS: Int64?
    public let createdDate: String
    public let createdDateMS: Int64
    public let lastModifiedDate: String
    public let lastModifiedDateMS: Int64
    public let url: String?
    public let alarms: [AlarmOutput]?
    public let recurrenceRules: [RecurrenceRuleOutput]?
}

/// Result of a snapshot operation.
public struct SnapshotResult: Codable {
    public let timestamp: String
    public let reminderCount: Int
    public let listCount: Int
    public let commitMessage: String
    public let diffSummary: String
    public let elapsedSeconds: Double
    public let repoPath: String
}

/// Status of the snapshot repository.
public struct SnapshotStatus: Codable {
    public let repoPath: String
    public let initialized: Bool
    public let lastSnapshotDate: String?
    public let lastCommitMessage: String?
    public let totalCommits: Int
    public let reminderFileCount: Int
}
