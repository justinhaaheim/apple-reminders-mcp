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
    dependencies: [
        .package(url: "https://github.com/adam-fowler/jmespath.swift", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: [
                .product(name: "JMESPath", package: "jmespath.swift")
            ],
            path: "Sources"
        )
    ]
)
