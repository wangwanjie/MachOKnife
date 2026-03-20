// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetagEngine",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "RetagEngine",
            targets: ["RetagEngine"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreMachO"),
    ],
    targets: [
        .target(
            name: "RetagEngine",
            dependencies: ["CoreMachO"]
        ),
        .testTarget(
            name: "RetagEngineTests",
            dependencies: ["RetagEngine"]
        ),
    ]
)
