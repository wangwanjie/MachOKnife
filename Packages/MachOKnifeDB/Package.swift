// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MachOKnifeDB",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MachOKnifeDB",
            targets: ["MachOKnifeDB"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "MachOKnifeDB",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "MachOKnifeDBTests",
            dependencies: ["MachOKnifeDB"]
        ),
    ]
)
