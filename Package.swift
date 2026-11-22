// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Do",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Do", targets: ["Do"])],
    targets: [
        .executableTarget(name: "Do")
    ]
)
