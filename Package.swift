// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhyText",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "WhyTextCore", targets: ["WhyTextCore"]),
        .library(name: "WhyTextApp", targets: ["WhyTextApp"]),
        .executable(name: "WhyText", targets: ["WhyText"]),
        .executable(name: "WhyTextCoreSmokeTests", targets: ["WhyTextCoreSmokeTests"]),
        .executable(name: "WhyTextStateMachineTests", targets: ["WhyTextStateMachineTests"]),
    ],
    targets: [
        .target(
            name: "WhyTextCore",
            path: "Sources/WhyTextCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "WhyTextApp",
            dependencies: ["WhyTextCore"],
            path: "Sources/WhyText",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "WhyText",
            dependencies: ["WhyTextApp"],
            path: "Sources/WhyTextMain",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        // Executable smoke tests stay portable for Command Line Tools–only setups.
        // Full Xcode also exposes these via `swift run WhyTextCoreSmokeTests`.
        .executableTarget(
            name: "WhyTextCoreSmokeTests",
            dependencies: ["WhyTextCore"],
            path: "Sources/WhyTextCoreSmokeTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "WhyTextStateMachineTests",
            dependencies: ["WhyTextApp", "WhyTextCore"],
            path: "Sources/WhyTextStateMachineTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
