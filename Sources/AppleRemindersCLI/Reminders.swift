import ArgumentParser
import AppleRemindersCore
import Foundation

@main
struct Reminders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Apple Reminders CLI — query, create, update, and manage reminders",
        version: appVersion,
        subcommands: [
            QueryCommand.self,
            ListsCommand.self,
            CreateCommand.self,
            CreateListCommand.self,
            UpdateCommand.self,
            DeleteCommand.self,
            ExportCommand.self,
            SnapshotCommand.self,
            AuditCommand.self,
            HashtagsCommand.self,
            MCPCommand.self,
        ],
        defaultSubcommand: QueryCommand.self
    )

    // Intercept --help --verbose and --help=skill before ArgumentParser runs
    static func main() async {
        HelpSystem.interceptIfNeeded()
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Flag(name: .long, help: "Use mock store (for testing)")
    var mock: Bool = false

    @Flag(name: .long, help: "Enable test mode restrictions")
    var testMode: Bool = false

    @Flag(name: .long, help: "Show debug logging on stderr")
    var verbose: Bool = false
}

// MARK: - Store Factory

func createStore(mock: Bool) -> ReminderStore {
    if mock || MockModeConfig.isEnabled {
        return MockReminderStore()
    }
    #if canImport(EventKit)
    return EKReminderStore()
    #else
    return MockReminderStore()
    #endif
}

func createManager(options: GlobalOptions) async throws -> RemindersManager {
    if options.testMode {
        setenv(TestModeConfig.envVar, "1", 1)
    }
    let store = createStore(mock: options.mock)
    // Discover SQLite enrichment stores. Returns [] (with one stderr
    // warning) when the calling terminal lacks Full Disk Access — the
    // manager degrades gracefully in that case.
    let dbReaders = options.mock ? [] : ReminderDBReader.discover()
    let manager = RemindersManager(store: store, dbReaders: dbReaders)
    try await manager.requestAccess()
    return manager
}

// MARK: - Auto-Snapshot Wrapper

/// Environment variable that opts in to CLI auto-snapshots.
let cliSnapshotEnvVar = "AR_SNAPSHOT_ENABLED"

/// Wraps a mutation closure with optional auto-snapshotting.
///
/// When `AR_SNAPSHOT_ENABLED=1` is set, this:
///   1. Takes a pre-mutation snapshot if the repo is stale (uninitialized,
///      no real snapshot commits yet, or last snapshot > 7 days old).
///   2. Runs the mutation closure.
///   3. Takes a post-mutation snapshot.
///
/// Snapshot failures (either pre or post) print a warning to stderr and never
/// abort the mutation — the user's primary intent is the mutation itself.
/// Repo path resolves via `--repo` flag → `AR_SNAPSHOT_REPO` env var → default.
func withAutoSnapshot<T>(
    store: ReminderStore,
    reason: String,
    repoPath: String? = nil,
    _ work: () async throws -> T
) async throws -> T {
    let enabled = ProcessInfo.processInfo.environment[cliSnapshotEnvVar] == "1"
    guard enabled else {
        return try await work()
    }

    let snapshotManager = SnapshotManager(repoPath: repoPath, store: store)

    if snapshotManager.needsPreSnapshot() {
        await tryAutoSnapshot(snapshotManager, reason: "pre \(reason)")
    }

    let result = try await work()

    await tryAutoSnapshot(snapshotManager, reason: "post \(reason)")
    return result
}

private func tryAutoSnapshot(_ manager: SnapshotManager, reason: String) async {
    fputs("Auto-snapshot (\(reason)) starting...\n", stderr)
    do {
        let result = try await manager.takeSnapshot()
        fputs(
            "Auto-snapshot (\(reason)) done: \(result.reminderCount) reminders, \(result.listCount) lists in \(String(format: "%.2f", result.elapsedSeconds))s\n",
            stderr
        )
    } catch {
        fputs(
            "Warning: auto-snapshot (\(reason)) failed: \(error.localizedDescription)\n",
            stderr
        )
    }
}

// MARK: - JSON Output

func outputJSON(_ value: Any, pretty: Bool) throws {
    let data: Data
    if let encodable = value as? Encodable {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        data = try encoder.encode(AnyEncodable(encodable))
    } else {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            : [.sortedKeys, .fragmentsAllowed]
        data = try JSONSerialization.data(withJSONObject: value, options: options)
    }

    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

