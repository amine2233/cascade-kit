// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cascade-kit-vapor-example",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.100.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .executableTarget(name: "Run", dependencies: ["App"]),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
