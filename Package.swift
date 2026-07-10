// swift-tools-version: 6.0
import PackageDescription

// Bump this before manually publishing a new package release.
let releaseVersion = "0.2.1"
let binaryArtifactVersion = "0.2.1"

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
            url: "https://github.com/caelyreth/libghostty-vt-spm/releases/download/\(binaryArtifactVersion)/GhosttyVtPrebuilt.xcframework.zip",
            checksum: "ea8f578e1f63e2a7b1cbc89eba71ad305affe2d41131cfc6132ed0a3f04129a2"
        ),
    ]
)
