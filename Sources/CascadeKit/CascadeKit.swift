import Foundation

// =============================================================================
// MARK: - Lock

// =============================================================================

/// A minimal mutex wrapping `NSLock`.
///
/// Used instead of `Synchronization.Mutex` so the library back-deploys to all
/// supported OS versions (`Mutex` requires iOS 18 / macOS 15). Swap to `Mutex`
/// if your deployment target allows it.
final class Lock<State>: @unchecked Sendable {
    private let nslock = NSLock()
    private var state: State

    init(_ initial: State) {
        self.state = initial
    }

    /// Executes `body` while holding the lock.
    ///
    /// - Important: Never perform work that re-enters this same lock from
    ///   inside `body` — `NSLock` is non-recursive and will deadlock.
    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        nslock.lock()
        defer { nslock.unlock() }
        return try body(&state)
    }
}

// =============================================================================
// MARK: - Type-keyed Storage (the shared primitive)

// =============================================================================

/// A marker protocol that binds a *key type* to a *value type*.
///
/// Conforming types are never instantiated; they exist purely as compile-time
/// keys whose identity (`ObjectIdentifier(Self.self)`) indexes `Storage`.
public protocol StorageKey {
    /// The type of value stored under this key. Must be `Sendable` because
    /// stored values cross concurrency boundaries.
    associatedtype Value: Sendable
}

/// Type-erased box so a heterogeneous `Storage` can still run teardown logic.
private protocol AnyStorageValue: Sendable {
    func shutdown()
}

private struct StoredValue<T: Sendable>: AnyStorageValue {
    let value: T
    let onShutdown: (@Sendable (T) -> Void)?
    func shutdown() {
        onShutdown?(value)
    }
}

/// A thread-safe, type-keyed bag of values.
///
/// This is a reference type with value-by-key semantics: each `StorageKey`
/// addresses exactly one slot, and the key type guarantees the stored/retrieved
/// types match. It backs the Vapor-style `Container`. (The `@Dependency`
/// registry uses a separate, *value-typed* store — see `DependencyValues` —
/// because it needs copy semantics for scoped overriding.)
public final class Storage: Sendable {
    private let items: Lock<[ObjectIdentifier: any AnyStorageValue]>

    public init() {
        self.items = Lock([:])
    }

    /// Returns whether a value is registered for `key`.
    public func contains<Key: StorageKey>(_ key: Key.Type) -> Bool {
        items.withLock { $0[ObjectIdentifier(key)] != nil }
    }

    /// Returns the value stored under `key`, or `nil` if absent.
    public func get<Key: StorageKey>(_ key: Key.Type) -> Key.Value? {
        items.withLock { ($0[ObjectIdentifier(key)] as? StoredValue<Key.Value>)?.value }
    }

    /// Stores `value` under `key`, or removes it when `value` is `nil`.
    ///
    /// - Parameter onShutdown: Optional cleanup run when the value is removed
    ///   or when `shutdownAll()` is called (e.g. closing a connection pool).
    ///
    /// The shutdown closure for a *replaced* or *removed* value runs **outside**
    /// the lock, so a closure that itself touches storage cannot deadlock.
    public func set<Key: StorageKey>(
        _ key: Key.Type,
        to value: Key.Value?,
        onShutdown: (@Sendable (Key.Value) -> Void)? = nil
    ) {
        let id = ObjectIdentifier(key)
        let evicted: (any AnyStorageValue)? = items.withLock { items in
            let previous = items[id]
            if let value {
                items[id] = StoredValue(value: value, onShutdown: onShutdown)
            } else {
                items[id] = nil
            }
            return previous
        }
        evicted?.shutdown()
    }

    /// Runs every registered value's shutdown hook and empties the store.
    public func shutdownAll() {
        let all = items.withLock { items -> [any AnyStorageValue] in
            let values = Array(items.values)
            items.removeAll()
            return values
        }
        all.forEach { $0.shutdown() }
    }
}

// =============================================================================
// MARK: - Dependency registry (the @Dependency system)

// =============================================================================

/// Which set of default values resolution falls back to when a dependency has
/// not been explicitly overridden.
public enum DependencyContext: Sendable, Hashable {
    /// Production: uses `DependencyKey.liveValue`.
    case live
    /// SwiftUI previews: uses `DependencyKey.previewValue`.
    case preview
    /// Tests: uses `DependencyKey.testValue` (typically a mock or a failing stub).
    case test
}

/// A key describing one dependency, along with the value used when nobody has
/// overridden it.
///
/// `liveValue` is the lazy "factory": it is built **once per process** the first
/// time the dependency is resolved without an override, then cached. `testValue`
/// and `previewValue` default to `liveValue` but can be specialised — e.g. point
/// `testValue` at an unimplemented stub that fails the test if it is ever called
/// unexpectedly.
public protocol DependencyKey: Sendable {
    associatedtype Value: Sendable
    /// The value used in production (`.live` context). Built lazily, cached once.
    static var liveValue: Value { get }
    /// The value used in SwiftUI previews. Defaults to `liveValue`.
    static var previewValue: Value { get }
    /// The value used in tests. Defaults to `liveValue`.
    static var testValue: Value { get }
}

