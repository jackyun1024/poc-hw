// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "toss-vision",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "toss-vision",
            path: "Sources"
        )
    ]
)
