// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HummingbirdExample",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "TodoApp",
            dependencies: [
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "Hummingbird", package: "hummingbird")
            ]
        ),
        .executableTarget(name: "Run", dependencies: ["TodoApp"]),
        .testTarget(
            name: "TodoAppTests",
            dependencies: [
                "TodoApp",
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
