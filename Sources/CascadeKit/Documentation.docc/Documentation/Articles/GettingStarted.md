# Getting Started with CascadeKit

CascadeKit provides a small collection of concurrency-safe primitives and a
lightweight dependency registry for Swift apps and libraries.

## Install
Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/amine2233/cascade-kit.git", from: "0.1.0"),
],
```

Then add `CascadeKit` to your target dependencies.

## Import

```swift
import CascadeKit
```

## Basic primitives

### `Lock`
A thin mutex wrapper around `NSLock` for protecting mutable state.

```swift
final class Counter {
    private let lock = Lock(0)

    func increment() {
        lock.withLock { count in
            count += 1
        }
    }

    func value() -> Int {
        lock.withLock { $0 }
    }
}
```

### `Storage`
Type-keyed thread-safe storage. Useful for storing singleton resources or
ad-hoc values keyed by type.

```swift
struct DBKey: StorageKey { typealias Value = Database }

let storage = Storage()
storage.set(DBKey.self, to: postgresDB)
let db: Database? = storage.get(DBKey.self)
```

Shutdown hooks can be provided when registering values to cleanly close
resources.

## Dependency registry
CascadeKit provides a small `DependencyKey` protocol and an `@Dependency`
property wrapper for resolving values across contexts (`.live`, `.preview`,
`.test`).

### Define a dependency key

```swift
struct APIClientKey: DependencyKey {
    static var liveValue: APIClient { RealAPIClient() }
    static var testValue: APIClient { MockAPIClient() }
}

extension DependencyValues {
    var apiClient: APIClient { self[APIClientKey.self] }
}
```

### Use via `@Dependency`

```swift
struct Service {
    @Dependency(\.apiClient) var apiClient: APIClient

    func fetch() async throws {
        try await apiClient.fetchItems()
    }
}
```

### Override in tests

```swift
await withTestDependencies {
    $0.apiClient = MockAPIClient()
} operation: {
    // code runs with the mock
}
```

## Container & Factory (optional)
If you prefer a Vapor-style container with lazy factories and scoped singletons,
use `Container` and `register`/`make` APIs.

```swift
app.register(DatabaseKey.self) { _ in
    PostgresDatabase(url: dbURL)
}

let db = app.make(DatabaseKey.self)
```

## Building documentation locally
This repository includes a `mise` task that runs DocC:

```bash
mise run build_documentations
```

Or preview a single doc catalog in Xcode by opening the package and
choosing the `CascadeKit` scheme.

---

For more examples and API details, see the module sources in
`Sources/CascadeKit` and the unit tests in `Tests/CascadeKitTests`.
