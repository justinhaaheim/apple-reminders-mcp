import Foundation

// MARK: - MCP Server

public class MCPServer {
    private let remindersManager: RemindersManager
    private let snapshotManager: SnapshotManager?
    private let snapshotEnabled: Bool

    public init() {
        // Choose store based on mock mode
        let store: ReminderStore
        if MockModeConfig.isEnabled {
            store = MockReminderStore()
        } else {
            #if canImport(EventKit)
            store = EKReminderStore()
            #else
            // EventKit not available (Linux) — force mock mode
            store = MockReminderStore()
            #endif
        }
        self.remindersManager = RemindersManager(store: store)

        // Set audit logger source to MCP
        AuditLogger.shared.source = "mcp"

        // Snapshot support (disabled by default)
        self.snapshotEnabled = ProcessInfo.processInfo.environment["AR_MCP_SNAPSHOT_ENABLED"] == "1"
        if snapshotEnabled {
            let repoPath = ProcessInfo.processInfo.environment["AR_MCP_SNAPSHOT_REPO"]
            self.snapshotManager = SnapshotManager(repoPath: repoPath, store: store)
        } else {
            self.snapshotManager = nil
        }
    }

    public func start() async {
        do {
            try await remindersManager.requestAccess()
            log("Successfully obtained access to Reminders")
        } catch {
            logError("Failed to get access to Reminders: \(error)")
            exit(1)
        }

        if MockModeConfig.isEnabled {
            log("MOCK MODE ENABLED - Using in-memory storage (no real reminders)")
        }

        if TestModeConfig.isEnabled {
            log("TEST MODE ENABLED - Write operations restricted to lists prefixed with '\(TestModeConfig.testListPrefix)'")
        }

        if snapshotEnabled {
            log("SNAPSHOT ENABLED - Auto-snapshotting after write operations")
            // Take initial snapshot on startup
            await autoSnapshot(reason: "session start")
        }

        log("Apple Reminders MCP Server running on stdio")

        while let line = readLine() {
            await handleRequest(line)
        }
    }

    /// Take an automatic snapshot after write operations (if enabled).
    private func autoSnapshot(reason: String) async {
        guard let snapshotManager = snapshotManager else { return }
        do {
            let result = try await snapshotManager.takeSnapshot()
            log("Auto-snapshot (\(reason)): \(result.reminderCount) reminders, \(result.listCount) lists")
        } catch {
            logError("Auto-snapshot failed (\(reason)): \(error.localizedDescription)")
        }
    }

