import ArgumentParser
import AppleRemindersCore
import Foundation

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export reminders to a JSON file"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Output file path (default: temp directory)")
    var path: String?

    @Option(name: .long, help: "Export specific list(s) by name (can be repeated)")
    var list: [String] = []

    @Flag(name: .long, help: "Include completed reminders")
    var includeCompleted: Bool = false

    func run() async throws {
        let manager = try await createManager(options: globals)

        let listSelectors: [ListSelector]? = list.isEmpty
            ? nil
            : list.map { ListSelector(name: $0) }

        let result = try await manager.exportReminders(
            path: path,
            lists: listSelectors,
            includeCompleted: includeCompleted
        )

        try outputJSON(result, pretty: globals.pretty)
    }
}
