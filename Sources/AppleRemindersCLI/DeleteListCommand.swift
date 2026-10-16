import ArgumentParser
import AppleRemindersCore
import Foundation

struct DeleteListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-list",
        abstract: "Permanently delete a reminder list and all reminders it contains"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "List name (case-insensitive). Rejected if multiple lists share the name — use --list-id.")
    var name: String?

    @Option(name: .long, help: "List ID (preferred — unambiguous)")
    var listId: String?

    @Flag(name: .long, help: "Required to delete a list that still contains reminders")
    var force: Bool = false

    func run() async throws {
        let selectorCount = [name != nil, listId != nil].filter { $0 }.count
        guard selectorCount == 1 else {
            throw ValidationError("Specify exactly one of: a list name argument or --list-id")
        }

        let manager = try await createManager(options: globals)
        let selector = listId != nil ? ListSelector(id: listId) : ListSelector(name: name)

        try await withAutoSnapshot(store: manager.store, reason: "delete_list") {
            let deletedId = try await manager.deleteList(selector: selector, force: force)
            // Mirror delete_reminders' shape for consistency.
            let output: [String: Any] = ["deleted": [deletedId], "failed": []]
            try outputJSON(output, pretty: globals.pretty)
        }
    }
}
