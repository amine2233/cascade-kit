// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotesMCP",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .target(
            name: "NotesKit",
            dependencies: [.product(name: "CascadeKit", package: "cascade-kit")]
        ),
        .executableTarget(
            name: "NotesServer",
            dependencies: [
                "NotesKit",
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "NotesKitTests",
            dependencies: ["NotesKit", .product(name: "CascadeKit", package: "cascade-kit")]
        )
    ],
    swiftLanguageModes: [.v6]
)
