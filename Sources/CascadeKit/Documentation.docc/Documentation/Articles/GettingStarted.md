# Getting Started with CascadeKit

Add the package, declare a dependency, and override it in a test.

## Install

Add the package to your `Package.swift` and depend on the `CascadeKit` product:

```swift
dependencies: [
    .package(url: "https://github.com/amine2233/cascade-kit.git", from: "2.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["CascadeKit"]),
]
```

CascadeKit v2 requires iOS 18 or macOS 15 and Swift 6.

## Declare a dependency

A dependency has a key that supplies the values for each context and an accessor on ``DependencyValues``.

```swift
protocol APIClient: Sendable {
    func fetchItems() async throws -> [Item]
}

struct APIClientKey: DependencyKey {
    static let liveValue: any APIClient = APIClientLive()
    static let testValue: any APIClient = APIClientUnimplemented()
}

extension DependencyValues {
    var apiClient: any APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
```

`previewValue` defaults to `liveValue`, and so does `testValue` unless you provide one.

## Use it

```swift
struct ItemsFeature {
    @Dependency(\.apiClient) var apiClient

    func load() async throws -> [Item] {
        try await apiClient.fetchItems()
    }
}
```

The value is resolved when it is read, so a feature created before an override still sees it.

## Override it in a test

```swift
@Test
func loadsItems() async throws {
    let items = try await withTestDependencies {
        $0.apiClient = APIClientStub(items: [.sample])
    } operation: {
        try await ItemsFeature().load()
    }
    #expect(items == [.sample])
}
```

`withTestDependencies` switches the context to `.test`, so every key you did not override uses its `testValue`.

## Register services on a container

For a composition root, register factories on an ``AppScope`` and bind it:

```swift
let app = AppScope()
app.register(DatabaseKey.self, onShutdown: { $0.close() }) { _ in
    PostgresDatabase(url: databaseURL)
}

try await withDependencies {
    $0.container = app
} operation: {
    try await run()
}
app.shutdown()
```

Anything registered on the container is now what `@Dependency(\.database)` returns.

## Next steps

- <doc:CompleteGuide> covers every feature and the resolution rules.
- <doc:Examples> shows a command-line tool, Vapor, Hummingbird and an MCP server.
- <doc:MigratingFromV1> lists every breaking change.
