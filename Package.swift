// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChargePlan",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "chargeplan",
            targets: ["ChargePlanCLI"]
        ),
        .executable(
            name: "ChargePlanApp",
            targets: ["ChargePlanApp"]
        ),
        .library(
            name: "ChargePlanCore",
            targets: ["ChargePlanCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ChargePlanCore",
            dependencies: [],
            path: "Sources/ChargePlanCore"
        ),
        .executableTarget(
            name: "ChargePlanCLI",
            dependencies: ["ChargePlanCore"],
            path: "Sources/ChargePlanCLI"
        ),
        .executableTarget(
            name: "ChargePlanApp",
            dependencies: ["ChargePlanCore"],
            path: "Sources/ChargePlanApp"
        ),
        .testTarget(
            name: "ChargePlanTests",
            dependencies: ["ChargePlanCore"],
            path: "Tests/ChargePlanTests"
        )
    ]
)
