// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmberCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EmberCore", targets: ["EmberCore"]),
    ],
    targets: [
        .target(name: "EmberCore"),
        .testTarget(name: "EmberCoreTests", dependencies: ["EmberCore"]),
    ]
)
