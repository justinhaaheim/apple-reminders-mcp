import ArgumentParser
import AppleRemindersCore
import Foundation

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Take a git-backed snapshot of all reminders",
        subcommands: [
            SnapshotTakeCommand.self,
            SnapshotStatusCommand.self,
            SnapshotDiffCommand.self,
        ],
        defaultSubcommand: SnapshotTakeCommand.self
    )
}

struct SnapshotTakeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "take",
        abstract: "Take a snapshot (default action)"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Snapshot repository path (default: ~/.config/apple-reminders-data)")
    var repo: String?

    func run() async throws {
        let manager = try await createManager(options: globals)
        let store = createStore(mock: globals.mock)
        let snapshotManager = SnapshotManager(repoPath: repo, store: store)

        // Request access first (manager already did this, but snapshot needs its own store)
        let result = try await snapshotManager.takeSnapshot()
        try outputJSON(result, pretty: globals.pretty)
    }
}

struct SnapshotStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show snapshot repository status"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Snapshot repository path")
    var repo: String?

    func run() async throws {
        let store = createStore(mock: globals.mock)
        let snapshotManager = SnapshotManager(repoPath: repo, store: store)
        let status = try snapshotManager.getStatus()
        try outputJSON(status, pretty: globals.pretty)
    }
}

struct SnapshotDiffCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Show changes since last snapshot"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Snapshot repository path")
    var repo: String?

    func run() async throws {
        let store = createStore(mock: globals.mock)
        let snapshotManager = SnapshotManager(repoPath: repo, store: store)
        let diff = try snapshotManager.getDiff()
        print(diff)
    }
}
