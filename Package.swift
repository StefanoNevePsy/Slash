// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Slash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Slash", path: "Sources/Slash")
    ]
)
