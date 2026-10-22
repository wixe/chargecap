// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChargeCap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "chargecap",
            targets: ["ChargeCapCLI"]
        ),
        .library(
            name: "ChargeCapCore",
            targets: ["ChargeCapCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ChargeCapCore",
            dependencies: [],
            path: "Sources/ChargeCapCore"
        ),
        .executableTarget(
            name: "ChargeCapCLI",
            dependencies: ["ChargeCapCore"],
            path: "Sources/ChargeCapCLI"
        ),
        .testTarget(
            name: "ChargeCapTests",
            dependencies: ["ChargeCapCore"],
            path: "Tests/ChargeCapTests"
        )
    ]
)
