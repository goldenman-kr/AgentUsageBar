// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
        .library(name: "ClaudeUsageUI", targets: ["ClaudeUsageUI"]),
        .executable(name: "usage-probe", targets: ["usage-probe"])
    ],
    targets: [
        // Pure data pipeline: models, Keychain, API client, formatters. No UI.
        .target(
            name: "ClaudeUsageCore"
        ),
        // Shared SwiftUI components reused by the menu-bar app and the widget.
        .target(
            name: "ClaudeUsageUI",
            dependencies: ["ClaudeUsageCore"]
        ),
        // CLI that verifies the pipeline against the live API.
        .executableTarget(
            name: "usage-probe",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        )
    ]
)
