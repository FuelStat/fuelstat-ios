// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FuelstatCore",
    platforms: [.iOS(.v27), .macOS(.v14)],
    products: [
        .library(name: "FuelstatCore", targets: ["FuelstatCore"])
    ],
    targets: [
        .target(name: "FuelstatCore"),
        .testTarget(name: "FuelstatCoreTests", dependencies: ["FuelstatCore"])
    ]
)
