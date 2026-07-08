// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhosttyVtSPM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "GhosttyVt", targets: ["GhosttyVt"]),
    ],
    targets: [
        .target(
            name: "GhosttyVt",
            dependencies: ["GhosttyVtPrebuilt"],
            path: "Sources/GhosttyVt"
        ),
        .binaryTarget(
            name: "GhosttyVtPrebuilt",
            path: "binary/GhosttyVtPrebuilt.xcframework"
        ),
    ]
)
