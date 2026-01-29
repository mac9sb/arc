// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Arc",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "arc", targets: ["Arc"]),
        .library(name: "ArcDescription", targets: ["ArcDescription"]),
        .library(name: "ArcCore", targets: ["ArcCore"]),
        .library(name: "ArcServer", targets: ["ArcServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),

        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/tuist/Noora.git", .upToNextMajor(from: "0.15.0")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.87.0"),
    ],
    targets: [
        .executableTarget(
            name: "Arc",
            dependencies: [
                "ArcCLI"
            ]
        ),
        .target(
            name: "ArcCLI",
            dependencies: [
                "ArcCore",
                "ArcServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "ArcDescription",
            dependencies: []
        ),
        .target(
            name: "ArcServer",
            dependencies: [
                "ArcCore",
                .product(name: "Noora", package: "Noora"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .target(
            name: "ArcCore",
            dependencies: [
                "ArcDescription",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Noora", package: "Noora"),
            ]
        ),
        .testTarget(
            name: "ArcCoreTests",
            dependencies: [
                "ArcCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ArcServerTests",
            dependencies: [
                "ArcServer",
                "ArcCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ArcCLITests",
            dependencies: [
                "ArcCLI",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ArcIntegrationTests",
            dependencies: [
                "ArcCore",
                "ArcServer",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
