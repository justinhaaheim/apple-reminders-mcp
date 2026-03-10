import ArgumentParser
import AppleRemindersCore
import Foundation

struct AuditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "View audit log of mutation operations"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Number of days to show (default: 7)")
    var days: Int?

    @Flag(name: .long, help: "Show log file paths and sizes")
    var files: Bool = false

    func run() async throws {
        let logger = AuditLogger.shared

        if files {
            let logFiles = logger.getLogFiles()
            if logFiles.isEmpty {
                let output: [String: Any] = [
                    "files": [] as [Any],
                    "message": "No audit log files found",
                ]
                try outputJSON(output, pretty: globals.pretty)
            } else {
                let filesOutput = logFiles.map { file -> [String: Any] in
                    [
                        "date": file.date,
                        "path": file.path,
                        "sizeBytes": file.sizeBytes,
                    ]
                }
                try outputJSON(filesOutput, pretty: globals.pretty)
            }
            return
        }

        let lookbackDays = days ?? 7
        let entries = logger.getRecentEntries(days: lookbackDays)

        if entries.isEmpty {
            let output: [String: Any] = [
                "entries": [] as [Any],
                "message": "No audit entries found in the last \(lookbackDays) day(s)",
            ]
            try outputJSON(output, pretty: globals.pretty)
            return
        }

        // Parse and re-output as a JSON array
        var parsedEntries: [Any] = []
        for line in entries {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data)
            {
                parsedEntries.append(obj)
            }
        }

        try outputJSON(parsedEntries, pretty: globals.pretty)
    }
}
