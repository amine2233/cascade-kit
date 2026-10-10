// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CascadeCLI",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/amine2233/cascade-kit.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "CLIKit", dependencies: [.product(name: "CascadeKit", package: "cascade-kit")]),
        .executableTarget(
            name: "cascade-cli",
            dependencies: [
                "CLIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "CLIKitTests",
            dependencies: ["CLIKit", .product(name: "CascadeKit", package: "cascade-kit")]
        )
    ],
    swiftLanguageModes: [.v6]
)
