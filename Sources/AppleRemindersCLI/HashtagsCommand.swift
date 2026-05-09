import ArgumentParser
import AppleRemindersCore
import Foundation

struct HashtagsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hashtags",
        abstract: "List the master hashtag inventory with usage counts"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Include hashtags with zero current applications (default: only used)")
    var all: Bool = false

    func run() async throws {
        let manager = try await createManager(options: globals)

        if !manager.hasDBEnrichment {
            // Match the convention used elsewhere: when DB enrichment is
            // unavailable we degrade to an empty result with a stderr
            // warning rather than erroring out.
            ReminderDBReader.warnOnce(
                "hashtags-no-enrichment",
                "Hashtag inventory unavailable: SQLite enrichment is disabled. Grant Full Disk Access to the calling terminal."
            )
        }

        let entries = manager.listHashtags(includeUnused: all)
        try outputJSON(entries, pretty: globals.pretty)
    }
}
