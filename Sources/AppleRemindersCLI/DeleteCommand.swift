import ArgumentParser
import AppleRemindersCore
import Foundation

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete one or more reminders"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(parsing: .remaining, help: "Reminder IDs to delete")
    var ids: [String]

    func run() async throws {
        guard !ids.isEmpty else {
            fputs("Error: At least one reminder ID is required\n", stderr)
            throw ExitCode.failure
        }

        let manager = try await createManager(options: globals)
        let result = manager.deleteReminders(ids: ids)

        var output: [String: Any] = [
            "deleted": result.deleted,
            "deletedCount": result.deleted.count,
        ]

        if !result.failed.isEmpty {
            output["failed"] = result.failed.map { ["id": $0.id, "error": $0.error] }
            output["failedCount"] = result.failed.count
        }

        try outputJSON(output, pretty: globals.pretty)

        if !result.failed.isEmpty {
            throw ExitCode.failure
        }
    }
}
