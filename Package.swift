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
        .testTarget(
            name: "GhosttyVtTests",
            dependencies: ["GhosttyVt"],
            path: "Tests/GhosttyVtTests"
        ),
        .binaryTarget(
            name: "GhosttyVtPrebuilt",
            url: "https://github.com/caelyreth/libghostty-vt-spm/releases/download/0.2.0/GhosttyVtPrebuilt.xcframework.zip",
            checksum: "7d12fd0141507b355bc9a8ce9c1c6d2e9a1cb9a778bebd672c10d27641f4aba9"
        ),
    ]
)
