// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "GitPlus",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "GitPlus", path: "Sources/GitPlus"),
        .testTarget(name: "GitPlusTests", dependencies: ["GitPlus"], path: "Tests/GitPlusTests"),
    ],
    swiftLanguageModes: [.v5]
)
