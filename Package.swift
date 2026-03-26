// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiCodeSwitch",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AiCodeSwitch", targets: ["AiCodeSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "AiCodeSwitch",
            path: "Sources/AiCodeSwitch",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AiCodeSwitchTests",
            dependencies: ["AiCodeSwitch"],
            path: "Tests/AiCodeSwitchTests"
        )
    ]
)
