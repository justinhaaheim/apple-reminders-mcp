// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleRemindersMCP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "apple-reminders-mcp",
            targets: ["AppleRemindersMCP"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppleRemindersMCP",
            path: "Sources"
        )
    ]
)
