// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "VikunjaBar",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "VikunjaCore"),
        .executableTarget(name: "VikunjaBar", dependencies: ["VikunjaCore"]),
        .testTarget(name: "VikunjaCoreTests", dependencies: ["VikunjaCore"]),
    ]
)
