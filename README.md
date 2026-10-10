# CascadeKit

Dependency injection for Swift with two setup styles that work together: implicit task-local `@Dependency` and an explicit scoped `Container`. No dependencies. Swift 6, iOS 18 / macOS 15.

## Features

- `DependencyKey`, `DependencyValues`, `@Dependency`: implicit, task-local injection with `live`, `preview` and `test` contexts.
- `AppScope`, `RequestScope`, `register` / `make` / `resolve`: explicit scoped container with singleton and transient lifetimes and shutdown hooks.
- Bind a container with `withDependencies { $0.container = app }` and `@Dependency` returns its registrations.
- `withDependencies` and `withTestDependencies` for scoped overrides.
- `ServiceStorage`: thread-safe, type-keyed storage with shutdown hooks.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/amine2233/cascade-kit.git", from: "2.0.0"),
],
```

Then add `CascadeKit` to your target's dependencies.

## Quick start

```swift
struct APIClientKey: DependencyKey {
    static let liveValue: any APIClient = APIClientLive()
    static let testValue: any APIClient = APIClientStub()
}

extension DependencyValues {
    var apiClient: any APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

struct ItemsFeature {
    @Dependency(\.apiClient) var apiClient
}

await withTestDependencies {
    $0.apiClient = APIClientStub(items: [.sample])
} operation: {
    // ItemsFeature sees the stub
}
```

## Documentation

The DocC catalog is in `Sources/CascadeKit/Documentation.docc`: a getting started article, a complete guide, a v1 to v2 migration guide and the examples overview. Build it with `mise run build_documentations`.

## Examples

Runnable packages in `Examples/`, each with its own `Package.swift` so the library stays dependency free:

- `Examples/CLI`: swift-argument-parser command-line tool.
- `Examples/VaporServer`: Vapor server with a request scope per request.
- `Examples/HummingbirdTodo`: Hummingbird 2 server.
- `Examples/MCP`: stdio MCP server built on the Swift MCP SDK.

## Migrating from v1

See the migration guide in the DocC catalog (`MigratingFromV1.md`).

## Development

```bash
swift build
swift test
```

`mise.toml` defines helper tasks: `mise run format`, `mise run test`, `mise run release --dry-run`.
