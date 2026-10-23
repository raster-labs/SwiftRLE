// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "Consumer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "SwiftRLE", package: "SwiftRLE")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