    private func handleRequest(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let request = try JSONDecoder().decode(MCPRequest.self, from: data)
            do {
                let response = try await processRequest(request)
                sendResponse(response)
            } catch {
                logError("Error processing request: \(error)")
                sendErrorResponse(id: request.id, code: -32603, message: error.localizedDescription)
            }
        } catch {
            logError("Error decoding request: \(error)")
            sendErrorResponse(id: .null, code: -32700, message: "Parse error: \(error.localizedDescription)")
        }
    }

    private func sendErrorResponse(id: MCPRequest.RequestID, code: Int, message: String) {
        let errorResponse = MCPResponse(
            id: id,
            result: nil,
            error: MCPResponse.MCPError(code: code, message: message)
        )
        sendResponse(errorResponse)
    }

    private func processRequest(_ request: MCPRequest) async throws -> MCPResponse {
        switch request.method {
        case "initialize":
            let instructions = """
            Apple Reminders MCP Server — Manage Apple Reminders on macOS.

            Call help(tool_name) for documentation on any tool.
            Call help(tool_name, verbose=true) for comprehensive docs with examples.
            Call guidance() for best practices and strategic usage patterns.
            Call schema(tool_name) to inspect input/output schemas.

            Quick start: query_reminders({}) returns incomplete reminders from the default list.
            """

            return MCPResponse(
                id: request.id,
                result: MCPResponse.Result(
                    content: nil,
                    tools: nil,
                    protocolVersion: "2024-11-05",
                    capabilities: MCPResponse.Result.Capabilities(
                        tools: MCPResponse.Result.Capabilities.ToolsCapability(listChanged: false)
                    ),
                    serverInfo: MCPResponse.Result.ServerInfo(
                        name: "apple-reminders",
                        version: appVersion
                    ),
                    instructions: instructions,
                    isError: nil
                ),
                error: nil
            )

        case "tools/list":
            return MCPResponse(
                id: request.id,
                result: MCPResponse.Result(
                    content: nil,
                    tools: getTools(),
                    protocolVersion: nil,
                    capabilities: nil,
                    serverInfo: nil,
                    instructions: nil,
                    isError: nil
                ),
                error: nil
            )

        case "tools/call":
            guard let params = request.params,
                  let toolName = params.name else {
                throw RemindersError("Missing tool name")
            }

            do {
                let resultText = try await callTool(toolName, arguments: params.arguments ?? [:])
                return MCPResponse(
                    id: request.id,
                    result: MCPResponse.Result(
                        content: [MCPResponse.Result.Content(type: "text", text: resultText)],
                        tools: nil,
                        protocolVersion: nil,
                        capabilities: nil,
                        serverInfo: nil,
                        instructions: nil,
                        isError: nil
                    ),
                    error: nil
                )
            } catch {
                // Return tool errors with isError: true
                let errorMessage = error.localizedDescription
                return MCPResponse(
                    id: request.id,
                    result: MCPResponse.Result(
                        content: [MCPResponse.Result.Content(type: "text", text: errorMessage)],
                        tools: nil,
                        protocolVersion: nil,
                        capabilities: nil,
                        serverInfo: nil,
                        instructions: nil,
                        isError: true
                    ),
                    error: nil
                )
            }

        default:
            throw RemindersError("Unknown method: \(request.method)")
        }
    }

    private func getTools() -> [MCPResponse.Result.Tool] {
        return [
            // query_reminders
            MCPResponse.Result.Tool(
                name: "query_reminders",
                description: "Search and filter reminders. Returns incomplete reminders from the default list by default. Supports list selection, text search, date ranges, status filtering, and JMESPath queries. Use help(\"query_reminders\") for full parameter docs.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "list": .object([
                            "type": .string("object"),
                            "description": .string("Which list to search. Omit for default list."),
                            "properties": .object([
                                "name": .object(["type": .string("string"), "description": .string("List name (case-insensitive match)")]),
                                "id": .object(["type": .string("string"), "description": .string("Exact list ID")]),
                                "all": .object(["type": .string("boolean"), "description": .string("Set true to search all lists")])
                            ]),
                            "additionalProperties": .bool(false)
                        ]),
                        "status": .object([
                            "type": .string("string"),
                            "enum": .array([.string("incomplete"), .string("completed"), .string("all")]),
                            "default": .string("incomplete"),
                            "description": .string("Filter by completion status")
                        ]),
                        "searchText": .object([
                            "type": .string("string"),
                            "description": .string("Case-insensitive text search across reminder titles and notes")
                        ]),
                        "dateFrom": .object([
                            "type": .string("string"),
                            "description": .string("Start of date range (ISO 8601). Filters by dueDate for incomplete, completionDate for completed reminders.")
                        ]),
                        "dateTo": .object([
                            "type": .string("string"),
                            "description": .string("End of date range (ISO 8601). Filters by dueDate for incomplete, completionDate for completed reminders.")
                        ]),
                        "sortBy": .object([
                            "type": .string("string"),
                            "enum": .array([.string("newest"), .string("oldest"), .string("priority"), .string("dueDate")]),
                            "default": .string("newest"),
                            "description": .string("Sort order. Ignored if 'query' includes sorting.")
                        ]),
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("JMESPath expression for advanced filtering/projection. Applied after list, status, searchText, and date filters. When provided, outputDetail is ignored (always uses full fields as input).")
                        ]),
                        "outputDetail": .object([
                            "type": .string("string"),
                            "enum": .array([.string("minimal"), .string("compact"), .string("full")]),
                            "default": .string("compact"),
                            "description": .string("Controls which fields are returned. 'minimal': id, title. 'compact' (default): most useful fields, nulls omitted. 'full': all fields, nulls shown. Ignored when 'query' (JMESPath) is provided. listName and isCompleted are contextually omitted in minimal/compact when implied by query params.")
                        ]),
                        "perPage": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "maximum": .int(1000),
                            "description": .string("Results per page (1-1000). Omit to return all (auto-paginates at 200).")
                        ]),
                        "cursor": .object([
                            "type": .string("string"),
                            "description": .string("Opaque cursor from previous response's pageInfo.endCursor for next page.")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // get_lists
            MCPResponse.Result.Tool(
                name: "get_lists",
                description: "Get all available reminder lists with names, IDs, and default indicator. No parameters needed.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // create_list
            MCPResponse.Result.Tool(
                name: "create_list",
                description: "Create a new reminder list. Requires a name parameter.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("name")]),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Name for the new list")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // create_reminders
            MCPResponse.Result.Tool(
                name: "create_reminders",
                description: "Create one or more reminders with optional notes, due date, priority, alarms, recurrence, and URL. Supports batch creation. Use help(\"create_reminders\") for parameter details and examples.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("reminders")]),
                    "properties": .object([
                        "reminders": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("object"),
                                "required": .array([.string("title")]),
                                "properties": .object([
                                    "title": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder title")
                                    ]),
                                    "notes": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder notes/body text")
                                    ]),
                                    "list": .object([
                                        "type": .string("object"),
                                        "description": .string("Target list. Uses default list if omitted."),
                                        "properties": .object([
                                            "name": .object(["type": .string("string")]),
                                            "id": .object(["type": .string("string")])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ]),
                                    "dueDate": .object([
                                        "type": .string("string"),
                                        "description": .string("Due date in ISO 8601 format")
                                    ]),
                                    "dueDateIncludesTime": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Whether the due date includes a specific time. Set false for all-day reminders. Default: true.")
                                    ]),
                                    "priority": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("none"), .string("low"), .string("medium"), .string("high")]),
                                        "description": .string("Priority level")
                                    ]),
                                    "url": .object([
                                        "type": .string("string"),
                                        "description": .string("URL to associate with the reminder")
                                    ]),
                                    "alarms": .object([
                                        "type": .string("array"),
                                        "description": .string("Alarm notifications for the reminder"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "required": .array([.string("type")]),
                                            "properties": .object([
                                                "type": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([.string("relative"), .string("absolute")]),
                                                    "description": .string("Alarm type: 'relative' (offset from due date) or 'absolute' (specific date/time)")
                                                ]),
                                                "offset": .object([
                                                    "type": .string("integer"),
                                                    "description": .string("Seconds before due date (for relative alarms). E.g., 3600 = 1 hour before.")
                                                ]),
                                                "date": .object([
                                                    "type": .string("string"),
                                                    "description": .string("ISO 8601 date/time (for absolute alarms)")
                                                ])
                                            ]),
                                            "additionalProperties": .bool(false)
                                        ])
                                    ]),
                                    "recurrenceRule": .object([
                                        "type": .string("object"),
                                        "description": .string("Recurrence rule for repeating reminders"),
                                        "required": .array([.string("frequency")]),
                                        "properties": .object([
                                            "frequency": .object([
                                                "type": .string("string"),
                                                "enum": .array([.string("daily"), .string("weekly"), .string("monthly"), .string("yearly")]),
                                                "description": .string("How often the reminder repeats")
                                            ]),
                                            "interval": .object([
                                                "type": .string("integer"),
                                                "minimum": .int(1),
                                                "default": .int(1),
                                                "description": .string("Repeat every N periods (e.g., 2 = every other week)")
                                            ]),
                                            "daysOfWeek": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(7)]),
                                                "description": .string("Days of week (1=Sunday, 2=Monday, ..., 7=Saturday). For weekly/monthly frequency.")
                                            ]),
                                            "daysOfMonth": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(-31), "maximum": .int(31)]),
                                                "description": .string("Days of month (1-31, or negative for last N days: -1=last day, -2=second-to-last, etc.). For monthly frequency.")
                                            ]),
                                            "monthsOfYear": .object([
                                                "type": .string("array"),
                                                "items": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(12)]),
                                                "description": .string("Months of year (1-12). For yearly frequency.")
                                            ]),
                                            "weekPosition": .object([
                                                "type": .string("integer"),
                                                "description": .string("Week position within month: 1=first, 2=second, ..., -1=last. Used with daysOfWeek for 'first Monday' patterns.")
                                            ]),
                                            "endDate": .object([
                                                "type": .string("string"),
                                                "description": .string("ISO 8601 date when recurrence stops")
                                            ]),
                                            "endCount": .object([
                                                "type": .string("integer"),
                                                "minimum": .int(1),
                                                "description": .string("Number of occurrences before stopping")
                                            ])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // update_reminders
            MCPResponse.Result.Tool(
                name: "update_reminders",
                description: "Update one or more reminders. Only specified fields are changed; omitted fields are preserved. Supports marking complete/incomplete, moving between lists, and clearing fields with null. Use help(\"update_reminders\") for parameter details.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("reminders")]),
                    "properties": .object([
                        "reminders": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("object"),
                                "required": .array([.string("id")]),
                                "properties": .object([
                                    "id": .object([
                                        "type": .string("string"),
                                        "description": .string("Reminder ID to update (full or abbreviated prefix)")
                                    ]),
                                    "title": .object([
                                        "type": .string("string"),
                                        "description": .string("New title")
                                    ]),
                                    "notes": .object([
                                        "type": .string("string"),
                                        "description": .string("New notes. Set to null to clear.")
                                    ]),
                                    "list": .object([
                                        "type": .string("object"),
                                        "description": .string("Move to this list"),
                                        "properties": .object([
                                            "name": .object(["type": .string("string")]),
                                            "id": .object(["type": .string("string")])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ]),
                                    "dueDate": .object([
                                        "type": .string("string"),
                                        "description": .string("New due date in ISO 8601 format. Set to null to clear.")
                                    ]),
                                    "dueDateIncludesTime": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Whether the due date includes a specific time. Set false for all-day reminders.")
                                    ]),
                                    "priority": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("none"), .string("low"), .string("medium"), .string("high")]),
                                        "description": .string("New priority level")
                                    ]),
                                    "completed": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Set true to complete, false to uncomplete")
                                    ]),
                                    "completedDate": .object([
                                        "type": .string("string"),
                                        "description": .string("Completion date in ISO 8601 format. Set to null to uncomplete. Overrides 'completed' if both provided.")
                                    ]),
                                    "url": .object([
                                        "type": .string("string"),
                                        "description": .string("URL to associate with the reminder. Set to null to clear.")
                                    ]),
                                    "alarms": .object([
                                        "type": .string("array"),
                                        "description": .string("Alarm notifications. Set to null to clear all alarms."),
                                        "items": .object([
                                            "type": .string("object"),
                                            "required": .array([.string("type")]),
                                            "properties": .object([
                                                "type": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([.string("relative"), .string("absolute")]),
                                                    "description": .string("Alarm type")
                                                ]),
                                                "offset": .object([
                                                    "type": .string("integer"),
                                                    "description": .string("Seconds before due date (for relative alarms)")
                                                ]),
                                                "date": .object([
                                                    "type": .string("string"),
                                                    "description": .string("ISO 8601 date/time (for absolute alarms)")
                                                ])
                                            ]),
                                            "additionalProperties": .bool(false)
                                        ])
                                    ]),
                                    "recurrenceRule": .object([
                                        "type": .string("object"),
                                        "description": .string("Recurrence rule. Set to null to clear."),
                                        "required": .array([.string("frequency")]),
                                        "properties": .object([
                                            "frequency": .object([
                                                "type": .string("string"),
                                                "enum": .array([.string("daily"), .string("weekly"), .string("monthly"), .string("yearly")])
                                            ]),
                                            "interval": .object(["type": .string("integer"), "minimum": .int(1), "default": .int(1)]),
                                            "daysOfWeek": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "daysOfMonth": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "monthsOfYear": .object(["type": .string("array"), "items": .object(["type": .string("integer")])]),
                                            "weekPosition": .object(["type": .string("integer")]),
                                            "endDate": .object(["type": .string("string")]),
                                            "endCount": .object(["type": .string("integer"), "minimum": .int(1)])
                                        ]),
                                        "additionalProperties": .bool(false)
                                    ])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // delete_reminders
            MCPResponse.Result.Tool(
                name: "delete_reminders",
                description: "Delete one or more reminders permanently by ID. This action cannot be undone.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("ids")]),
                    "properties": .object([
                        "ids": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "items": .object([
                                "type": .string("string")
                            ]),
                            "description": .string("Array of reminder IDs to delete (full or abbreviated prefixes)")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // export_reminders
            MCPResponse.Result.Tool(
                name: "export_reminders",
                description: "Export reminders to a JSON file for backup. Writes data to a file instead of returning it in context. Optional path, list filter, and includeCompleted parameters.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Custom file path. Supports ~ for home directory. Default: temp directory with timestamp.")
                        ]),
                        "lists": .object([
                            "type": .string("array"),
                            "description": .string("Lists to export. Default: all lists."),
                            "items": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "name": .object(["type": .string("string"), "description": .string("List name")]),
                                    "id": .object(["type": .string("string"), "description": .string("List ID")])
                                ]),
                                "additionalProperties": .bool(false)
                            ])
                        ]),
                        "includeCompleted": .object([
                            "type": .string("boolean"),
                            "default": .bool(true),
                            "description": .string("Include completed reminders in export")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // Meta-tools for progressive disclosure

            // help
            MCPResponse.Result.Tool(
                name: "help",
                description: "Get documentation for any tool. Returns concise help by default, or comprehensive docs with verbose=true.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("tool_name")]),
                    "properties": .object([
                        "tool_name": .object([
                            "type": .string("string"),
                            "description": .string("Name of the tool to get help for (e.g., \"query_reminders\")")
                        ]),
                        "verbose": .object([
                            "type": .string("boolean"),
                            "default": .bool(false),
                            "description": .string("Set true for comprehensive docs with examples")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // schema
            MCPResponse.Result.Tool(
                name: "schema",
                description: "Get the full JSON input schema for any tool. Use when you need to construct complex payloads.",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("tool_name")]),
                    "properties": .object([
                        "tool_name": .object([
                            "type": .string("string"),
                            "description": .string("Name of the tool to get schema for")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // guidance
            MCPResponse.Result.Tool(
                name: "guidance",
                description: "Get strategic guidance and best practices for using Apple Reminders tools effectively. Optional topic to scope the guidance.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "topic": .object([
                            "type": .string("string"),
                            "description": .string("Optional topic: a tool name or general area (e.g., \"query_reminders\", \"mutations\", \"querying\")")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),
        ]
    }

    private func callTool(_ name: String, arguments: [String: AnyCodable]) async throws -> String {
        switch name {
        case "get_lists":
            let lists = remindersManager.getAllLists()
            return try toJSON(lists)

        case "create_list":
            guard let listName = arguments["name"]?.value as? String else {
                throw RemindersError("Missing required field: 'name'")
            }
            let createdList = try remindersManager.createList(name: listName)
            await autoSnapshot(reason: "create_list")
            return try toJSON(createdList)

        case "query_reminders":
            let listDict = arguments["list"]?.value as? [String: Any]
            let listSelector = ListSelector(from: listDict)
            let status = arguments["status"]?.value as? String
            let sortBy = arguments["sortBy"]?.value as? String
            let query = arguments["query"]?.value as? String
            let perPage = arguments["perPage"]?.value as? Int
            let cursor = arguments["cursor"]?.value as? String
            let searchText = arguments["searchText"]?.value as? String
            let dateFrom = arguments["dateFrom"]?.value as? String
            let dateTo = arguments["dateTo"]?.value as? String
            let outputDetail = arguments["outputDetail"]?.value as? String

            let result = try await remindersManager.queryReminders(
                list: listDict == nil ? nil : listSelector,
                status: status,
                sortBy: sortBy,
                query: query,
                perPage: perPage,
                cursor: cursor,
                searchText: searchText,
                dateFrom: dateFrom,
                dateTo: dateTo,
                outputDetail: outputDetail
            )

            return try toJSON(result)

        case "create_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw RemindersError("Missing required field: 'reminders'")
            }

            var inputs: [CreateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let title = dict["title"] as? String else {
                    throw RemindersError("Missing required field 'title' in reminder at index \(index)")
                }
                // Parse alarm inputs
                var alarmInputs: [AlarmInput]? = nil
                if let alarmsArray = dict["alarms"] as? [[String: Any]] {
                    alarmInputs = alarmsArray.map { alarmDict in
                        AlarmInput(
                            type: alarmDict["type"] as? String ?? "relative",
                            date: alarmDict["date"] as? String,
                            offset: alarmDict["offset"] as? Int
                        )
                    }
                }

                // Parse recurrence rule input
                var recurrenceInput: RecurrenceRuleInput? = nil
                if let ruleDict = dict["recurrenceRule"] as? [String: Any] {
                    recurrenceInput = RecurrenceRuleInput(
                        frequency: ruleDict["frequency"] as? String ?? "daily",
                        interval: ruleDict["interval"] as? Int,
                        daysOfWeek: ruleDict["daysOfWeek"] as? [Int],
                        daysOfMonth: ruleDict["daysOfMonth"] as? [Int],
                        monthsOfYear: ruleDict["monthsOfYear"] as? [Int],
                        weekPosition: ruleDict["weekPosition"] as? Int,
                        endDate: ruleDict["endDate"] as? String,
                        endCount: ruleDict["endCount"] as? Int
                    )
                }

                inputs.append(CreateReminderInput(
                    title: title,
                    notes: dict["notes"] as? String,
                    list: ListSelector(from: dict["list"] as? [String: Any]),
                    dueDate: dict["dueDate"] as? String,
                    priority: dict["priority"] as? String,
                    url: dict["url"] as? String,
                    dueDateIncludesTime: dict["dueDateIncludesTime"] as? Bool,
                    alarms: alarmInputs,
                    recurrenceRule: recurrenceInput
                ))
            }

            let (created, failed) = remindersManager.createReminders(inputs: inputs)

            if !created.isEmpty {
                await autoSnapshot(reason: "create_reminders")
            }

            if failed.isEmpty {
                return try toJSON(created)
            } else {
                let failedOutput = failed.map { ["index": $0.index, "error": $0.error] }
                let response: [String: Any] = ["created": encodableArray(created), "failed": failedOutput]
                return try toJSON(response)
            }

        case "update_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw RemindersError("Missing required field: 'reminders'")
            }

            var inputs: [UpdateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let id = dict["id"] as? String else {
                    throw RemindersError("Missing required field 'id' in reminder at index \(index)")
                }
                // Parse alarm inputs if present
                var alarmsClearable: Clearable<[AlarmInput]>? = nil
                if let alarmsRaw = dict["alarms"] {
                    if alarmsRaw is NSNull {
                        alarmsClearable = .clear
                    } else if let alarmsArray = alarmsRaw as? [[String: Any]] {
                        alarmsClearable = .value(alarmsArray.map { alarmDict in
                            AlarmInput(
                                type: alarmDict["type"] as? String ?? "relative",
                                date: alarmDict["date"] as? String,
                                offset: alarmDict["offset"] as? Int
                            )
                        })
                    }
                }

                // Parse recurrence rule if present
                var recurrenceClearable: Clearable<RecurrenceRuleInput>? = nil
                if let ruleRaw = dict["recurrenceRule"] {
                    if ruleRaw is NSNull {
                        recurrenceClearable = .clear
                    } else if let ruleDict = ruleRaw as? [String: Any] {
                        recurrenceClearable = .value(RecurrenceRuleInput(
                            frequency: ruleDict["frequency"] as? String ?? "daily",
                            interval: ruleDict["interval"] as? Int,
                            daysOfWeek: ruleDict["daysOfWeek"] as? [Int],
                            daysOfMonth: ruleDict["daysOfMonth"] as? [Int],
                            monthsOfYear: ruleDict["monthsOfYear"] as? [Int],
                            weekPosition: ruleDict["weekPosition"] as? Int,
                            endDate: ruleDict["endDate"] as? String,
                            endCount: ruleDict["endCount"] as? Int
                        ))
                    }
                }

                inputs.append(UpdateReminderInput(
                    id: id,
                    title: dict["title"] as? String,
                    notes: parseClearable(dict["notes"]),
                    list: ListSelector(from: dict["list"] as? [String: Any]),
                    dueDate: parseClearable(dict["dueDate"]),
                    priority: dict["priority"] as? String,
                    completed: dict["completed"] as? Bool,
                    completedDate: parseClearable(dict["completedDate"]),
                    url: parseClearable(dict["url"]),
                    dueDateIncludesTime: dict["dueDateIncludesTime"] as? Bool,
                    alarms: alarmsClearable,
                    recurrenceRule: recurrenceClearable
                ))
            }

            let (updated, failed) = await remindersManager.updateReminders(inputs: inputs)

            if !updated.isEmpty {
                await autoSnapshot(reason: "update_reminders")
            }

            if failed.isEmpty {
                return try toJSON(updated)
            } else {
                let failedOutput = failed.map { ["id": $0.id, "error": $0.error] }
                let response: [String: Any] = ["updated": encodableArray(updated), "failed": failedOutput]
                return try toJSON(response)
            }

        case "delete_reminders":
            guard let ids = arguments["ids"]?.value as? [String] else {
                throw RemindersError("Missing required field: 'ids'")
            }

            let (deleted, failed) = await remindersManager.deleteReminders(ids: ids)

            if !deleted.isEmpty {
                await autoSnapshot(reason: "delete_reminders")
            }

            let failedOutput = failed.map { ["id": $0.id, "error": $0.error] }
            let response: [String: Any] = ["deleted": deleted, "failed": failedOutput]
            return try toJSON(response)

        case "export_reminders":
            let path = arguments["path"]?.value as? String
            let includeCompleted = arguments["includeCompleted"]?.value as? Bool ?? true

            // Parse lists array if provided
            var listSelectors: [ListSelector]? = nil
            if let listsArray = arguments["lists"]?.value as? [[String: Any]] {
                listSelectors = listsArray.map { ListSelector(from: $0) }
            }

            let result = try await remindersManager.exportReminders(
                path: path,
                lists: listSelectors,
                includeCompleted: includeCompleted
            )

            return try toJSON(result)

        // Meta-tools for progressive disclosure

        case "help":
            guard let toolName = arguments["tool_name"]?.value as? String else {
                throw RemindersError("Missing required field: 'tool_name'")
            }
            let verbose = arguments["verbose"]?.value as? Bool ?? false
            return getToolHelp(toolName: toolName, verbose: verbose)

        case "schema":
            guard let toolName = arguments["tool_name"]?.value as? String else {
                throw RemindersError("Missing required field: 'tool_name'")
            }
            return try getToolSchema(toolName: toolName)

        case "guidance":
            let topic = arguments["topic"]?.value as? String
            return getGuidance(topic: topic)

        default:
            throw RemindersError("Unknown tool: \(name)")
        }
    }

    // MARK: - Meta-tool Implementations

    /// Map MCP tool names to CLI command names for help lookup.
    private static let toolToCommandMap: [String: String] = [
        "query_reminders": "query",
        "get_lists": "lists",
        "create_list": "create-list",
        "create_reminders": "create",
        "update_reminders": "update",
        "delete_reminders": "delete",
        "export_reminders": "export",
    ]

    private func getToolHelp(toolName: String, verbose: Bool) -> String {
        // Map MCP tool name to CLI command name
        let commandName = Self.toolToCommandMap[toolName] ?? toolName

        if verbose {
            if let content = HelpContent.verbose(for: commandName) {
                return content
            }
        } else {
            if let content = HelpContent.concise(for: commandName) {
                return content
            }
        }

        let validTools = Self.toolToCommandMap.keys.sorted().joined(separator: ", ")
        return "No help available for '\(toolName)'. Valid tools: \(validTools)"
    }

    private func getToolSchema(toolName: String) throws -> String {
        let tools = getTools()
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            let validTools = tools.map { $0.name }.filter { $0 != "help" && $0 != "schema" && $0 != "guidance" }.sorted().joined(separator: ", ")
            throw RemindersError("Unknown tool: '\(toolName)'. Valid tools: \(validTools)")
        }

        // Serialize the inputSchema to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tool.inputSchema)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func getGuidance(topic: String?) -> String {
        // If a specific tool is requested, return its skill guidance
        if let topic = topic {
            let commandName = Self.toolToCommandMap[topic] ?? topic
            if let content = HelpContent.skill(for: commandName) {
                return content
            }
        }

        // Return top-level skill guidance
        return HelpContent.skill(for: nil) ?? "No guidance available."
    }

    /// Parses a JSON value into a Clearable: NSNull → .clear, castable T → .value(T), absent key → nil
    private func parseClearable<T>(_ raw: Any?) -> Clearable<T>? {
        guard let raw = raw else { return nil }
        if raw is NSNull { return .clear }
        if let value = raw as? T { return .value(value) }
        return nil
    }

    private func encodableArray(_ reminders: [ReminderOutput]) -> [[String: Any]] {
        return reminders.map { reminder in
            var dict: [String: Any] = [
                "id": reminder.id,
                "title": reminder.title,
                "listId": reminder.listId,
                "listName": reminder.listName,
                "isCompleted": reminder.isCompleted,
                "priority": reminder.priority,
                "createdDate": reminder.createdDate,
                "lastModifiedDate": reminder.lastModifiedDate
            ]
            if let notes = reminder.notes {
                dict["notes"] = notes
            }
            if let dueDate = reminder.dueDate {
                dict["dueDate"] = dueDate
            }
            if let dueDateIncludesTime = reminder.dueDateIncludesTime {
                dict["dueDateIncludesTime"] = dueDateIncludesTime
            }
            if let completionDate = reminder.completionDate {
                dict["completionDate"] = completionDate
            }
            if let url = reminder.url {
                dict["url"] = url
            }
            if let alarms = reminder.alarms {
                dict["alarms"] = alarms.map { $0.toDict() }
            }
            if let rules = reminder.recurrenceRules {
                dict["recurrenceRules"] = rules.map { $0.toDict() }
            }
            return dict
        }
    }

    private func sendResponse(_ response: MCPResponse) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(response)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
        } catch {
            logError("Error encoding response: \(error)")
        }
    }

    private func toJSON(_ object: Any) throws -> String {
        if let encodable = object as? Encodable {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(AnyEncodable(encodable))
            guard let string = String(data: data, encoding: .utf8) else {
                throw RemindersError("Failed to convert to JSON string")
            }
            return string
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RemindersError("Failed to convert to JSON string")
        }
        return string
    }
}
