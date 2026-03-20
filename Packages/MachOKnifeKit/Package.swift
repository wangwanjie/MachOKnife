// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MachOKnifeKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MachOKnifeKit",
            targets: ["MachOKnifeKit"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreMachO"),
    ],
    targets: [
        .target(
            name: "MachOKnifeKit",
            dependencies: [
                .product(name: "CoreMachO", package: "CoreMachO"),
            ]
        ),
        .testTarget(
            name: "MachOKnifeKitTests",
            dependencies: ["MachOKnifeKit"]
        ),
    ]
)
