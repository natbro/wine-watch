// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WineWatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WineWatch",
            path: "Sources/WineWatch"
        )
    ]
)
