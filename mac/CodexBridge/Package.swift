// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexBridge",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CodexBridge", targets: ["CodexBridge"])],
    targets: [
        .executableTarget(name: "CodexBridge"),
        .testTarget(name: "CodexBridgeTests", dependencies: ["CodexBridge"])
    ]
)