extension DependencyKey {
    public static var previewValue: Value {
        liveValue
    }

    public static var testValue: Value {
        liveValue
    }
}

/// Process-wide cache for lazily-built default values, keyed by (key type, context).
private struct DefaultCacheKey: Hashable {
    let id: ObjectIdentifier
    let context: DependencyContext
}

private let _defaultCache = Lock<[DefaultCacheKey: any Sendable]>([:])

/// The current set of dependency values, propagated implicitly down the task
/// tree (this is `EnvironmentValues` for non-SwiftUI async code).
///
/// Resolution order for a given key:
///   1. An explicit override stored via `withDependencies`.
///   2. Otherwise the context default (`liveValue`/`previewValue`/`testValue`),
///      cached once for `.live`/`.preview`, recomputed fresh for `.test`.
public struct DependencyValues: Sendable {
    /// The values in effect for the current task. Bound by `withDependencies`.
    @TaskLocal public static var current = DependencyValues()

    /// The fallback context for unoverridden keys. Defaults to `.live`.
    public var context: DependencyContext = .live

    /// Explicit overrides, keyed on the dependency key's metatype.
    private var storage: [ObjectIdentifier: any Sendable] = [:]

    public init() {}

    /// Reads or writes the value for `key`.
    ///
    /// - Writing stores an explicit override (what `withDependencies` mutates).
    /// - Reading returns the override if present, else the cached context default.
    public subscript<K: DependencyKey>(_ key: K.Type) -> K.Value {
        get {
            if let override = storage[ObjectIdentifier(key)] as? K.Value {
                return override
            }
            // No override: fall back to the context default.
            if context == .test {
                // Tests get a fresh default each time (no cross-test caching).
                return Self.makeDefault(key, context)
            }
            let cacheKey = DefaultCacheKey(id: ObjectIdentifier(key), context: context)
            if let cached = _defaultCache.withLock({ $0[cacheKey] as? K.Value }) {
                return cached
            }
            // Build OUTSIDE the lock: a `liveValue` may resolve other
            // dependencies, which would otherwise re-enter this lock.
            let made = Self.makeDefault(key, context)
            _defaultCache.withLock { $0[cacheKey] = made }
            return made
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    private static func makeDefault<K: DependencyKey>(
        _ key: K.Type,
        _ context: DependencyContext
    ) -> K.Value {
        switch context {
        case .live: K.liveValue
        case .preview: K.previewValue
        case .test: K.testValue
        }
    }
}

/// Reads a dependency by key path, resolving against the current task-local
/// `DependencyValues` at the moment of access.
///
/// Because resolution happens on access (not on init), a value declared as a
/// stored property of a reducer picks up whatever override is bound when the
/// reducer actually runs — which is exactly what makes test overrides work.
///
///     struct AppReducer {
///         @Dependency(\.apiClient) var apiClient
///         // ...
///     }
@propertyWrapper
public struct Dependency<Value: Sendable>: Sendable {
    /// A `Sendable`-constrained key path. Literal key paths (e.g. `\.apiClient`)
    /// are `Sendable` because they capture nothing non-`Sendable`, so call sites
    /// are unchanged. This is what lets `Dependency` conform to `Sendable` and
    /// therefore be stored in a `Sendable` reducer.
    private let keyPath: any KeyPath<DependencyValues, Value> & Sendable

    /// Creates a dependency reference for the given key path.
    public init(_ keyPath: any KeyPath<DependencyValues, Value> & Sendable) {
        self.keyPath = keyPath
    }

    /// The resolved value from the current dependency context.
    public var wrappedValue: Value {
        DependencyValues.current[keyPath: keyPath]
    }
}

// =============================================================================
// MARK: - withDependencies (scoping & test sugar)

// =============================================================================

/// Runs `operation` with a modified copy of the current dependencies.
///
/// The current values are copied, handed to `mutate` for adjustment, then bound
/// for the dynamic extent of `operation`. The binding ends automatically when
/// `operation` returns or throws — there is no teardown to forget.
///
///     withDependencies {
///         $0.apiClient = .mock(user: .stub)
///     } operation: {
///         // code here sees the mock
///     }
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) -> Void,
    operation: () throws -> R
) rethrows -> R {
    var values = DependencyValues.current
    mutate(&values)
    return try DependencyValues.$current.withValue(values) {
        try operation()
    }
}

