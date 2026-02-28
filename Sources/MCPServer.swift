import Foundation

// MARK: - MCP Server

class MCPServer {
    private let remindersManager: RemindersManager

    init() {
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
    }

    func start() async {
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

        log("Apple Reminders MCP Server running on stdio")

        while let line = readLine() {
            await handleRequest(line)
        }
    }

    private func handleRequest(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        var requestId: MCPRequest.RequestID?
        if let partialRequest = try? JSONDecoder().decode(MCPRequest.self, from: data) {
            requestId = partialRequest.id
        }

        do {
            let request = try JSONDecoder().decode(MCPRequest.self, from: data)
            let response = try await processRequest(request)
            sendResponse(response)
        } catch {
            logError("Error processing request: \(error)")
            sendErrorResponse(id: requestId ?? .int(-1), code: -32603, message: error.localizedDescription)
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
            Apple Reminders MCP Server - Access Apple Reminders with 7 powerful tools.

            TOOLS:
            • query_reminders - Search and filter reminders (text search, date range, JMESPath)
            • get_lists - Get all reminder lists
            • create_list - Create a new list
            • create_reminders - Create reminders with alarms, recurrence, URLs
            • update_reminders - Update reminders (including mark complete/incomplete)
            • delete_reminders - Delete reminders
            • export_reminders - Export reminders to JSON file (for backup)

            QUICK START:
            1. Call query_reminders with {} to see incomplete reminders from default list
            2. Use get_lists to see all available lists
            3. Specify list by name: {"list": {"name": "Work"}}
            4. Specify list by ID: {"list": {"id": "x-apple-..."}}
            5. Search by text: {"searchText": "meeting"}
            6. Search all lists: {"list": {"all": true}}

            PRIORITY: Use "none", "low", "medium", or "high" (not numbers)
            DATES: ISO 8601 with timezone, e.g., "2024-01-15T10:00:00-05:00"
            ALARMS: [{"type": "relative", "offset": 3600}] (1 hour before)
            RECURRENCE: {"frequency": "weekly", "interval": 1}
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
                        version: "2.0.0"
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
                throw MCPToolError("Missing tool name")
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
            throw MCPToolError("Unknown method: \(request.method)")
        }
    }

