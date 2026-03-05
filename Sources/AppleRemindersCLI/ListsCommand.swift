import ArgumentParser
import AppleRemindersCore
import Foundation

struct ListsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lists",
        abstract: "Get all reminder lists"
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let manager = try await createManager(options: globals)
        let lists = manager.getAllLists()
        try outputJSON(lists, pretty: globals.pretty)
    }
}
