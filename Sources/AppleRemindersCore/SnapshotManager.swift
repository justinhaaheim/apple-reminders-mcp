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

        // Capture the cutoff for the NEXT snapshot BEFORE we fetch. Anything
        // modified during the fetch will land at or after this instant, so the
        // next snapshot will pick those changes up. Conservative — we may
        // re-export a few unchanged reminders next time, but we never miss.
        let snapshotCutoff = Date()

        // 3. Read previous snapshot state (cutoff timestamp from last run).
        //    Absent → fall back to a full snapshot.
        let previousState = readSnapshotState()
        let previousCutoff = previousState.flatMap { Date.fromISO8601($0.lastSnapshotAt) }

        // 4. Fetch all reminders from all lists. Even in incremental mode we
        //    need the full set to detect deletes and to write the per-fetch
        //    lists.json. EventKit doesn't expose a "modified-since" predicate.
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

        // 5. Build list metadata.
        let listOutputs = calendars.map { calendar in
            ReminderListOutput(
                id: calendar.id,
                name: calendar.name,
                isDefault: calendar.id == defaultCalendar?.id
            )
        }

        // 6. Decide mode (incremental vs. full re-export). Reminder JSON files
        //    no longer embed listName (consumers join via lists.json), so a
        //    list rename does NOT force a full re-export. List membership
        //    changes update each affected reminder's modifiedDate in EventKit
        //    (verified empirically), so incremental picks them up via the
        //    listId field.
        let dataDir = (repoPath as NSString).appendingPathComponent("data/id")
        let listsPath = (repoPath as NSString).appendingPathComponent("lists.json")

        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true
        )

        let mode: SnapshotMode
        if previousState == nil {
            mode = .full(reason: "no previous snapshot state")
        } else if previousState!.schemaVersion != SnapshotState.currentSchemaVersion {
            mode = .full(reason: "schema version changed (was \(previousState!.schemaVersion), now \(SnapshotState.currentSchemaVersion))")
        } else {
            mode = .incremental(cutoff: previousCutoff!)
        }
        log("Snapshot: mode = \(mode.description)")

        // 7. Determine which reminders to write and which files to delete.
        let currentIDs = Set(allReminders.map { $0.id })
        let existingFileIDs = existingReminderFileIDs(dataDir: dataDir)

        let toWrite: [Reminder]
        switch mode {
        case .full:
            toWrite = allReminders
        case .incremental(let cutoff):
            toWrite = allReminders.filter { reminder in
                // No lastModifiedDate? Be safe — treat as changed.
                guard let lm = reminder.lastModifiedDate else { return true }
                return lm >= cutoff
            }
        }
        let toDelete = existingFileIDs.subtracting(currentIDs)

        let unchanged = allReminders.count - toWrite.count
        log("Snapshot: writing \(toWrite.count) changed reminders (\(unchanged) unchanged), deleting \(toDelete.count) removed file(s)")

        // 8. Write reminder JSON files. Each write is per-file atomic via
        //    Data.write(.atomic) — Foundation writes to a temp file in the
        //    same directory and renames over the destination. No directory
        //    swap, so a crash partway through leaves some files updated and
        //    others not — the next snapshot's checkCleanState will surface
        //    the partial state for the user.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let writeStart = Date()
        let progressInterval = max(1, min(500, toWrite.count / 10))

        for (index, reminder) in toWrite.enumerated() {
            let output = convertToSnapshotOutput(reminder)
            let jsonData = try encoder.encode(output)
            let filePath = (dataDir as NSString).appendingPathComponent("\(reminder.id).json")
            try jsonData.write(to: URL(fileURLWithPath: filePath), options: .atomic)

            let written = index + 1
            if written % progressInterval == 0 && written < toWrite.count {
                log("Snapshot: wrote \(written)/\(toWrite.count) files")
            }
        }
        if !toWrite.isEmpty {
            let writeMs = Int(Date().timeIntervalSince(writeStart) * 1000)
            log("Snapshot: wrote \(toWrite.count) files in \(writeMs)ms")
        }

        for id in toDelete {
            let filePath = (dataDir as NSString).appendingPathComponent("\(id).json")
            try? FileManager.default.removeItem(atPath: filePath)
        }
        if !toDelete.isEmpty {
            log("Snapshot: deleted \(toDelete.count) stale reminder file(s)")
        }

        // 9. Always re-export lists.json (one-line change covers list create
        //    / delete / rename without depending on reminder mtime updates).
        let listsData = try encoder.encode(listOutputs)
        try listsData.write(to: URL(fileURLWithPath: listsPath), options: .atomic)

        // 10. Persist new state file with the cutoff for the NEXT snapshot.
        let newState = SnapshotState(
            lastSnapshotAt: snapshotCutoff.toISO8601WithTimezone(),
            schemaVersion: SnapshotState.currentSchemaVersion
        )
        try writeSnapshotState(newState)

        // 11. Git add + commit (no-op if nothing actually changed on disk).
        log("Snapshot: committing to git...")
        let commitStart = Date()
        let timestamp = Date().toISO8601WithTimezone()
        let commitMessage = "Snapshot \(timestamp) — \(allReminders.count) reminders, \(calendars.count) lists"
        let diffSummary = try gitAddAndCommit(message: commitMessage)
        let commitMs = Int(Date().timeIntervalSince(commitStart) * 1000)
        log("Snapshot: git pipeline done in \(commitMs)ms")

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

    /// Snapshot operating mode for one invocation.
    private enum SnapshotMode {
        case full(reason: String)
        case incremental(cutoff: Date)

        var description: String {
            switch self {
            case .full(let reason): return "full (\(reason))"
            case .incremental(let cutoff): return "incremental (cutoff: \(cutoff.toISO8601WithTimezone()))"
            }
        }
    }

    /// Read the persisted snapshot state, or nil if absent / unparseable.
    /// Unparseable = treat as missing → safe fallback to full snapshot.
    private func readSnapshotState() -> SnapshotState? {
        let path = (repoPath as NSString).appendingPathComponent(SnapshotState.fileName)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(SnapshotState.self, from: data)
    }

    private func writeSnapshotState(_ state: SnapshotState) throws {
        let path = (repoPath as NSString).appendingPathComponent(SnapshotState.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// IDs of existing reminder snapshot files in `data/id/` (the `<id>` part
    /// of `<id>.json`). Used to compute deletions in incremental mode.
    private func existingReminderFileIDs(dataDir: String) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dataDir) else {
            return []
        }
        return Set(
            entries
                .filter { $0.hasSuffix(".json") }
                .map { String($0.dropLast(5)) }
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
                """
                Snapshot repository has uncommitted changes at \(repoPath).

                If a previous snapshot was interrupted, you can discard the partial
                state with:
                  cd \(repoPath) && git reset --hard HEAD && git clean -fd

                Otherwise, commit or discard the changes manually before retrying.
                """
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

    private func convertToSnapshotOutput(_ reminder: Reminder) -> SnapshotReminderOutput {
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

        return SnapshotReminderOutput(
            id: reminder.id,
            title: reminder.title,
            notes: reminder.notes,
            listId: reminder.calendarId,
            isCompleted: reminder.isCompleted,
            priority: Priority.fromInternal(reminder.priority).rawValue,
            dueDate: dueDate,
            dueDateIncludesTime: reminder.dueDateComponents != nil ? !reminder.isAllDay : nil,
            completedDate: reminder.completionDate?.toISO8601WithTimezone(),
            createdDate: reminder.creationDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            modifiedDate: reminder.lastModifiedDate?.toISO8601WithTimezone() ?? Date().toISO8601WithTimezone(),
            url: reminder.url?.absoluteString,
            alarms: alarmOutputs,
            recurrenceRules: recurrenceOutputs
        )
    }
}

// MARK: - Snapshot Output Types

/// Per-reminder JSON record written to `<repo>/data/id/<id>.json`.
///
/// Differences from `ReminderOutput`:
/// - **No `listName`.** The list name lives once in `lists.json`; consumers
///   join via `listId`. Avoids re-writing every reminder file when a list
///   is renamed (EventKit doesn't bump per-reminder modifiedDate on list
///   rename, so leaving listName here would silently drift).
/// - **ISO 8601 strings only.** No `*Ms` epoch variants. The ISO strings are
///   sortable lexically and round-trip via `Date.fromISO8601`.
public struct SnapshotReminderOutput: Codable {
    public let id: String
    public let title: String
    public let notes: String?
    public let listId: String
    public let isCompleted: Bool
    public let priority: String
    public let dueDate: String?
    public let dueDateIncludesTime: Bool?
    public let completedDate: String?
    public let createdDate: String
    public let modifiedDate: String
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

/// On-disk record of the most recent snapshot's cutoff timestamp. Persisted
/// at `<repoPath>/snapshot-state.json` and read by the next snapshot to
/// decide what to re-export.
///
/// `lastSnapshotAt` is captured *just before* the EventKit fetch — anything
/// modified at or after this instant is included in the next snapshot.
/// `schemaVersion` lets us evolve the format if needed.
public struct SnapshotState: Codable {
    /// Bump this when the on-disk snapshot file format changes in a way that
    /// requires re-writing existing files (e.g. dropped fields, renamed
    /// fields). On schema mismatch the next snapshot does a full re-export.
    /// History:
    ///   1: initial format with listName + Ms epoch variants
    ///   2: dropped listName (joined via lists.json), dropped Ms variants,
    ///      renamed completionDate→completedDate, lastModifiedDate→modifiedDate
    public static let currentSchemaVersion = 2
    public static let fileName = "snapshot-state.json"

    public let lastSnapshotAt: String
    public let schemaVersion: Int

    public init(lastSnapshotAt: String, schemaVersion: Int) {
        self.lastSnapshotAt = lastSnapshotAt
        self.schemaVersion = schemaVersion
    }
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