    private func getTools() -> [MCPResponse.Result.Tool] {
        return [
            // query_reminders
            MCPResponse.Result.Tool(
                name: "query_reminders",
                description: """
                Query reminders from Apple Reminders.

                **Default behavior (no parameters needed):**
                - Searches DEFAULT LIST only
                - Returns INCOMPLETE reminders only
                - Sorted by NEWEST CREATED first
                - Limited to 50 results
                - Uses "compact" output (most useful fields, nulls omitted)

                **Parameters (all optional):**

                list — Which list to search. Omit for default list.
                  • {"name": "Work"} → by exact name (case-insensitive)
                  • {"id": "x-apple-..."} → by exact ID
                  • {"all": true} → all lists

                status — "incomplete" (default), "completed", or "all"

                searchText — Case-insensitive text search across title and notes

                dateFrom / dateTo — Date range filter (ISO 8601). For incomplete reminders filters by dueDate, for completed by completionDate.

                sortBy — "newest" (default), "oldest", "priority", "dueDate"

                query — JMESPath expression for advanced filtering (overrides sortBy and outputDetail — always uses full fields as input)

                outputDetail — Controls which fields are returned:
                  • "minimal" — id, title only (plus listName if searching all lists, isCompleted if status is "all")
                  • "compact" (default) — id, title, notes, dueDate, priority, createdDate, lastModifiedDate (plus listName/isCompleted when contextually useful). Null fields omitted.
                  • "full" — All fields always included, null values shown explicitly

                limit — Max results (default 50, max 200)

                **Examples:**

                Recent incomplete from default list:
                  {}

                From specific list:
                  {"list": {"name": "Work"}}

                All lists, completed:
                  {"list": {"all": true}, "status": "completed"}

                Search by text:
                  {"searchText": "meeting"}

                Due this week:
                  {"dateFrom": "2024-01-15T00:00:00-05:00", "dateTo": "2024-01-21T23:59:59-05:00"}

                Full detail for debugging:
                  {"outputDetail": "full"}

                Minimal for quick overview:
                  {"outputDetail": "minimal"}

                High priority only:
                  {"query": "[?priority == 'high']"}

                Created today or later (via JMESPath):
                  {"query": "[?createdDate >= '2024-01-15']"}

                Modified in the last week (via JMESPath):
                  {"query": "[?lastModifiedDate >= '2024-01-08']"}

                **Reminder fields available in JMESPath (always full):**
                - id, title, notes, listId, listName, isCompleted
                - priority (string: "none", "low", "medium", "high")
                - dueDate, dueDateIncludesTime, completionDate, createdDate, lastModifiedDate
                - url, alarms, recurrenceRules
                """,
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
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "maximum": .int(200),
                            "default": .int(50),
                            "description": .string("Maximum results to return")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // get_lists
            MCPResponse.Result.Tool(
                name: "get_lists",
                description: """
                Get all available reminder lists.

                Returns list names, IDs, and which one is the default. Call this if you need to know what lists exist before querying reminders.

                **Parameters:** None

                **Example:**
                  {}
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // create_list
            MCPResponse.Result.Tool(
                name: "create_list",
                description: """
                Create a new reminder list.

                **Parameters:**

                name (required) — Name for the new list

                **Example:**

                Create a "Groceries" list:
                  {"name": "Groceries"}
                """,
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
                description: """
                Create one or more reminders.

                **Parameters:**

                reminders — Array of reminder objects to create. Each object:
                  • title (required) — Reminder title
                  • notes — Body text
                  • list — Target list as {"name": "..."} or {"id": "..."}. Default list if omitted.
                  • dueDate — ISO 8601 datetime (e.g., "2024-01-15T10:00:00-05:00")
                  • dueDateIncludesTime — Whether the due date has a specific time (default true). Set false for all-day reminders.
                  • priority — "none", "low", "medium", or "high"
                  • url — URL to associate with the reminder
                  • alarms — Array of alarm objects: {"type": "relative", "offset": 3600} or {"type": "absolute", "date": "..."}
                  • recurrenceRule — Recurrence rule: {"frequency": "daily|weekly|monthly|yearly", "interval": 1, ...}

                **Examples:**

                Single reminder:
                  {"reminders": [{"title": "Buy milk"}]}

                With details:
                  {"reminders": [{"title": "Call dentist", "list": {"name": "Personal"}, "dueDate": "2024-01-20T09:00:00-05:00", "priority": "high"}]}

                With alarm (1 hour before):
                  {"reminders": [{"title": "Meeting", "dueDate": "2024-01-20T14:00:00-05:00", "alarms": [{"type": "relative", "offset": 3600}]}]}

                Weekly recurrence:
                  {"reminders": [{"title": "Team standup", "dueDate": "2024-01-20T09:00:00-05:00", "recurrenceRule": {"frequency": "weekly", "interval": 1, "daysOfWeek": [2, 3, 4, 5, 6]}}]}

                Batch create:
                  {"reminders": [
                    {"title": "Buy milk"},
                    {"title": "Buy eggs"},
                    {"title": "Buy bread", "priority": "low"}
                  ]}
                """,
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
                description: """
                Update one or more reminders. Only specified fields are changed.

                **Parameters:**

                reminders — Array of update objects. Each object:
                  • id (required) — Reminder ID to update
                  • title — New title
                  • notes — New notes (null to clear)
                  • list — Move to list as {"name": "..."} or {"id": "..."}
                  • dueDate — New due date as ISO 8601 (null to clear)
                  • dueDateIncludesTime — Whether due date has specific time (false = all-day)
                  • priority — "none", "low", "medium", or "high"
                  • completed — true to complete, false to uncomplete
                  • completedDate — ISO 8601 completion date (null to uncomplete)
                  • url — URL to associate (null to clear)
                  • alarms — Array of alarm objects (null to clear all alarms)
                  • recurrenceRule — Recurrence rule object (null to clear)

                **Examples:**

                Update title:
                  {"reminders": [{"id": "...", "title": "Buy oat milk"}]}

                Move to different list:
                  {"reminders": [{"id": "...", "list": {"name": "Groceries"}}]}

                Complete a reminder:
                  {"reminders": [{"id": "...", "completed": true}]}

                Uncomplete a reminder:
                  {"reminders": [{"id": "...", "completed": false}]}

                Complete with specific date:
                  {"reminders": [{"id": "...", "completedDate": "2024-01-15T10:00:00-05:00"}]}

                Clear due date:
                  {"reminders": [{"id": "...", "dueDate": null}]}

                Add alarm:
                  {"reminders": [{"id": "...", "alarms": [{"type": "relative", "offset": 1800}]}]}

                Set weekly recurrence:
                  {"reminders": [{"id": "...", "recurrenceRule": {"frequency": "weekly"}}]}

                Clear recurrence:
                  {"reminders": [{"id": "...", "recurrenceRule": null}]}

                Batch update (complete multiple):
                  {"reminders": [
                    {"id": "abc", "completed": true},
                    {"id": "def", "completed": true},
                    {"id": "ghi", "completed": true}
                  ]}
                """,
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
                                        "description": .string("Reminder ID to update")
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
                description: """
                Delete one or more reminders permanently.

                **Parameters:**

                ids — Array of reminder IDs to delete

                **Examples:**

                Single delete:
                  {"ids": ["abc123"]}

                Batch delete:
                  {"ids": ["abc123", "def456", "ghi789"]}
                """,
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
                            "description": .string("Array of reminder IDs to delete")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),

            // export_reminders
            MCPResponse.Result.Tool(
                name: "export_reminders",
                description: """
                Export reminders to a JSON file for backup or data portability.

                Writes all reminder data to a file without consuming LLM context tokens.
                Default location is system temp directory; move the file to keep it permanently.

                **Parameters (all optional):**

                path — Custom file path (default: temp directory with timestamp)
                  • Supports ~ for home directory
                  • Example: "~/Desktop/my-backup.json"

                lists — Array of lists to export (default: all lists)
                  • Each item: {"name": "..."} or {"id": "..."}
                  • Example: [{"name": "Work"}, {"name": "Personal"}]

                includeCompleted — Include completed reminders (default: true)

                **Examples:**

                Export everything to temp:
                  {}

                Export to Desktop:
                  {"path": "~/Desktop/reminders-backup.json"}

                Export only incomplete reminders:
                  {"includeCompleted": false}

                Export specific lists:
                  {"lists": [{"name": "Work"}, {"name": "Shopping"}]}

                **File format:**
                JSON with exportVersion, exportDate, stats, lists[], and reminders[].
                """,
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
            )
        ]
    }

    private func callTool(_ name: String, arguments: [String: AnyCodable]) async throws -> String {
        switch name {
        case "get_lists":
            let lists = remindersManager.getAllLists()
            return try toJSON(lists)

        case "create_list":
            guard let listName = arguments["name"]?.value as? String else {
                throw MCPToolError("Missing required field: 'name'")
            }
            let createdList = try remindersManager.createList(name: listName)
            return try toJSON(createdList)

        case "query_reminders":
            let listDict = arguments["list"]?.value as? [String: Any]
            let listSelector = ListSelector(from: listDict)
            let status = arguments["status"]?.value as? String
            let sortBy = arguments["sortBy"]?.value as? String
            let query = arguments["query"]?.value as? String
            let limit = arguments["limit"]?.value as? Int
            let searchText = arguments["searchText"]?.value as? String
            let dateFrom = arguments["dateFrom"]?.value as? String
            let dateTo = arguments["dateTo"]?.value as? String
            let outputDetail = arguments["outputDetail"]?.value as? String

            let result = try await remindersManager.queryReminders(
                list: listDict == nil ? nil : listSelector,
                status: status,
                sortBy: sortBy,
                query: query,
                limit: limit,
                searchText: searchText,
                dateFrom: dateFrom,
                dateTo: dateTo,
                outputDetail: outputDetail
            )

            return try toJSON(result)

        case "create_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw MCPToolError("Missing required field: 'reminders'")
            }

            var inputs: [CreateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let title = dict["title"] as? String else {
                    throw MCPToolError("Missing required field 'title' in reminder at index \(index)")
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

            if failed.isEmpty {
                return try toJSON(created)
            } else {
                let failedOutput = failed.map { ["index": $0.index, "error": $0.error] }
                let response: [String: Any] = ["created": encodableArray(created), "failed": failedOutput]
                return try toJSON(response)
            }

        case "update_reminders":
            guard let remindersArray = arguments["reminders"]?.value as? [[String: Any]] else {
                throw MCPToolError("Missing required field: 'reminders'")
            }

            var inputs: [UpdateReminderInput] = []
            for (index, dict) in remindersArray.enumerated() {
                guard let id = dict["id"] as? String else {
                    throw MCPToolError("Missing required field 'id' in reminder at index \(index)")
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

            let (updated, failed) = remindersManager.updateReminders(inputs: inputs)

            if failed.isEmpty {
                return try toJSON(updated)
            } else {
                let failedOutput = failed.map { ["id": $0.id, "error": $0.error] }
                let response: [String: Any] = ["updated": encodableArray(updated), "failed": failedOutput]
                return try toJSON(response)
            }

        case "delete_reminders":
            guard let ids = arguments["ids"]?.value as? [String] else {
                throw MCPToolError("Missing required field: 'ids'")
            }

            let (deleted, failed) = remindersManager.deleteReminders(ids: ids)
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

        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
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
                throw MCPToolError("Failed to convert to JSON string")
            }
            return string
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPToolError("Failed to convert to JSON string")
        }
        return string
    }
}
