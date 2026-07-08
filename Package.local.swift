// swift-tools-version: 6.0
import Foundation
import PackageDescription

let useSystemLibrary = ProcessInfo.processInfo.environment["GHOSTTY_VT_DISABLE_BINARY"] == "1"

let products: [Product] = [
    .library(name: "GhosttyVt", targets: ["GhosttyVt"]),
]

let targets: [Target] = if useSystemLibrary {
    [
        .systemLibrary(
            name: "GhosttyVt",
            path: "Sources/GhosttyVtSystem"
        ),
    ]
} else {
    [
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
}

let package = Package(
    name: "GhosttyVtSPM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    products: products,
    targets: targets
)
