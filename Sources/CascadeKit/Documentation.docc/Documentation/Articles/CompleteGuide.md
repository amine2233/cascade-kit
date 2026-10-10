# Complete Guide

Every feature of CascadeKit and the rules that decide which value you get.

## Keys

``StorageKey`` binds a key type to a value type. Key types are never instantiated.

```swift
enum PoolKey: StorageKey { typealias Value = ConnectionPool }
```

``DependencyKey`` refines ``StorageKey`` and adds the defaults for each ``DependencyContext``. The same key works in both setup styles.

```swift
enum PoolKey: DependencyKey {
    static let liveValue = ConnectionPool(url: productionURL)
    static var testValue: ConnectionPool { ConnectionPool(url: inMemoryURL) }
}
```

| Context | Value used | When |
| --- | --- | --- |
| `.live` | `liveValue` | Default |
| `.preview` | `previewValue` | SwiftUI previews, defaults to `liveValue` |
| `.test` | `testValue` | Inside `withTestDependencies`, defaults to `liveValue` |

## Reading a dependency

```swift
struct Handler {
    @Dependency(\.pool) var pool
}
```

``Dependency`` reads ``DependencyValues/current``, a task-local, every time it is accessed.

## Which value do you get

For each read, in order:

1. An explicit override set with `withDependencies` or `withTestDependencies`.
2. A registration on the bound `container`, if one is bound.
3. The context default: `liveValue`, `previewValue` or `testValue`.

In the `.test` context a container is ignored unless you bind it inside `withTestDependencies`, so a test that forgets an override reaches `testValue` instead of a real registration.

```swift
await withTestDependencies {
    $0.container = app
} operation: {
    // registrations on app now win over testValue
}
```

## Default value lifetimes

- `liveValue` and `previewValue` are built once per process, even under concurrent first use.
- `testValue` is built once per `withTestDependencies` scope. Two reads in one scope return the same instance, so a stateful stub keeps its state. A new scope gets a new instance, and a nested `withDependencies` shares its parent's cache.
- A default that reads its own key traps with `Recursive resolution of <Key>` instead of overflowing the stack.

## Scoped overrides

```swift
withDependencies {
    $0.clock = TestClock()
} operation: {
    // code here sees the test clock
}
```

The binding ends when the operation returns or throws. The async overloads take an `isolation:` parameter and run the operation on the caller's actor, so a `@MainActor` caller can use main-actor state inside it.

### Where overrides propagate

| API | Overrides propagate? |
| --- | --- |
| `async let`, child task, `TaskGroup` | Yes |
| `Task { … }` | Yes |
| `Task.detached { … }` | No |
| `DispatchQueue.async`, callbacks | No |

Where they do not, capture the values and bind them again:

```swift
let values = DependencyValues.current
Task.detached {
    await DependencyValues.$current.withValue(values) { await effect() }
}
```

## Containers

A ``Container`` owns a ``ServiceStorage`` and may fall back to a parent. ``AppScope`` lives for the process; ``RequestScope`` layers per-request state over an application.

```swift
let app = AppScope()
app.register(DatabaseKey.self, onShutdown: { $0.close() }) { _ in Database(url: url) }
app.register(UserRepositoryKey.self, lifetime: .transient) { container in
    UserRepositoryPostgres(database: container.make(DatabaseKey.self))
}

let request = RequestScope(application: app)
let repository = request.make(UserRepositoryKey.self)
```

### Lifetimes

``ServiceLifetime`` is `.singleton` (the default) or `.transient`.

- A singleton is built once on first use and cached on the container that registered it. Concurrent first callers wait for the one build.
- A transient service is built on every resolution and has no shutdown.
- A singleton factory runs under root `DependencyValues`: no overrides, with its own container bound. A caller's override is never captured in a cached instance. A transient factory sees its caller's values.

### Resolving

| Method | When nothing is registered |
| --- | --- |
| `make(_:)` | Traps with `No factory registered for <Key>.` |
| `resolve(_:)` | Throws ``CascadeKitError/serviceNotRegistered(_:)`` |
| `resolveIfRegistered(_:)` | Returns `nil` |

A factory that resolves its own key traps with `Recursive resolution of <Key>`.

### Shutdown

`register(_:lifetime:onShutdown:_:)` takes a hook that runs once for each singleton that was built when `shutdown()` is called. Hooks run outside the storage lock.

```swift
app.shutdown()
```

## Using both styles together

Bind a container to make registrations injectable:

```swift
let app = AppScope()
app.register(DatabaseKey.self) { _ in Database(url: url) }

await withDependencies {
    $0.container = app
} operation: {
    @Dependency(\.database) var database
    // database is the registered singleton
}
```

Bind a `RequestScope` per request so handlers see request-scoped registrations and the application's singletons through `@Dependency`.

## ServiceStorage

A thread-safe, type-keyed bag for values that need shutdown hooks. `Container` is built on it.

```swift
let storage = ServiceStorage()
storage.set(PoolKey.self, to: pool, onShutdown: { $0.close() })
let pool = storage.get(PoolKey.self)
storage.removeValue(for: PoolKey.self)
storage.shutdownAll()
```

`set` and `removeValue` run the shutdown hook of the value they replace or remove.

## Errors

``CascadeKitError`` is the module's only error type.

```swift
do {
    let database = try app.resolve(DatabaseKey.self)
} catch CascadeKitError.serviceNotRegistered(let name) {
    logger.error("Missing service \(name)")
}
```
