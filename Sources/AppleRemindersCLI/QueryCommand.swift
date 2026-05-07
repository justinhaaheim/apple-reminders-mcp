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

    @Option(name: .long, help: "Results per page (auto-paginates at 200 when omitted)")
    var perPage: Int?

    @Option(name: .long, help: "Opaque cursor from previous response's pageInfo.endCursor for next page")
    var cursor: String?

    @Option(name: .long, help: "Filter by createdDate >= this ISO 8601 date (or YYYY-MM-DD)")
    var createdFrom: String?

    @Option(name: .long, help: "Filter by createdDate <= this ISO 8601 date (or YYYY-MM-DD)")
    var createdTo: String?

    @Option(name: .long, help: "Filter by lastModifiedDate >= this ISO 8601 date (or YYYY-MM-DD)")
    var modifiedFrom: String?

    @Option(name: .long, help: "Filter by lastModifiedDate <= this ISO 8601 date (or YYYY-MM-DD)")
    var modifiedTo: String?

    @Option(name: .long, help: "Filter by dueDate >= this ISO 8601 date (or YYYY-MM-DD)")
    var dueFrom: String?

    @Option(name: .long, help: "Filter by dueDate <= this ISO 8601 date (or YYYY-MM-DD)")
    var dueTo: String?

    @Option(name: .long, help: "Output detail level: minimal, compact, full")
    var detail: String?

    @Argument(help: "Optional JMESPath expression. CLI flags above filter at fetch time; this expression then filters/projects the result. Example: \"[?priority == 'high']\"")
    var query: String?

    private static let validStatuses = ["incomplete", "completed", "all"]
    private static let validSorts = ["newest", "oldest", "priority", "dueDate"]
    private static let validDetails = ["minimal", "compact", "full"]

    func run() async throws {
        // Validate enum-like options
        if let status = status, !Self.validStatuses.contains(status) {
            throw ValidationError("Invalid --status '\(status)'. Must be one of: \(Self.validStatuses.joined(separator: ", "))")
        }
        if let sort = sort, !Self.validSorts.contains(sort) {
            throw ValidationError("Invalid --sort '\(sort)'. Must be one of: \(Self.validSorts.joined(separator: ", "))")
        }
        if let detail = detail, !Self.validDetails.contains(detail) {
            throw ValidationError("Invalid --detail '\(detail)'. Must be one of: \(Self.validDetails.joined(separator: ", "))")
        }

        // Validate list selector mutual exclusivity
        let listOptionCount = [list != nil, listId != nil, allLists].filter { $0 }.count
        if listOptionCount > 1 {
            throw ValidationError("Specify only one of --list, --list-id, or --all-lists")
        }

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
            query: query,
            perPage: perPage,
            cursor: cursor,
            searchText: search,
            createdFrom: createdFrom,
            createdTo: createdTo,
            modifiedFrom: modifiedFrom,
            modifiedTo: modifiedTo,
            dueFrom: dueFrom,
            dueTo: dueTo,
            outputDetail: detail
        )

        try outputJSON(result, pretty: globals.pretty)
    }
}
