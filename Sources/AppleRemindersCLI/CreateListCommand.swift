import ArgumentParser
import AppleRemindersCore
import Foundation

struct CreateListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-list",
        abstract: "Create a new reminder list"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Name for the new list")
    var name: String

    func run() async throws {
        let manager = try await createManager(options: globals)

        try await withAutoSnapshot(store: manager.store, reason: "create_list") {
            let list = try manager.createList(name: name)
            try outputJSON(list, pretty: globals.pretty)
        }
    }
}
