import Foundation

// MARK: - Help System Pre-Parser

/// Pre-parses ProcessInfo.arguments to intercept help flags before ArgumentParser runs.
/// Supports three help modes:
///   --help              Concise help (replaces ArgumentParser's default)
///   --help --verbose    Comprehensive help (cumulative, includes concise content)
///   --help=skill        Strategic guidance (separate axis)
///
/// Call `HelpSystem.interceptIfNeeded()` at the start of `main()` before
/// ArgumentParser runs. If a help flag is detected, it prints the appropriate
/// content and calls exit(0).
public enum HelpSystem {

    /// Check process arguments for help flags and handle them if found.
    /// This must be called before ArgumentParser parses arguments.
    /// If a help request is detected, this function prints help and exits (does not return).
    public static func interceptIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        // args[0] is the binary path; skip it
        let flags = Array(args.dropFirst())

        // Detect --help=skill anywhere in the arguments
        let hasHelpSkill = flags.contains { $0 == "--help=skill" }

        // Detect --help or -h anywhere in the arguments
        let hasHelp = flags.contains { $0 == "--help" || $0 == "-h" }

        // Detect --verbose anywhere in the arguments
        let hasVerbose = flags.contains { $0 == "--verbose" }

        // Must have some help flag to proceed
        guard hasHelpSkill || hasHelp else { return }

        // Determine the subcommand (first non-flag argument)
        let subcommand = findSubcommand(in: flags)

        if hasHelpSkill {
            if let content = HelpContent.skill(for: subcommand) {
                print(content)
            } else if let cmd = subcommand {
                fputs("No skill guidance available for '\(cmd)'\n", stderr)
                _exit(1)
            }
            _exit(0)
        }

        if hasHelp && hasVerbose {
            if let content = HelpContent.verbose(for: subcommand) {
                print(content)
            } else if let cmd = subcommand {
                fputs("No verbose help available for '\(cmd)'\n", stderr)
                _exit(1)
            }
            _exit(0)
        }

        // Plain --help: use our concise content (with self-referencing footer)
        if hasHelp {
            if let content = HelpContent.concise(for: subcommand) {
                print(content)
            } else {
                // Unknown subcommand — fall through to let ArgumentParser handle it
                return
            }
            _exit(0)
        }
    }

    /// Find the first argument that looks like a subcommand (not a flag).
    private static func findSubcommand(in flags: [String]) -> String? {
        for flag in flags {
            // Skip flags (including --help=skill which contains no space)
            if flag.hasPrefix("-") { continue }
            // Check if it's a known command
            if HelpContent.supportedCommands.contains(flag) {
                return flag
            }
        }
        return nil
    }
}
