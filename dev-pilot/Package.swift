// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DevPilot",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "dev-pilot",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/DevPilot"
        ),
        .testTarget(
            name: "DevPilotTests",
            dependencies: ["dev-pilot"]
        ),
    ]
)
