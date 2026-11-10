// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Heathy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QingXing", targets: ["Heathy"])],
    targets: [
        .target(name: "HeathyCore"),
        .executableTarget(name: "Heathy", dependencies: ["HeathyCore"]),
        .executableTarget(name: "HeathyTests", dependencies: ["HeathyCore"], path: "Tests/HeathyCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
