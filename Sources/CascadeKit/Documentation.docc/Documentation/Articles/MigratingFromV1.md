# Migrating from v1 to v2

Every breaking change in v2, with the replacement for each.

## Requirements

v2 requires iOS 18 and macOS 15. v1 declared iOS 13 and macOS 10.15; stay on v1 if you support older systems. v1 receives no further fixes.

The internal `NSLock`-based `Lock` class is gone. v2 uses `Synchronization.Mutex` and contains no `@unchecked Sendable` types. `Lock` was never public, so no code should depend on it.

## Renamed types

| v1 | v2 |
| --- | --- |
| `Application` | ``AppScope`` |
| `Request` | ``RequestScope`` |
| `Storage` | ``ServiceStorage`` |

The new names do not clash with Vapor's `Application` and `Request`.

```swift
// v1
let app = Application()
let request = Request(application: app)

// v2
let app = AppScope()
let request = RequestScope(application: app)
```

## One key protocol

`ServiceKey` is removed. Use ``StorageKey``, or ``DependencyKey`` when you also want `@Dependency` defaults. ``DependencyKey`` now refines ``StorageKey`` and keeps its `Value` associated type.

```swift
// v1
enum DatabaseKey: ServiceKey { typealias Value = Database }

// v2
enum DatabaseKey: StorageKey { typealias Value = Database }
```

## Registering services

`Factory<Service>.Scope` is now the top-level ``ServiceLifetime``, and the argument label is `lifetime:`. `register` gained an `onShutdown:` parameter.

```swift
// v1
app.register(DatabaseKey.self, scope: .transient) { _ in Database() }

// v2
app.register(DatabaseKey.self, lifetime: .transient) { _ in Database() }
app.register(PoolKey.self, onShutdown: { $0.close() }) { _ in Pool() }
```

## ServiceStorage

`set(_:to:)` takes a non-optional value. Removal moved to `removeValue(for:)`.

```swift
// v1
storage.set(PoolKey.self, to: nil)

// v2
storage.removeValue(for: PoolKey.self)
```

## Resolving

`make(_:)` still traps when nothing is registered. Use the new `resolve(_:)` to handle that case, or `resolveIfRegistered(_:)` for an optional.

```swift
let database = try app.resolve(DatabaseKey.self)
```

`Container` has a new `resolveIfRegistered(_:)` requirement with a default implementation, so existing conformers keep compiling. Override it to customize resolution through `any Container`.

## Behavior changes

These compile unchanged but behave differently.

- **Singletons are built once.** Concurrent first use waits for one build. In v1 two callers could both run the factory, and one instance silently replaced the other.
- **Singleton factories run under root values.** They no longer see the caller's `withDependencies` overrides, so a request or test override is never captured in a cached instance. Transient factories still see them.
- **Shutdown hooks run.** Services registered with `onShutdown:` are torn down by `shutdown()`.
- **`testValue` is cached per scope.** Inside one `withTestDependencies`, repeated reads return the same instance. In v1 each read built a new one. Code that relied on a fresh instance per read must call the builder explicitly.
- **`liveValue` and `previewValue` are built once** even under concurrent first use.
- **Re-entry traps.** A factory or default that resolves its own key now traps with `Recursive resolution of <Key>` instead of overflowing the stack.
- **`withTestDependencies` unbinds the container.** A container bound outside the scope is ignored; bind it inside to opt in.

```swift
await withTestDependencies {
    $0.container = app
} operation: { … }
```

## New in v2

- `DependencyValues.container` makes container registrations available to `@Dependency`. See <doc:CompleteGuide>.
- ``CascadeKitError`` and `resolve(_:)` for recoverable missing registrations.
- `isolation:` on the async `withDependencies` and `withTestDependencies`, so the operation runs on the caller's actor.

## Checklist

1. Raise your deployment target to iOS 18 or macOS 15.
2. Rename `Application`, `Request` and `Storage`.
3. Replace `ServiceKey` with `StorageKey`.
4. Change `scope:` to `lifetime:` and replace `set(_:to: nil)` with `removeValue(for:)`.
5. Run your tests and check any stateful `testValue` for the per-scope caching change.
