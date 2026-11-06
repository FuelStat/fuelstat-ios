// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FuelstatCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FuelstatCore", targets: ["FuelstatCore"])
    ],
    targets: [
        .target(name: "FuelstatCore"),
        .testTarget(name: "FuelstatCoreTests", dependencies: ["FuelstatCore"])
    ]
)
