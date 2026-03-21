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
        .package(url: "https://github.com/p-x9/MachOKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MachOKnifeKit",
            dependencies: [
                .product(name: "CoreMachO", package: "CoreMachO"),
                .product(name: "MachOKit", package: "MachOKit"),
            ]
        ),
        .testTarget(
            name: "MachOKnifeKitTests",
            dependencies: ["MachOKnifeKit"]
        ),
    ]
)
