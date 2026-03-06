import ArgumentParser
import AppleRemindersCore
import Foundation

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing reminder"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Reminder ID to update")
    var id: String

    @Option(name: .long, help: "New title")
    var title: String?

    @Option(name: .long, help: "New notes (use --clear-notes to remove)")
    var notes: String?

    @Flag(name: .long, help: "Clear notes")
    var clearNotes: Bool = false

    @Option(name: .long, help: "Move to list by name")
    var list: String?

    @Option(name: .long, help: "Move to list by ID")
    var listId: String?

    @Option(name: .long, help: "New due date (ISO 8601, use --clear-due-date to remove)")
    var due: String?

    @Flag(name: .long, help: "Clear due date")
    var clearDueDate: Bool = false

    @Option(name: .long, help: "New priority: none, low, medium, high")
    var priority: String?

    @Flag(name: .long, help: "Mark as complete")
    var complete: Bool = false

    @Flag(name: .long, help: "Mark as incomplete")
    var incomplete: Bool = false

    @Option(name: .long, help: "New URL (use --clear-url to remove)")
    var url: String?

    @Flag(name: .long, help: "Clear URL")
    var clearUrl: Bool = false

    func run() async throws {
        let manager = try await createManager(options: globals)

        let notesValue: Clearable<String>?
        if clearNotes {
            notesValue = .clear
        } else if let notes = notes {
            notesValue = .value(notes)
        } else {
            notesValue = nil
        }

        let dueDateValue: Clearable<String>?
        if clearDueDate {
            dueDateValue = .clear
        } else if let due = due {
            dueDateValue = .value(due)
        } else {
            dueDateValue = nil
        }

        let urlValue: Clearable<String>?
        if clearUrl {
            urlValue = .clear
        } else if let url = url {
            urlValue = .value(url)
        } else {
            urlValue = nil
        }

        let listSelector: ListSelector?
        if let listId = listId {
            listSelector = ListSelector(id: listId)
        } else if let list = list {
            listSelector = ListSelector(name: list)
        } else {
            listSelector = nil
        }

        let completed: Bool?
        if complete {
            completed = true
        } else if incomplete {
            completed = false
        } else {
            completed = nil
        }

        let input = UpdateReminderInput(
            id: id,
            title: title,
            notes: notesValue,
            list: listSelector,
            dueDate: dueDateValue,
            priority: priority,
            completed: completed,
            url: urlValue
        )

        let result = manager.updateReminders(inputs: [input])

        if !result.failed.isEmpty {
            for failure in result.failed {
                fputs("Error updating \(failure.id): \(failure.error)\n", stderr)
            }
            throw ExitCode.failure
        }

        if let updated = result.updated.first {
            try outputJSON(updated, pretty: globals.pretty)
        }
    }
}
