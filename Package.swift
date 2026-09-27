// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "HerdrBridge", platforms: [.macOS(.v13)],
    products: [.executable(name: "HerdrBridge", targets: ["HerdrBridge"])],
    targets: [
        .target(name: "BridgeCore"),
        .executableTarget(name: "HerdrBridge", dependencies: ["BridgeCore"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"])
    ]
)
