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
        .executable(name: "WhyText", targets: ["WhyText"]),
    ],
    targets: [
        .target(
            name: "WhyTextCore",
            path: "Sources/WhyTextCore"
        ),
        .executableTarget(
            name: "WhyText",
            dependencies: ["WhyTextCore"],
            path: "Sources/WhyText",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "WhyTextCoreSmokeTests",
            dependencies: ["WhyTextCore"],
            path: "Sources/WhyTextCoreSmokeTests"
        ),
    ]
)
