// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinDock",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PinDock",
            path: "Sources/PinDock"
        )
    ]
)
