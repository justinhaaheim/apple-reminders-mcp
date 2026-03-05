import ArgumentParser
import AppleRemindersCore
import Foundation

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new reminder"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Reminder title")
    var title: String

    @Option(name: .long, help: "List name to create reminder in")
    var list: String?

    @Option(name: .long, help: "List ID to create reminder in")
    var listId: String?

    @Option(name: .long, help: "Notes for the reminder")
    var notes: String?

    @Option(name: .long, help: "Due date (ISO 8601)")
    var due: String?

    @Option(name: .long, help: "Priority: none, low, medium, high")
    var priority: String?

    @Option(name: .long, help: "URL to attach")
    var url: String?

    @Option(name: .long, help: "Relative alarm offset in seconds before due date")
    var alarmRelative: Int?

    @Option(name: .long, help: "Absolute alarm date (ISO 8601)")
    var alarmDate: String?

    @Option(name: .long, help: "Recurrence frequency: daily, weekly, monthly, yearly")
    var recurrence: String?

    @Option(name: .long, help: "Recurrence interval (default: 1)")
    var recurrenceInterval: Int?

    func run() async throws {
        let manager = try await createManager(options: globals)

        let listSelector: ListSelector?
        if let listId = listId {
            listSelector = ListSelector(id: listId)
        } else if let list = list {
            listSelector = ListSelector(name: list)
        } else {
            listSelector = nil
        }

        var alarms: [AlarmInput]?
        if let offset = alarmRelative {
            alarms = [AlarmInput(type: "relative", date: nil, offset: offset)]
        } else if let date = alarmDate {
            alarms = [AlarmInput(type: "absolute", date: date, offset: nil)]
        }

        var recurrenceRule: RecurrenceRuleInput?
        if let freq = recurrence {
            recurrenceRule = RecurrenceRuleInput(
                frequency: freq,
                interval: recurrenceInterval
            )
        }

        let input = CreateReminderInput(
            title: title,
            notes: notes,
            list: listSelector,
            dueDate: due,
            priority: priority,
            url: url,
            alarms: alarms,
            recurrenceRule: recurrenceRule
        )

        let result = manager.createReminders(inputs: [input])

        if !result.failed.isEmpty {
            for failure in result.failed {
                fputs("Error: \(failure.error)\n", stderr)
            }
            throw ExitCode.failure
        }

        if let created = result.created.first {
            try outputJSON(created, pretty: globals.pretty)
        }
    }
}
