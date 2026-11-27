// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KView",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KView", targets: ["KView"])
    ],
    targets: [
        .executableTarget(
            name: "KView",
            path: "Sources"
        )
    ]
)
