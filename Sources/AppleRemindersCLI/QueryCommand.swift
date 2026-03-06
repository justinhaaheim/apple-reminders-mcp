import ArgumentParser
import AppleRemindersCore
import Foundation

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Search and filter reminders"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Filter by list name")
    var list: String?

    @Option(name: .long, help: "Filter by list ID")
    var listId: String?

    @Flag(name: .long, help: "Search across all lists")
    var allLists: Bool = false

    @Option(name: .long, help: "Status filter: incomplete, completed, or all")
    var status: String?

    @Option(name: .long, help: "Search text in titles and notes")
    var search: String?

    @Option(name: .long, help: "Sort by: newest, oldest, priority, dueDate")
    var sort: String?

    @Option(name: .long, help: "Maximum number of results (default: 50, max: 200)")
    var limit: Int?

    @Option(name: .long, help: "Date range start (ISO 8601)")
    var from: String?

    @Option(name: .long, help: "Date range end (ISO 8601)")
    var to: String?

    @Option(name: .long, help: "JMESPath query expression")
    var jmespath: String?

    @Option(name: .long, help: "Output detail level: minimal, compact, full")
    var detail: String?

    func run() async throws {
        let manager = try await createManager(options: globals)

        let listSelector: ListSelector?
        if allLists {
            listSelector = ListSelector(all: true)
        } else if let listId = listId {
            listSelector = ListSelector(id: listId)
        } else if let list = list {
            listSelector = ListSelector(name: list)
        } else {
            listSelector = nil
        }

        let result = try await manager.queryReminders(
            list: listSelector,
            status: status,
            sortBy: sort,
            query: jmespath,
            limit: limit,
            searchText: search,
            dateFrom: from,
            dateTo: to,
            outputDetail: detail
        )

        try outputJSON(result, pretty: globals.pretty)
    }
}