/// Async overload of `withDependencies`.
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) -> Void,
    operation: () async throws -> R
) async rethrows -> R {
    var values = DependencyValues.current
    mutate(&values)
    return try await DependencyValues.$current.withValue(values) {
        try await operation()
    }
}

/// Test-focused sugar: switches the context to `.test` (so unoverridden keys
/// resolve to their `testValue`), then applies any explicit overrides.
///
///     await withTestDependencies {
///         $0.apiClient = .mock(user: .stub)
///     } operation: {
///         // unoverridden deps use their testValue; apiClient is the mock
///     }
@discardableResult
public func withTestDependencies<R>(
    _ mutate: (inout DependencyValues) -> Void = { _ in },
    operation: () async throws -> R
) async rethrows -> R {
    try await withDependencies {
        $0.context = .test
        mutate(&$0)
    } operation: {
        try await operation()
    }
}

/// Synchronous variant of `withTestDependencies`, for non-async reducers.
@discardableResult
public func withTestDependencies<R>(
    _ mutate: (inout DependencyValues) -> Void = { _ in },
    operation: () throws -> R
) rethrows -> R {
    try withDependencies {
        $0.context = .test
        mutate(&$0)
    } operation: {
        try operation()
    }
}

// =============================================================================
// MARK: - Optional: Vapor-style scoped container (make / register)

// =============================================================================
//
// This layer is independent of `@Dependency`. Use it when you need lazy
// factories with explicit singleton/transient scoping and an app→request
// fallback hierarchy (e.g. server-side). It builds on the same `Storage`.

/// A scope that owns a `Storage` and may delegate unresolved lookups upward.
public protocol Container: AnyObject, Sendable {
    /// This scope's storage (holds factories and cached singletons).
    var storage: Storage { get }
    /// The enclosing scope to fall back to (e.g. a request's application).
    var parent: (any Container)? { get }
}

/// A marker key binding a service key type to its value type.
public protocol ServiceKey: Sendable {
    associatedtype Value: Sendable
}

/// A lazy factory plus its lifetime scope.
public struct Factory<Service: Sendable>: Sendable {
    public enum Scope: Sendable {
        /// One instance, built on first `make` and cached on the owning container.
        case singleton
        /// A fresh instance on every `make`.
        case transient
    }

    let scope: Scope
    let build: @Sendable (any Container) -> Service
}

/// Two distinct generic specialisations give each `ServiceKey` two slots —
/// one for its factory, one for its cached singleton — for free and type-safely.
private struct FactoryKey<K: ServiceKey>: StorageKey {
    typealias Value = Factory<K.Value>
}

private struct CacheKey<K: ServiceKey>: StorageKey {
    typealias Value = K.Value
}

extension Container {
    /// Registers a factory for a service (Vapor calls this `use`).
    ///
    ///     app.register(DatabaseKey.self) { _ in PostgresDatabase(url: url) }
    ///     app.register(UserRepoKey.self) { c in
    ///         SQLUserRepository(db: c.make(DatabaseKey.self))   // pulls a dep
    ///     }
    public func register<K: ServiceKey>(
        _ key: K.Type,
        scope: Factory<K.Value>.Scope = .singleton,
        _ build: @escaping @Sendable (any Container) -> K.Value
    ) {
        storage.set(FactoryKey<K>.self, to: Factory(scope: scope, build: build))
    }

    /// Resolves a service, running its factory (and caching it, if a singleton).
    ///
    /// Resolution walks up to `parent` when the key is not registered locally,
    /// so a request resolves application-level singletons transparently.
    ///
    /// - Note: Factories run **outside** the storage lock, so a factory that
    ///   recursively `make`s its own dependencies cannot deadlock. The lazy
    ///   singleton cache uses a benign last-write-wins race under concurrent
    ///   first-touch; warm singletons up single-threaded at boot to avoid it.
    public func make<K: ServiceKey>(_ key: K.Type) -> K.Value {
        if let factory = storage.get(FactoryKey<K>.self) {
            switch factory.scope {
            case .transient:
                return factory.build(self)
            case .singleton:
                if let cached = storage.get(CacheKey<K>.self) {
                    return cached
                }
                let instance = factory.build(self) // built without the lock
                storage.set(CacheKey<K>.self, to: instance)
                return instance
            }
        }
        if let parent {
            return parent.make(key)
        }
        fatalError("No factory registered for \(K.self).")
    }
}

/// Process-scoped container: singletons live for the lifetime of the app.
public final class Application: Container {
    public let storage = Storage()
    public let parent: (any Container)? = nil
    public init() {}

    /// Explicit teardown (drains every registered service's shutdown hook).
    public func shutdown() {
        storage.shutdownAll()
    }
}

/// Request-scoped container: layers per-request state over the application,
/// falling through to it for anything not registered locally.
public final class Request: Container {
    public let storage = Storage()
    public let parent: (any Container)?
    public init(application: Application) {
        self.parent = application
    }
}
