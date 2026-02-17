// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhyText",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "WhyText", targets: ["WhyText"]),
    ],
    targets: [
        .executableTarget(
            name: "WhyText",
            path: "Sources/WhyText",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
    ]
)
