// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenViewer", targets: ["TokenViewer"])
    ],
    targets: [
        .executableTarget(
            name: "TokenViewer",
            path: "Sources/TokenViewer"
        ),
        .testTarget(
            name: "TokenViewerTests",
            dependencies: ["TokenViewer"],
            path: "Tests/TokenViewerTests"
        )
    ]
)
