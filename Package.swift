// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KMark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KMark", targets: ["KMark"])
    ],
    targets: [
        .executableTarget(
            name: "KMark",
            path: "Sources"
        )
    ]
)
