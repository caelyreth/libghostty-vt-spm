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
    ],
    targets: [
        .target(
            name: "GhosttyVt",
            dependencies: ["GhosttyVtPrebuilt"],
            path: "Sources/GhosttyVt"
        ),
        .binaryTarget(
            name: "GhosttyVtPrebuilt",
            url: "https://github.com/caelyreth/libghostty-vt-spm/releases/download/0.1.0/GhosttyVtPrebuilt.xcframework.zip",
            checksum: "08211ebae23d18186b4d73799f8ee126235b0d72fb0a097988e4abc58a1a1113"
        ),
    ]
)
