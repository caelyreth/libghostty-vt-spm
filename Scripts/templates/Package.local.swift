// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhosttyVtSPM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
    ],
    products: [
        .library(name: "GhosttyVt", targets: ["GhosttyVt"]),
        .library(name: "GhosttyVtGraphics", targets: ["GhosttyVtGraphics"]),
        .library(name: "GhosttyVtRaw", targets: ["GhosttyVtRaw"]),
    ],
    targets: [
        .target(
            name: "GhosttyVt",
            dependencies: ["GhosttyVtRaw"],
            path: "Sources/GhosttyVt"
        ),
        .target(
            name: "GhosttyVtRaw",
            dependencies: ["GhosttyVtPrebuilt"],
            path: "Sources/GhosttyVtRaw"
        ),
        .target(
            name: "GhosttyVtGraphics",
            dependencies: ["GhosttyVt", "GhosttyVtRaw"],
            path: "Sources/GhosttyVtGraphics"
        ),
        .testTarget(
            name: "GhosttyVtTests",
            dependencies: ["GhosttyVt", "GhosttyVtGraphics"],
            path: "Tests/GhosttyVtTests"
        ),
        .binaryTarget(
            name: "GhosttyVtPrebuilt",
            path: "binary/GhosttyVtPrebuilt.xcframework"
        ),
    ]
)
