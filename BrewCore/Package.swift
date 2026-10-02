// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrewCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BrewCore", targets: ["BrewCore"])
    ],
    targets: [
        .target(
            name: "BrewCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrewCoreTests",
            dependencies: ["BrewCore"]
        )
    ]
)
