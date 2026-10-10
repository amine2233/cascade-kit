# CascadeKit v2 API cheat sheet

```swift
import CascadeKit
```

## Declare a dependency

```swift
protocol Clock: Sendable { func now() -> Date }

struct ClockKey: DependencyKey {
    static let liveValue: any Clock = ClockSystem()
    static let testValue: any Clock = ClockFixed(Date(timeIntervalSince1970: 0))
}

extension DependencyValues {
    var clock: any Clock {
        get { self[ClockKey.self] }
        set { self[ClockKey.self] = newValue }
    }
}
```

`previewValue` and `testValue` default to `liveValue`. Contexts: `.live`, `.preview`, `.test`.

## Read it

```swift
struct Feature {
    @Dependency(\.clock) var clock
}
```

The value is resolved on every read from the task-local `DependencyValues.current`.

## Override in a scope

```swift
withDependencies { $0.clock = ClockFixed(date) } operation: { … }

await withTestDependencies { $0.clock = ClockFixed(date) } operation: { … }
```

Async overloads take `isolation:` and run the operation on the caller's actor, so `@MainActor` code can use main-actor state inside.

`withTestDependencies` switches to `.test`, unbinds any inherited container and builds each `testValue` once per scope.

## Containers

```swift
let app = AppScope()
app.register(DatabaseKey.self, onShutdown: { $0.close() }) { _ in Database(url: url) }
app.register(RepoKey.self, lifetime: .transient) { c in RepoPostgres(database: c.make(DatabaseKey.self)) }

let request = RequestScope(application: app)
let repo = request.make(RepoKey.self)
let maybe = request.resolveIfRegistered(RepoKey.self)
let checked = try request.resolve(RepoKey.self)
app.shutdown()
```

Keys used with containers conform to `StorageKey` (`typealias Value = …`). A `DependencyKey` is also a `StorageKey`, so one key works in both styles.

| Lifetime | Behavior |
| --- | --- |
| `.singleton` (default) | Built once, cached on the registering container, concurrent first callers wait for one build, `onShutdown` runs on `shutdown()` |
| `.transient` | Built on every resolution, no shutdown |

## Bind a container to `@Dependency`

```swift
try await withDependencies {
    $0.container = app
} operation: {
    @Dependency(\.database) var database
}
```

## Propagation

| API | Overrides propagate? |
| --- | --- |
| `async let`, child task, `TaskGroup`, `Task { }` | Yes |
| `Task.detached`, `DispatchQueue.async`, callbacks | No |

```swift
let values = DependencyValues.current
Task.detached { await DependencyValues.$current.withValue(values) { await work() } }
```

## ServiceStorage

```swift
let storage = ServiceStorage()
storage.set(PoolKey.self, to: pool, onShutdown: { $0.close() })
storage.get(PoolKey.self)
storage.removeValue(for: PoolKey.self)
storage.shutdownAll()
```

## Errors

`CascadeKitError.serviceNotRegistered(String)` is the only error type.
