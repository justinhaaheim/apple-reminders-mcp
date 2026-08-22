import ArgumentParser
import AppleRemindersCore
import Foundation

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Search and filter reminders"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: ArgumentHelp(
        "JMESPath expression applied after CLI flag filters. Use quotes; precede with -- if it starts with '-'.",
        valueName: "query"
    ))
    var query: String?

    @Option(name: .long, help: "Filter by list name")
    var list: String?

    @Option(name: .long, help: "Filter by list ID")
    var listId: String?

    @Flag(name: .long, help: "Search across all lists (default is the configured default list — only widen when the user asks for cross-list results)")
    var allLists: Bool = false

    @Flag(name: .long, help: "Include completed reminders alongside incomplete (default is incomplete only)")
    var includeCompleted: Bool = false

    @Flag(name: .long, help: "Return only completed reminders (mutually exclusive with --include-completed)")
    var completedOnly: Bool = false

    @Option(name: .long, help: "Search text in titles and notes")
    var search: String?

    @Option(name: .long, help: "Sort by: newest, oldest, priority, dueDate")
    var sort: String?

    @Option(name: .long, help: "Results per page (auto-paginates at 200 when omitted)")
    var perPage: Int?

    @Option(name: .long, help: "Opaque cursor from previous response's pageInfo.endCursor for next page")
    var cursor: String?

    @Option(name: .long, help: "Filter by createdDate >= ISO 8601 date (or YYYY-MM-DD)")
    var createdFrom: String?

    @Option(name: .long, help: "Filter by createdDate <= ISO 8601 date (or YYYY-MM-DD)")
    var createdTo: String?

    @Option(name: .long, help: "Filter by lastModifiedDate >= ISO 8601 date (or YYYY-MM-DD)")
    var modifiedFrom: String?

    @Option(name: .long, help: "Filter by lastModifiedDate <= ISO 8601 date (or YYYY-MM-DD)")
    var modifiedTo: String?

    @Option(name: .long, help: "Filter by dueDate >= ISO 8601 date (or YYYY-MM-DD)")
    var dueFrom: String?

    @Option(name: .long, help: "Filter by dueDate <= ISO 8601 date (or YYYY-MM-DD)")
    var dueTo: String?

    @Option(name: .long, help: "Output detail level: minimal, compact, full")
    var detail: String?

    @Option(name: .long, help: "Filter by hashtag (case-insensitive on canonical name)")
    var hashtag: String?

    @Option(name: .long, help: "Filter to direct children of the given reminder UUID (mutually exclusive with --top-level)")
    var parent: String?

    @Flag(name: .long, help: "Filter to top-level reminders only (mutually exclusive with --parent)")
    var topLevel: Bool = false

    @Option(name: .long, help: "Filter by section (matches section UUID or display name, case-insensitive)")
    var section: String?

    private static let validSorts = ["newest", "oldest", "priority", "dueDate"]
    private static let validDetails = ["minimal", "compact", "full"]

    func run() async throws {
        // Validate enum-like options
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

        if includeCompleted && completedOnly {
            throw ValidationError("--include-completed and --completed-only are mutually exclusive")
        }

        if parent != nil && topLevel {
            throw ValidationError("--parent and --top-level are mutually exclusive")
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
            includeCompleted: includeCompleted,
            completedOnly: completedOnly,
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
            outputDetail: detail,
            hashtag: hashtag,
            parentId: parent,
            topLevelOnly: topLevel,
            sectionId: section
        )

        try outputJSON(result, pretty: globals.pretty)
    }
}
