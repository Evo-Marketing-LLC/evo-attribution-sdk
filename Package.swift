// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EVOAttribution",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "EVOAttribution",
            targets: ["EVOAttribution"]
        ),
    ],
    targets: [
        .target(name: "EVOAttribution"),
        .testTarget(
            name: "EVOAttributionTests",
            dependencies: ["EVOAttribution"]
        ),
    ]
)
