import Foundation

// MARK: - Snapshot Manager

/// Manages git-backed snapshots of Apple Reminders data.
/// Each snapshot fetches all reminders, writes them as individual JSON files,
/// and commits the state to a local git repository.
public class SnapshotManager {
    private let repoPath: String
    private let store: ReminderStore?

    /// Default snapshot repository location
    public static let defaultRepoPath = "~/.config/apple-reminders-data"

    /// Create a SnapshotManager with a store (required for takeSnapshot).
    /// For getStatus() and getDiff(), the store is not needed.
    public init(repoPath: String? = nil, store: ReminderStore? = nil) {
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
        guard let store = store else {
            throw RemindersError("SnapshotManager requires a ReminderStore to take snapshots")
        }
        let startTime = Date()

        // 1. Ensure repo exists and is initialized
        try ensureRepoExists()

        // 2. Check for uncommitted changes
        try checkCleanState()

        // 3. Fetch all reminders from all lists
        let calendars = store.getAllCalendars()
        let defaultCalendar = store.getDefaultCalendar()
        log("Snapshot: fetching reminders from \(calendars.count) list(s) (this can take a moment for large libraries)")
        let fetchStart = Date()
        let allReminders = await store.fetchReminders(
            in: calendars,
            status: .all,
            dueDateStart: nil,
            dueDateEnd: nil
        )
        let fetchMs = Int(Date().timeIntervalSince(fetchStart) * 1000)
        log("Snapshot: fetched \(allReminders.count) reminders in \(fetchMs)ms")

        // 4. Build list metadata
        let listOutputs = calendars.map { calendar in
            ReminderListOutput(
                id: calendar.id,
                name: calendar.name,
                isDefault: calendar.id == defaultCalendar?.id
            )
        }

        // 5. Write reminders and lists to a temp directory, then atomically swap
        let dataDir = (repoPath as NSString).appendingPathComponent("data/id")
        let tempDir = (repoPath as NSString).appendingPathComponent("data/.id-temp-\(UUID().uuidString)")
        let listsPath = (repoPath as NSString).appendingPathComponent("lists.json")
        let tempListsPath = (repoPath as NSString).appendingPathComponent(".lists-temp-\(UUID().uuidString).json")

        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )

        // 6. Write each reminder as individual JSON file (to temp dir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        log("Snapshot: writing \(allReminders.count) JSON files...")
        let writeStart = Date()
        // Log progress every ~10% of total, or every 500 items, whichever is smaller.
        let progressInterval = max(1, min(500, allReminders.count / 10))

        do {
            for (index, reminder) in allReminders.enumerated() {
                let output = convertToSnapshotOutput(reminder, calendars: calendars, defaultCalendar: defaultCalendar, store: store)
                let jsonData = try encoder.encode(output)
                let filePath = (tempDir as NSString).appendingPathComponent("\(reminder.id).json")
                try jsonData.write(to: URL(fileURLWithPath: filePath))

                let written = index + 1
                if written % progressInterval == 0 && written < allReminders.count {
                    log("Snapshot: wrote \(written)/\(allReminders.count) files")
                }
            }
            let writeMs = Int(Date().timeIntervalSince(writeStart) * 1000)
            log("Snapshot: wrote \(allReminders.count) files in \(writeMs)ms")

            // 7. Write lists.json to temp file first
            let listsData = try encoder.encode(listOutputs)
            try listsData.write(to: URL(fileURLWithPath: tempListsPath))

            // Atomically replace data/id directory using replaceItemAt for crash safety.
            // replaceItemAt handles the swap atomically on APFS/HFS+, avoiding the
            // window where dataDir doesn't exist between remove + move.
            let dataDirURL = URL(fileURLWithPath: dataDir)
            let tempDirURL = URL(fileURLWithPath: tempDir)
            if FileManager.default.fileExists(atPath: dataDir) {
                _ = try FileManager.default.replaceItemAt(dataDirURL, withItemAt: tempDirURL)
            } else {
                try FileManager.default.moveItem(atPath: tempDir, toPath: dataDir)
            }

            // Atomically replace lists.json
            let listsURL = URL(fileURLWithPath: listsPath)
            let tempListsURL = URL(fileURLWithPath: tempListsPath)
            if FileManager.default.fileExists(atPath: listsPath) {
                _ = try FileManager.default.replaceItemAt(listsURL, withItemAt: tempListsURL)
            } else {
                try FileManager.default.moveItem(atPath: tempListsPath, toPath: listsPath)
            }
        } catch {
            // Clean up temp files on failure
            try? FileManager.default.removeItem(atPath: tempDir)
            try? FileManager.default.removeItem(atPath: tempListsPath)
            throw error
        }

        // 8. Git add + commit
        log("Snapshot: committing to git...")
        let commitStart = Date()
        let timestamp = Date().toISO8601WithTimezone()
        let commitMessage = "Snapshot \(timestamp) — \(allReminders.count) reminders, \(calendars.count) lists"
        let diffSummary = try gitAddAndCommit(message: commitMessage)
        let commitMs = Int(Date().timeIntervalSince(commitStart) * 1000)
        log("Snapshot: git commit done in \(commitMs)ms")

