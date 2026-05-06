// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OvergraphSwiftBridge",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "OvergraphSwiftBridge",
      targets: ["OvergraphSwiftBridge"]
    ),
    .executable(
      name: "overgraph-cli",
      targets: ["OvergraphCLI"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
  ],
  targets: [
    .target(
      name: "COvergraphBridge",
      publicHeadersPath: "include",
      linkerSettings: [
        .unsafeFlags([
          "-L", "BridgeArtifacts/lib",
          "-lovergraph_swift_bridge",
        ])
      ]
    ),
    .target(
      name: "OvergraphSwiftBridge",
      dependencies: ["COvergraphBridge"]
    ),
    .executableTarget(
      name: "OvergraphCLI",
      dependencies: [
        "OvergraphSwiftBridge",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "OvergraphSwiftBridgeTests",
      dependencies: ["OvergraphSwiftBridge"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
