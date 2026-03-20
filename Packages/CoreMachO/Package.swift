// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreMachO",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CoreMachO",
            targets: ["CoreMachO"]
        ),
    ],
    targets: [
        .target(
            name: "CoreMachOC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CoreMachO",
            dependencies: ["CoreMachOC"]
        ),
        .testTarget(
            name: "CoreMachOTests",
            dependencies: ["CoreMachO"]
        ),
    ]
)
