// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickMermaid",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuickMermaid"
        )
    ]
)
