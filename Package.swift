// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DodoCheckIn",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DodoCore", targets: ["DodoCore"])],
    targets: [
        .target(name: "DodoCore", resources: [.process("Resources")]),
        .testTarget(name: "DodoCoreTests", dependencies: ["DodoCore"])
    ]
)