        let elapsed = Date().timeIntervalSince(startTime)
        log("Snapshot: complete (\(allReminders.count) reminders, \(calendars.count) lists, \(String(format: "%.2f", elapsed))s total)")

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

    /// Whether a pre-mutation snapshot is warranted given the repo's current state.
    /// Returns true when the repo is uninitialized, has no real `Snapshot`-prefixed
    /// commits yet (e.g. only the auto-init "Initial commit"), or the most recent
    /// snapshot is older than `staleAfterDays`.
    /// On any I/O / git error the caller's context is too uncertain for a meaningful
    /// pre-snapshot, so this returns false (the post-snapshot will still run).
    public func needsPreSnapshot(staleAfterDays: Int = 7) -> Bool {
        do {
            let status = try getStatus()
            if !status.initialized { return true }
            guard let lastMessage = status.lastCommitMessage,
                  lastMessage.hasPrefix("Snapshot ") else {
                // Only "Initial commit" or some non-snapshot commit on top — no
                // real snapshot exists yet, take a pre-snapshot.
                return true
            }
            guard let lastDateString = status.lastSnapshotDate,
                  let lastDate = Date.fromISO8601(lastDateString) else {
                return true
            }
            let staleCutoff = Date().addingTimeInterval(-Double(staleAfterDays) * 86400)
            return lastDate < staleCutoff
        } catch {
            return false
        }
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

    /// Show what changed in the last snapshot.
    public func getDiff() throws -> String {
        // Check if there's more than one commit
        let count = Int(try runGit("rev-list", "--count", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if count < 2 {
            return "Only one snapshot exists — no previous snapshot to compare against."
        }
        return try runGit("show", "--stat", "--format=%s%n", "HEAD")
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
            // Configure local git user so commits work even without global config
            try runGit("config", "user.email", "noreply@apple-reminders-tools.local")
            try runGit("config", "user.name", "Apple Reminders Tools")
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
        return try runGitArgs(args, expectedExitCodes: [0])
    }

    /// Run git, draining stdout/stderr concurrently to avoid the classic
    /// Process pipe-buffer deadlock when output exceeds ~64 KB (the macOS
    /// pipe buffer size). With 10k+ snapshot files this happens immediately
    /// on `git status --porcelain`, `git diff --stat`, etc. Reads happen on
    /// background queues so neither pipe can fill while we're blocked on the
    /// other.
    @discardableResult
    private func runGitArgs(_ args: [String], expectedExitCodes: [Int32]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async(group: group) {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        queue.async(group: group) {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        group.wait()

        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        if !expectedExitCodes.contains(exitCode) {
            // git commit returns exit 1 when nothing to commit — handle gracefully.
            if args.first == "commit" && (output + errorOutput).contains("nothing to commit") {
                return "nothing to commit"
            }
            let details = errorOutput.isEmpty ? output : errorOutput
            throw RemindersError("git \(args.joined(separator: " ")) failed (exit \(exitCode)): \(details)")
        }

        return output
    }

    /// Returns the exit code without throwing for non-zero. Used for plumbing
    /// commands like `git diff --cached --quiet` where the exit code itself
    /// is the answer (0 = clean, 1 = differences).
    private func runGitExitCode(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        // Suppress output; we only want the exit code.
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func gitAddAndCommit(message: String) throws -> String {
        // Each step here can be slow on first snapshot (10k+ new files), so
        // log timings — that's the only signal a watching user has to know
        // whether things are progressing.

        log("Snapshot: git add -A...")
        let addStart = Date()
        try runGit("add", "-A")
        log("Snapshot: git add done in \(Int(Date().timeIntervalSince(addStart) * 1000))ms")

        // Has anything actually staged? `git diff --cached --quiet` returns
        // exit 0 if no staged changes, 1 if changes exist. No large output.
        // (The previous implementation called `git status --porcelain`, which
        // emits one line per staged file — fine for small repos but pipe-
        // deadlock-prone for thousands.)
        log("Snapshot: checking for staged changes...")
        let diffExitCode = try runGitExitCode("diff", "--cached", "--quiet")
        if diffExitCode == 0 {
            log("Snapshot: no staged changes — skipping commit")
            return "no changes"
        }

        log("Snapshot: git commit...")
        let commitStart = Date()
        _ = try runGit("commit", "-m", message)
        log("Snapshot: git commit done in \(Int(Date().timeIntervalSince(commitStart) * 1000))ms")

        log("Snapshot: building diff summary...")
        let summaryStart = Date()
        // --shortstat collapses a (potentially huge) per-file --stat output
        // into one line: "N files changed, M insertions(+), K deletions(-)".
        let diffStat = try runGit("diff", "--shortstat", "HEAD~1..HEAD")
        log("Snapshot: diff summary done in \(Int(Date().timeIntervalSince(summaryStart) * 1000))ms")
        return diffStat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertToSnapshotOutput(
        _ reminder: Reminder,
        calendars: [ReminderCalendar],
        defaultCalendar: ReminderCalendar?,
        store: ReminderStore
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
