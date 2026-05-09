// swift-tools-version: 5.9
import PackageDescription

// On Apple platforms, `import SQLite3` resolves to the system module shipped
// with the SDK. On Linux (used for CI / development tooling), Swift has no
// built-in SQLite3 module, so we provide our own system library target
// pointing at the platform's libsqlite3-dev. ReminderDBReader picks the
// right one with `#if canImport(SQLite3)` / `#elseif canImport(CSQLite3)`.
//
// We always declare the CSQLite3 target so SwiftPM doesn't treat the
// `Sources/CSQLite3/` directory as an implicit Swift target on Apple
// platforms — but AppleRemindersCore only depends on it when the SDK
// doesn't already provide SQLite3, so its pkgConfig/link directives are
// inert on macOS (no sqlite3.pc lookup, no extra linker flags).
#if canImport(Darwin)
let sqliteCoreDeps: [PackageDescription.Target.Dependency] = [
    .product(name: "JMESPath", package: "jmespath.swift")
]
#else
let sqliteCoreDeps: [PackageDescription.Target.Dependency] = [
    .product(name: "JMESPath", package: "jmespath.swift"),
    "CSQLite3",
]
#endif

let package = Package(
    name: "AppleRemindersTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppleRemindersCore",
            targets: ["AppleRemindersCore"]
        ),
        .executable(
            name: "apple-reminders-mcp",
            targets: ["AppleRemindersMCP"]
        ),
        .executable(
            name: "reminders",
            targets: ["AppleRemindersCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/adam-fowler/jmespath.swift", from: "1.0.0"),
        // 1.6+ uses `internal import os`, which on macOS-14's default Xcode
        // (Swift 5.9) requires `-enable-experimental-feature AccessLevelOnImport`.
        // Pin to <1.6 to keep CI building on the stock toolchain.
        .package(url: "https://github.com/apple/swift-argument-parser", "1.3.0" ..< "1.6.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite3",
            path: "Sources/CSQLite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
            ]
        ),
        .target(
            name: "AppleRemindersCore",
            dependencies: sqliteCoreDeps,
            path: "Sources/AppleRemindersCore"
        ),
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: ["AppleRemindersCore"],
            path: "Sources/AppleRemindersMCP"
        ),
        .executableTarget(
            name: "AppleRemindersCLI",
            dependencies: [
                "AppleRemindersCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AppleRemindersCLI"
        ),
        .testTarget(
            name: "AppleRemindersCoreTests",
            dependencies: ["AppleRemindersCore"],
            path: "Tests/AppleRemindersCoreTests"
        ),
    ]
)
