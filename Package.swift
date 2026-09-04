// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DevBar", targets: ["DevBar"])
    ],
    targets: [
        .executableTarget(
            name: "DevBar",
            path: "DevBar"
        ),
        .testTarget(
            name: "DevBarTests",
            dependencies: ["DevBar"],
            path: "Tests/DevBarTests"
        )
    ]
)
