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
// MARK: - Type-keyed ServiceStorage (the shared primitive)

// =============================================================================

/// A marker protocol that binds a *key type* to a *value type*.
///
/// Conforming types are never instantiated; they exist purely as compile-time
/// keys whose identity (`ObjectIdentifier(Self.self)`) indexes `ServiceStorage`.
public protocol StorageKey {
    /// The type of value stored under this key. Must be `Sendable` because
    /// stored values cross concurrency boundaries.
    associatedtype Value: Sendable
}

/// Type-erased box so a heterogeneous `ServiceStorage` can still run teardown logic.
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
public final class ServiceStorage: Sendable {
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

    /// Returns the value under `key`, inserting `make()` atomically if absent.
    func value<Key: StorageKey>(_ key: Key.Type, orInsert make: () -> Key.Value) -> Key.Value {
        let id = ObjectIdentifier(key)
        return items.withLock { items in
            if let existing = (items[id] as? StoredValue<Key.Value>)?.value {
                return existing
            }
            let created = make()
            items[id] = StoredValue(value: created, onShutdown: nil)
            return created
        }
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
public protocol DependencyKey: StorageKey, Sendable {
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
///   2. A registration on the bound `container`, if any.
///   3. Otherwise the context default (`liveValue`/`previewValue`/`testValue`),
///      cached once for `.live`/`.preview`, recomputed fresh for `.test`.
public struct DependencyValues: Sendable {
    /// The values in effect for the current task. Bound by `withDependencies`.
    @TaskLocal public static var current = DependencyValues()

    /// The fallback context for unoverridden keys. Defaults to `.live`.
    public var context: DependencyContext = .live

    /// A container consulted for keys that are not overridden. Registrations on
    /// it win over the context default.
    public var container: (any Container)?

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
            if let found = container?.resolveIfRegistered(key) {
                return found
            }
            // Nothing registered: fall back to the context default.
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

/// Async overload of `withDependencies`. `operation` runs on the caller's actor.
@discardableResult
public func withDependencies<R>(
    isolation: isolated (any Actor)? = #isolation,
    _ mutate: (inout DependencyValues) -> Void,
    operation: () async throws -> R
) async rethrows -> R {
    var values = DependencyValues.current
    mutate(&values)
    return try await DependencyValues.$current.withValue(values, operation: operation, isolation: isolation)
}

/// Test-focused sugar: switches the context to `.test` (so unoverridden keys
/// resolve to their `testValue`), unbinds any inherited container, then applies
/// any explicit overrides. Bind a container inside `mutate` to opt back in.
///
///     await withTestDependencies {
///         $0.apiClient = .mock(user: .stub)
///     } operation: {
///         // unoverridden deps use their testValue; apiClient is the mock
///     }
@discardableResult
public func withTestDependencies<R>(
    isolation: isolated (any Actor)? = #isolation,
    _ mutate: (inout DependencyValues) -> Void = { _ in },
    operation: () async throws -> R
) async rethrows -> R {
    try await withDependencies(isolation: isolation) {
        $0.context = .test
        $0.container = nil
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
        $0.container = nil
        mutate(&$0)
    } operation: {
        try operation()
    }
}

// =============================================================================
// MARK: - Optional: Vapor-style scoped container (make / register)

// =============================================================================
//
// The explicit setup style. Use it when you need lazy factories with explicit
// singleton/transient scoping and an app→request fallback hierarchy. Bind a
// container with `withDependencies { $0.container = app }` and `@Dependency`
// resolves its registrations through the same keys.

/// A scope that owns a `ServiceStorage` and may delegate unresolved lookups upward.
public protocol Container: AnyObject, Sendable {
    /// This scope's storage (holds factories and cached singletons).
    var storage: ServiceStorage { get }
    /// The enclosing scope to fall back to (e.g. a request's application).
    var parent: (any Container)? { get }
    /// Resolves a registered service, or returns `nil`. A requirement (not just
    /// an extension method) so calls through `any Container` reach custom
    /// conformers; the default implementation walks `storage` then `parent`.
    func resolveIfRegistered<K: StorageKey>(_ key: K.Type) -> K.Value?
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
    let onShutdown: (@Sendable (Service) -> Void)?
}

/// Builds a singleton once: the first caller holds the cell's lock while the
/// factory runs, later callers wait and then read the same instance.
private final class OnceCell<Value: Sendable>: Sendable {
    private let state = Lock<Value?>(nil)

    func value(build: () -> Value) -> Value {
        state.withLock { value in
            if let value {
                return value
            }
            let created = build()
            value = created
            return created
        }
    }
}

private struct CellKey<K: StorageKey>: StorageKey {
    typealias Value = OnceCell<K.Value>
}

/// Two distinct generic specialisations give each `StorageKey` two slots —
/// one for its factory, one for its cached singleton — for free and type-safely.
private struct FactoryKey<K: StorageKey>: StorageKey {
    typealias Value = Factory<K.Value>
}

private struct CacheKey<K: StorageKey>: StorageKey {
    typealias Value = K.Value
}

private struct ResolutionID: Hashable {
    let container: ObjectIdentifier
    let key: ObjectIdentifier
}

/// The (container, key) factories currently running on this task, so a factory
/// that resolves its own key fails fast instead of overflowing the stack.
private enum ResolutionStack {
    @TaskLocal static var active: Set<ResolutionID> = []
}

extension Container {
    /// Registers a factory for a service (Vapor calls this `use`).
    ///
    ///     app.register(DatabaseKey.self) { _ in PostgresDatabase(url: url) }
    ///     app.register(UserRepoKey.self) { c in
    ///         SQLUserRepository(db: c.make(DatabaseKey.self))   // pulls a dep
    ///     }
    public func register<K: StorageKey>(
        _ key: K.Type,
        scope: Factory<K.Value>.Scope = .singleton,
        onShutdown: (@Sendable (K.Value) -> Void)? = nil,
        _ build: @escaping @Sendable (any Container) -> K.Value
    ) {
        storage.set(FactoryKey<K>.self, to: Factory(scope: scope, build: build, onShutdown: onShutdown))
    }

    /// Resolves a service if one is registered here or on a parent, running its
    /// factory (and caching it, if a singleton). Returns `nil` otherwise.
    ///
    /// Resolution walks up to `parent` when the key is not registered locally,
    /// so a request resolves application-level singletons transparently.
    ///
    /// Singleton factories run under root `DependencyValues` (no overrides, this
    /// container bound) so a caller's overrides are never captured in a cached
    /// instance; transient factories see the caller's values.
    ///
    /// - Note: Factories run **outside** the storage lock, so a factory that
    ///   recursively `make`s a *different* key cannot deadlock. A singleton is
    ///   built exactly once even under concurrent first use; concurrent callers
    ///   wait for the first build. Its `onShutdown` hook runs on `shutdown()`.
    public func resolveIfRegistered<K: StorageKey>(_ key: K.Type) -> K.Value? {
        if let factory = storage.get(FactoryKey<K>.self) {
            switch factory.scope {
            case .transient:
                return build(key, factory, values: DependencyValues.current)
            case .singleton:
                if let cached = storage.get(CacheKey<K>.self) {
                    return cached
                }
                ensureNotResolving(key)
                var root = DependencyValues()
                root.container = self
                let cell = storage.value(CellKey<K>.self) { OnceCell() }
                return cell.value {
                    let instance = build(key, factory, values: root) // built without the storage lock
                    storage.set(CacheKey<K>.self, to: instance, onShutdown: factory.onShutdown)
                    return instance
                }
            }
        }
        return parent?.resolveIfRegistered(key)
    }

    /// Traps if this (container, key) is already being built on the current
    /// task. Checked before taking a singleton's cell lock, which would
    /// otherwise deadlock on re-entry.
    private func ensureNotResolving<K: StorageKey>(_ key: K.Type) {
        let id = ResolutionID(container: ObjectIdentifier(self), key: ObjectIdentifier(key))
        guard !ResolutionStack.active.contains(id) else {
            fatalError("Recursive resolution of \(K.self).")
        }
    }

    /// Runs `factory` with `values` bound.
    private func build<K: StorageKey>(
        _ key: K.Type,
        _ factory: Factory<K.Value>,
        values: DependencyValues
    ) -> K.Value {
        ensureNotResolving(key)
        let id = ResolutionID(container: ObjectIdentifier(self), key: ObjectIdentifier(key))
        return ResolutionStack.$active.withValue(ResolutionStack.active.union([id])) {
            DependencyValues.$current.withValue(values) {
                factory.build(self)
            }
        }
    }

    /// Resolves a service, trapping when nothing is registered.
    public func make<K: StorageKey>(_ key: K.Type) -> K.Value {
        guard let value = resolveIfRegistered(key) else {
            fatalError("No factory registered for \(K.self).")
        }

        return value
    }
}

/// Process-scoped container: singletons live for the lifetime of the app.
public final class AppScope: Container {
    public let storage = ServiceStorage()
    public let parent: (any Container)? = nil
    public init() {}

    /// Explicit teardown (drains every registered service's shutdown hook).
    public func shutdown() {
        storage.shutdownAll()
    }
}

/// Request-scoped container: layers per-request state over the application,
/// falling through to it for anything not registered locally.
public final class RequestScope: Container {
    public let storage = ServiceStorage()
    public let parent: (any Container)?
    public init(application: AppScope) {
        self.parent = application
    }
}
