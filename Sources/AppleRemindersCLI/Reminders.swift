import ArgumentParser
import AppleRemindersCore
import Foundation

@main
struct Reminders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Apple Reminders CLI — query, create, update, and manage reminders",
        version: "0.1.0",
        subcommands: [
            QueryCommand.self,
            ListsCommand.self,
            CreateCommand.self,
            CreateListCommand.self,
            UpdateCommand.self,
            DeleteCommand.self,
            ExportCommand.self,
            MCPCommand.self,
        ],
        defaultSubcommand: QueryCommand.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Flag(name: .long, help: "Use mock store (for testing)")
    var mock: Bool = false

    @Flag(name: .long, help: "Enable test mode restrictions")
    var testMode: Bool = false

    @Flag(name: .long, help: "Show debug logging on stderr")
    var verbose: Bool = false
}

// MARK: - Store Factory

func createStore(mock: Bool) -> ReminderStore {
    if mock || MockModeConfig.isEnabled {
        return MockReminderStore()
    }
    #if canImport(EventKit)
    return EKReminderStore()
    #else
    return MockReminderStore()
    #endif
}

func createManager(options: GlobalOptions) async throws -> RemindersManager {
    if options.testMode {
        setenv(TestModeConfig.envVar, "1", 1)
    }
    let store = createStore(mock: options.mock)
    let manager = RemindersManager(store: store)
    try await manager.requestAccess()
    return manager
}

// MARK: - JSON Output

func outputJSON(_ value: Any, pretty: Bool) throws {
    let data: Data
    if let encodable = value as? Encodable {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        data = try encoder.encode(AnyEncodable(encodable))
    } else {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            : [.sortedKeys, .fragmentsAllowed]
        data = try JSONSerialization.data(withJSONObject: value, options: options)
    }

    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

// MARK: - AnyEncodable wrapper for CLI

private struct AnyEncodable: Encodable {
    private let encodable: Encodable

    init(_ encodable: Encodable) {
        self.encodable = encodable
    }

    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}
