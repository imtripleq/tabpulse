// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TabPulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TabPulse", path: "Sources/TabPulse")
    ]
)
