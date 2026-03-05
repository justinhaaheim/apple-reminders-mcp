// swift-tools-version: 5.9
import PackageDescription

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
    ],
    dependencies: [
        .package(url: "https://github.com/adam-fowler/jmespath.swift", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AppleRemindersCore",
            dependencies: [
                .product(name: "JMESPath", package: "jmespath.swift"),
            ],
            path: "Sources/AppleRemindersCore"
        ),
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: ["AppleRemindersCore"],
            path: "Sources/AppleRemindersMCP"
        ),
    ]
)
