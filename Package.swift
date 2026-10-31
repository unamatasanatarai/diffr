// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Diffr",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "Diffr",
            targets: ["Diffr"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Diffr",
            dependencies: [],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["Diffr"],
            path: "Tests/AppTests"
        )
    ]
)
