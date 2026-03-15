// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitBeaconApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitBeaconApp",
            path: "Sources/GitBeaconApp"
        )
    ]
)
