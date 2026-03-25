// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSwitcher",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AiCodeSwitch", targets: ["CodexSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "CodexSwitcher",
            path: "Sources/CodexSwitcher",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexSwitcherTests",
            dependencies: ["CodexSwitcher"],
            path: "Tests/CodexSwitcherTests"
        )
    ]
)
