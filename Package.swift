// swift-tools-version: 6.2.3
import PackageDescription

let package = Package(
  name: "Arc",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "arc", targets: ["Arc"]),
    .library(name: "ArcCore", targets: ["ArcCore"]),
    .library(name: "ArcServer", targets: ["ArcServer"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    .package(url: "https://github.com/apple/pkl-swift.git", from: "0.3.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/tuist/Noora.git", .upToNextMajor(from: "0.15.0")),
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
      name: "ArcServer",
      dependencies: [
        "ArcCore",
        .product(name: "Noora", package: "Noora"),
      ]
    ),
    .target(
      name: "ArcCore",
      dependencies: [
        .product(name: "PklSwift", package: "pkl-swift"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Noora", package: "Noora"),
      ]
    ),
  ]
)
