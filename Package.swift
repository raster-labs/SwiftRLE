// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "SwiftRLE",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftRLE",
            targets: ["SwiftRLE"]
        ),
        .executable(name: "swiftrle-cli", targets: ["SwiftRLECLI"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftRLECLI",
            dependencies: ["SwiftRLECLICore"],
            path: "Sources/SwiftRLECLI/Entry",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "SwiftRLECLICore",
            dependencies: ["SwiftRLE"],
            path: "Sources/SwiftRLECLI",
            exclude: ["Entry"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "SwiftRLE",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SwiftRLETests",
            dependencies: ["SwiftRLE"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SwiftRLECLITests",
            dependencies: ["SwiftRLECLICore", "SwiftRLE"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
